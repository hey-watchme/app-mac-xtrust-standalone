# 要約ランタイム安全設計: クラッシュ防止アーキテクチャ

作成日: 2026-05-10 JST

---

## 背景

このマシンでローカル実行する MLX / Gemma 4 要約は、過去にホスト Mac を完全にフリーズ・クラッシュさせたことがある。再発防止として `MLXSummarizerConfiguration.requiredAvailableMemoryBytes = 8 GB` の事前チェックが導入されたが、これは下記の理由で**運用不能な状態**を生んだ。

1. 静的 8 GB 閾値は M1 Pro 16 GB 機の通常状態でほぼ常に不足側に判定される
2. macOS は使われていないメモリを積極的にキャッシュに転用するため、「空き」が小さいのは正常な状態であり、それを欠乏と解釈するのが誤り
3. 事前チェックは CPU 側の `host_statistics64()` だけを見ており、MLX が実際に使う Metal 経由の GPU バッファ確保を捉えていない (Apple Silicon は Unified Memory)

結果として、現在の実装は**過剰に保守的でありながら同時に盲点もある**という最悪の組み合わせで、要約機能が事実上動かない一方で、クラッシュ防止としても完全ではない。

---

## 要求の再定義

### ハード要件 (絶対)

- **ホスト Mac がクラッシュ・フリーズしない**

### ソフト要件 (許容)

- 要約自体の失敗 (途中で停止) は許容する
- 失敗時にユーザーに状況が伝わる

### 否定要件 (やってはいけない)

- 静的閾値で偽陽性ブロックを発生させない
- 利用可能な技術スタック (MLX, Metal, Gemma 4) を制限しない
- 「保守的に倒す」設計はしない (ギリギリまで攻める)

つまり「**攻めながら守る**」設計が必要。

---

## 設計原則

### 原則 1: メモリ判定はOSに委ねる

OS はメモリ全体 (CPU + GPU + 圧縮 + swap余地) を統合的に把握している唯一の主体である。アプリ側で同等の判断を再現することは不可能であり、再現を試みると保守的に過ぎるかリスクを見落とすかのどちらかになる。

したがってアプリは**判断する側ではなく、OSのシグナルに反応する側**に回る。

### 原則 2: クラッシュ防止の物理的根拠はサブプロセス分離

MLX は既に Python サブプロセスで動いている。これは天然の隔壁:

- サブプロセスを kill すれば確保メモリ (Metal 経由含む) は即解放される
- SwiftUI アプリ本体は生存する
- ホスト Mac は生存する

「Mac を守る」=「サブプロセスを適切なタイミングで kill できる」と等価である。

### 原則 3: 静的閾値は最低限の sanity check のみ

事前チェックは「明らかに無理な状況」だけを弾く軽い check に縮小する。判断の重みは実行中の監視に移す。

---

## アーキテクチャ: 多層防衛

```
[Layer 1: 起動前 sanity check]
  └─ 空きが極端に少ない (例: 500 MB 未満) または
     pressure が起動時点で .critical の場合のみブロック
↓ 通常 pass
[Layer 2: サブプロセス起動]
  ├─ MLX / Gemma 4 を Python サブプロセスでフルパワー起動
  └─ サブプロセス PID を Layer 3 監視に登録
↓
[Layer 3: 実行中 OS memory pressure 監視]
  ├─ DispatchSource memory pressure を購読
  ├─ .warning  → ログのみ、続行
  └─ .critical → サブプロセス PID に SIGKILL
↓
[Layer 4 (オプション): プロセスリソース上限]
  └─ setrlimit(RLIMIT_AS) を緩い上限で設定
     (Python インタプリタ暴走の保険)
```

### Layer 1: 最小事前チェック

**目的**: 起動時点で既に異常な状況だけを弾く。

**残すチェック**:
- モデルディレクトリ・Python 実行ファイルの存在確認 (既存)
- 起動時点の memory pressure level が `.critical` でないこと
- 空きメモリが極小値 (例: 500 MB) を下回っていないこと

**削除するチェック**:
- `requiredAvailableMemoryBytes = 8 GB` のような攻めない閾値
- `host_statistics64()` ベースの「Required vs Available」判定

### Layer 2: サブプロセス分離 (既存の活用)

既存の `MLXSummarizer.summarize()` のサブプロセス起動フローはそのまま流用する。追加するのは:

- サブプロセス起動直後に `MemoryPressureMonitor.register(pid:)`
- サブプロセス終了時 (正常 / kill / エラー) に `MemoryPressureMonitor.unregister(pid:)`

### Layer 3: OS Memory Pressure 監視 (本命)

```swift
let source = DispatchSource.makeMemoryPressureSource(
    eventMask: [.warning, .critical],
    queue: .global(qos: .userInteractive)
)
source.setEventHandler { [weak self] in
    let event = source.data
    if event.contains(.critical) {
        self?.killActiveSubprocesses(reason: "system memory pressure critical")
    } else if event.contains(.warning) {
        self?.logPressureWarning()
    }
}
source.resume()
```

**根拠**:
- `DispatchSource memory pressure` は macOS 自身が `.warning` / `.critical` を判定して通知する API
- Safari, Xcode, Photos など Apple 製アプリも利用している
- 閾値・ヒューリスティクスをアプリ側で決める必要がない

### Layer 4 (オプション): `setrlimit`

サブプロセス起動時に `RLIMIT_AS` を緩い上限 (例: 物理 RAM の 90%) で設定する。

**注意点**:
- Metal 経由の GPU バッファ確保は IOKit/カーネル領域を通るため、`setrlimit` で守れない可能性が高い
- これは Python インタプリタ自体の暴走 (リスト無限拡張など) に対する補助的保険
- 実装は任意。Layer 3 が機能していれば必須ではない

---

## コンポーネント設計

### 新規: `MemoryPressureMonitor`

配置: `Packages/AppCore/Sources/AppCore/Application/MemoryPressureMonitor.swift`

責務:
- DispatchSource memory pressure イベントの購読
- 監視対象 PID の登録 / 解除 (複数同時可)
- `.critical` 発火時に登録 PID 全てに SIGKILL
- pressure イベント・kill イベントの履歴を保持 (診断用)

公開 API (案):
```swift
public actor MemoryPressureMonitor {
    public init()

    public func register(pid: pid_t, label: String)
    public func unregister(pid: pid_t)

    public var currentLevel: MemoryPressureLevel { get }
    public func recentEvents(limit: Int) -> [MemoryPressureEvent]
}

public enum MemoryPressureLevel: Sendable {
    case normal
    case warning
    case critical
}

public struct MemoryPressureEvent: Sendable {
    public let timestamp: Date
    public let kind: Kind
    public enum Kind: Sendable {
        case pressureChanged(MemoryPressureLevel)
        case subprocessKilled(pid: pid_t, label: String, reason: String)
    }
}
```

### 変更: `MLXSummarizer`

1. `validateMemoryBudget()` を削除し、`validateLayer1Sanity()` に置き換え
   - 起動時 pressure level チェック
   - 空きメモリの極小値チェック (500 MB 程度)
2. サブプロセス起動直後に `monitor.register(pid:)`
3. サブプロセス終了時に `monitor.unregister(pid:)`
4. サブプロセスが SIGKILL で終了した場合は `MLXSummarizerError.killedByMemoryPressure` を投げる

### 変更: `MLXSummarizerError`

```swift
case insufficientMemory(...)        // ← 廃止
case killedByMemoryPressure(reason: String)  // ← 新規
case startupBlockedBySystemPressure          // ← 新規 (Layer 1)
```

### 変更: Diagnostics

- 現在の memory pressure level を表示
- 直近の pressure イベント履歴を表示
- 直近の subprocess kill 履歴を表示
- 既存の `MLX Required Memory` 表示は撤去 (静的閾値が消えるため)

### 変更: `AppRuntime`

- `MemoryPressureMonitor` をシングルトンとして起動時に生成
- `MLXSummarizer` と (将来的に) `MoonshineSherpaTranscriber` に注入

---

## 動作シナリオ

### S1: 通常ケース (現在ブロックされている状態)

1. ユーザーが要約ボタン押下
2. Layer 1: sanity check pass (現在 3.82 GB 空きでも pressure は normal)
3. Layer 2: Python サブプロセス起動、モニターに PID 登録
4. 要約完了、結果返却
5. PID をモニターから解除

→ **現在ブロックされているケースが正常に動く**

### S2: メモリ圧力発生ケース (本来ブロックすべき状況)

1. 要約実行中、システム全体のメモリ圧力が `.critical` に到達
2. Layer 3: モニターがイベント受信、サブプロセスに SIGKILL 送信
3. Python サブプロセス即終了、Metal 確保メモリ解放
4. SwiftUI 側は `MLXSummarizerError.killedByMemoryPressure` を受け取り、Topic を `summary_status = failed` に更新
5. UI にユーザー向けメッセージ表示 (例:「システムメモリ圧迫により要約を中止しました」)
6. **Mac は生存。SwiftUI アプリは生存。**

### S3: 起動時すでに critical (極端ケース)

1. ユーザーが要約ボタン押下
2. Layer 1: 起動時点で `.critical` を検出
3. `startupBlockedBySystemPressure` を返して起動拒否
4. UI にメッセージ表示

---

## リスクと未解決事項

### R1: `.critical` 発火から枯渇までの猶予時間

`.critical` から完全フリーズまで通常は数秒の余裕があるとされるが、Apple Silicon の SSD swap 速度では理論上 sub-second で枯渇する可能性もある。

**対応**:
- 実機検証で計測する
- 必要に応じて `.warning` 段階で先制 kill する設定を追加可能にする

### R2: 前回クラッシュの真因が不明

現在「クラッシュした」事実だけが記憶されており、それがカーネルパニックだったのかフリーズだったのか jetsam だったのかが不明。真因によって対策の重み付けが変わる。

**対応**:
- 実装着手前に `~/Library/Logs/DiagnosticReports/` を確認する
- 真因が分かれば本ドキュメントに追記する

### R3: Metal 側独自シグナルの扱い

`MTLDevice` には GPU memory pressure に該当する直接的なシグナルがない。Apple Silicon は Unified Memory なので OS memory pressure に GPU 側状況も統合されている認識だが、これは仮定であり要検証。

**対応**:
- 仮定を文書化 (本項)
- 実機検証で挙動を確認

### R4: 複数 LLM 並走の将来

現在 `SerializedSummarizer` で要約は直列化されているが、将来的に他のローカル LLM (例: 別モデルでのチェック) が並走する設計に変わった場合、kill 対象 PID の優先順位設計が必要になる。

**対応**:
- 現時点では SerializedSummarizer を維持
- `MemoryPressureMonitor.register()` の `label` で識別子を持たせ、将来の優先順位拡張に備える

---

## 受け入れ基準

実装完了の判定:

- [ ] 通常使用 (空き 1〜4 GB, pressure normal) で要約が成功する
- [ ] 意図的にメモリを圧迫した状態 (例: `stress-ng --vm 4 --vm-bytes 12G`) で要約を起動しても Mac がクラッシュしない
- [ ] 上記圧迫状態でサブプロセスが kill され、SwiftUI 側に `killedByMemoryPressure` として伝わる
- [ ] Diagnostics 画面で memory pressure level と kill 履歴が確認できる
- [ ] 既存の `SerializedSummarizer` 直列化動作は維持される
- [ ] `swift test` が全件通過する (新規ユニットテスト含む)

---

## スコープ外

- ASR (Moonshine Base JA) 側のクラッシュ防止
  - 現状 134 MB モデルでクラッシュリスク低
  - 必要になれば同パターンを適用
- CPU 過負荷検知
- ディスク full 検知
- Real auth 統合 (Milestone 15 で扱う)

将来ローカル LLM が大型化した場合や、ASR が大型化した場合は本パターンを横展開する。

---

## マイルストーンとの関係

本作業は Milestone 11 (Capture session refactor) と独立しており、運用ブロッカーとして優先度が高い。

実装着手前に以下を順に行う:

1. (本ドキュメントのレビュー)
2. クラッシュログ調査 (`~/Library/Logs/DiagnosticReports/`)
3. 実装プラン詳細化 (`implementation-plan.md` への追記)
4. 実装
5. 圧迫テスト

---

## 参考

- Apple Developer Documentation: [DispatchSource memory pressure](https://developer.apple.com/documentation/dispatch/dispatchsource/memorypressureevent)
- macOS Internals: jetsam (kernel-level OOM killer)
- 既存セクション: `architecture.md` "Summary runtime safety"
