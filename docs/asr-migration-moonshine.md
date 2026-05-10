# ASR移行: Whisper → Moonshine Base JA (sherpa-onnx)

作業日: 2026-05-10

---

## 概要

ローカルASR（音声認識）を Whisper CLI から Moonshine Base JA（sherpa-onnx 経由）に置き換えた。
既存の `Transcriber` プロトコルのアダプター差し替えのみで完結しており、
`TranscriptionJobRunner`・ドメインモデル・VAD・UIには変更なし。

---

## なぜ移行したか

| 比較項目 | Whisper small | Moonshine Base JA |
|---|---|---|
| モデルサイズ | ~244MB (.pt) | ~134MB (.ort x2) |
| パラメータ数 | 244M | 61.5M |
| 日本語精度(CER) | —（参考値として優秀） | 13.62%（FLEURS） |
| 処理速度(RTF) | 遅い（CPU） | 約 0.016〜0.026（CPU） |
| VAD必要性 | 任意 | 必須（ONNX 10秒上限あり） |
| ffmpeg依存 | あり | なし |

Moonshine は英語だと Whisper Large-v3 相当の精度をパラメータ数 1/6 で実現するモデル。
日本語向けは「Flavors of Moonshine」世代（v1 アーキテクチャ）の Base JA (61.5M params)。

既存アーキテクチャが VAD 済みの短い発話単位（3秒無音区切り）で WAV を渡す設計のため、
Moonshine の ONNX 10秒上限問題は実質的に回避されている。

参考記事: [Moonshine Voice ASR を sherpa-onnx で動かして日本語文字起こしする完全ガイド (Zenn 2026-03-10)](https://zenn.dev/tubome/articles/moonshine-sherpa-onnx-japanese)

---

## 環境前提

| 項目 | 値 |
|---|---|
| マシン | MacBook Pro M1 Pro |
| OS | macOS Darwin 25.4.0 (Sequoia) |
| Python | 3.11.8 (pyenv) |
| sherpa-onnx | 1.13.1 (pip, arm64 wheel) |

### インストール済み依存

```bash
pip install sherpa-onnx   # sherpa-onnx-core 同梱、arm64 wheel
```

`pip check` で確認される競合（numba/numpy、python-jose/pyasn1）は移行前から存在していたものであり、
sherpa-onnx 自体の動作に影響しない。

---

## モデルファイル

### 配置先

```
~/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/moonshine-base-ja/
├── encoder_model.ort      (30MB)
├── decoder_model_merged.ort  (104MB)
├── tokens.txt             (536KB)
└── test_wavs/0.wav        (サンプル音声 44100Hz)
```

### ダウンロード方法

```python
from huggingface_hub import snapshot_download
import os

snapshot_download(
    repo_id='csukuangfj2/sherpa-onnx-moonshine-base-ja-quantized-2026-02-27',
    local_dir=os.path.expanduser(
        '~/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/moonshine-base-ja'
    ),
    ignore_patterns=['*.md', '.gitattributes'],
)
```

`git lfs` は不要。`huggingface_hub` が既にインストール済みであれば上記で取得できる。

---

## 変更したファイル一覧

### 新規作成

| ファイル | 説明 |
|---|---|
| `scripts/moonshine_transcribe.py` | Python 文字起こしスクリプト（参照用・バックアップ） |
| `Packages/AppCore/Sources/AppCore/Infrastructure/MoonshineSherpaTranscriber.swift` | `Transcriber` プロトコルの新実装 |

### 変更

| ファイル | 変更内容 |
|---|---|
| `XTrustMacApp/App/AppRuntime.swift` | `whisperTranscriber` → `moonshineTranscriber` に差し替え |
| `XTrustMacApp/App/AppState.swift` | 同上（プロパティ・init・refreshDiagnostics） |
| `XTrustMacApp/App/AppDiagnostics.swift` | `whisperModelPath/Ready` → `moonshineModelDirectory/Ready` |
| `XTrustMacApp/Shared/DiagnosticsView.swift` | ラベルを "Whisper Model" → "Moonshine Model" に更新 |

### 削除・無効化

- `WhisperCLITranscriber.swift` はそのまま残っている（削除していない）。
  将来 Whisper に戻す場合は `AppRuntime.swift` の DI 箇所を差し替えるだけでよい。

---

## アーキテクチャ

```
AVAudioCaptureController (VAD: RMS 0.01, 無音3秒)
  ↓ utteranceFinalized イベント（16kHz mono WAV）
CaptureRuntime
  ↓
TranscriptionJobRunner
  ↓ Transcriber プロトコル経由
MoonshineSherpaTranscriber
  ↓ Process() でサブプロセス起動
python3 moonshine_transcribe.py <wav> <job_dir> <model_dir>
  ↓ sherpa-onnx OfflineRecognizer.from_moonshine_v2()
  ↓ 結果を <job_dir>/<basename>.txt に書き出し
TranscriptionJobRunner が .txt を検証・昇格
  ↓
TranscriptArtifactStore（SQLite + transcripts/）
```

### Python スクリプトの動作

`scripts/moonshine_transcribe.py` の引数:
```
python3 moonshine_transcribe.py <audio_file> <output_dir> <model_dir>
```

- 16kHz mono 16-bit PCM WAV を読み込む
- sherpa-onnx `OfflineRecognizer.from_moonshine_v2()` で Moonshine Base JA を呼ぶ
- 8.5秒超えのセグメントは 0.9秒オーバーラップで分割（ONNX 10秒制限の安全策）
- CJK 文字間のスペースを正規表現で除去
- `<output_dir>/<audio_basename>.txt` に書き出す
- stdout にも同じテキストを出力

スクリプト本体は `MoonshineSherpaTranscriber.swift` 内に `pythonScriptContent` として埋め込んでいる。
アプリ起動時に `developmentDefault()` が `{workspace_root}/scripts/moonshine_transcribe.py` に
自動展開するため、ユーザーによる手動配置は不要。

---

## MoonshineSherpaTranscriber の設計

### Configuration

```swift
public struct MoonshineSherpaTranscriberConfiguration: Sendable {
    public let pythonExecutablePath: String  // 直接バージョンパス（shimは使わない）
    public let scriptPath: String            // workspace/scripts/moonshine_transcribe.py
    public let modelDirectory: String        // models/moonshine-base-ja/
    public let language: String              // "ja"

    public var expectedEncoderPath: String   // modelDirectory/encoder_model.ort
}
```

### Python パス解決の重要な注意点

**pyenv shim (`~/.pyenv/shims/python3`) を使ってはいけない。**

理由: shim は内部で `bash pyenv-exec python3 ...` を実行するが、
macOS アプリから `Process()` で起動したサブプロセスには `PYENV_ROOT` などのシェル環境変数が
引き継がれない。その結果、`pyenv-exec` が Python バージョンを解決できずハングする
（プロセスが終了せず、Swift 側の `waitUntilExit()` が永遠にブロックされる）。

**正しい実装:** `~/.pyenv/versions/` を直接列挙し、バージョン名の降順で実行可能なパスを探す。

```swift
let pyenvVersionsRoot = "\(home)/.pyenv/versions"
let pyenvVersioned: [String] = {
    let versions = (try? FileManager.default.contentsOfDirectory(atPath: pyenvVersionsRoot)) ?? []
    return versions.sorted(by: >).map { "\(pyenvVersionsRoot)/\($0)/bin/python3" }
}()
let pythonCandidates = pyenvVersioned + [
    "/opt/homebrew/bin/python3",
    "/usr/local/bin/python3",
    "/usr/bin/python3",
]
let pythonPath = pythonCandidates.first { fileManager.isExecutableFile(atPath: $0) } ?? "python3"
```

この方法により `3.11.8/bin/python3`（sherpa-onnx インストール済み）が正しく選ばれる。

**症状（誤った実装の場合）:**
- ジョブが "running" のまま止まる
- タイマーが数秒〜十数秒でストップ
- コンソールに `throwing -10877`（Core Audio の別エラー）が見える
- `ps aux | grep pyenv-exec` で bash プロセスが残り続ける

---

## テスト結果

### コマンドラインテスト

```bash
# テスト音声（44100Hz → 16kHz 変換後）
ffmpeg -i <test.wav> -ar 16000 -ac 1 /tmp/test_16k.wav -y

python3 moonshine_transcribe.py /tmp/test_16k.wav /tmp/out /path/to/moonshine-base-ja
# 出力: 国があなたのために何ができるかを問うのではなく、あなたが国のために何ができるかを問うてください。
```

ケネディ大統領就任演説の日本語音声で正確な文字起こしを確認。

### アプリ内テスト

- VAD 録音 → 発話 → 自動文字起こし → テキスト表示: 成功
- `swift test`: 42テスト全通過
- `swift build`: エラーなし

### 処理時間

実際の発話（短い発話、数秒）で数秒以内に文字起こし完了を確認。
初回モデルロードは若干遅いが、2回目以降は高速。

---

## Diagnostics 画面

`Settings > Diagnostics` で以下を確認できる:

- `Moonshine Model`: モデルディレクトリのパス
- `Moonshine Model Ready`: `encoder_model.ort` の存在確認（Yes/No）

---

## 既知の制限・注意点

1. **句読点なし（モデル依存）**
   Moonshine Base JA は句読点を出力しないことがある（テストでは出力されたが保証なし）。

2. **固有名詞の精度**
   人名・地名の誤認識が Whisper より多い可能性がある。
   Whisper の `initial_prompt` に相当するヒント機能は Moonshine にない。

3. **ONNX 10秒制限**
   量子化 ONNX モデルは約 10秒超えの入力でエラーになる。
   既存の Swift VAD（3秒無音区切り）が自然に回避しているが、
   スクリプト内にも 8.5秒ハードカット + 0.9秒オーバーラップの安全策を入れている。

4. **Whisper は削除していない**
   `WhisperCLITranscriber.swift` は残っている。
   DI 箇所（`AppRuntime.swift` の `MoonshineSherpaTranscriber(...)` 行）を
   `WhisperCLITranscriber(...)` に戻すだけで元の動作に切り替えられる。

---

## 今後の課題（次のセッション以降）

- [ ] 正式な `docs/` ドキュメント更新（tech-stack-plan.md, architecture.md など）
- [ ] Moonshine Tiny JA との精度・速度比較（69MB、さらに軽量）
- [ ] `mlx-audio` を使った Gemma 4 audio ASR の実験（将来のマルチモーダル拡張）
- [ ] Milestone 11（Session → CaptureSession リファクタ）への移行
- [ ] pyenv バージョンを固定する設計への改善（現在は降順で最初の実行可能パスを選ぶ）

---

## ファイル変更サマリー（diffなし版）

### 新規: `MoonshineSherpaTranscriber.swift`

`Packages/AppCore/Sources/AppCore/Infrastructure/` に配置。
`Transcriber` プロトコルを実装する。Python スクリプト内容を `pythonScriptContent` として埋め込み、
`developmentDefault()` でワークスペースの `scripts/` ディレクトリに自動展開する。

### 変更: `AppRuntime.swift` / `AppState.swift`

```swift
// Before
let whisperTranscriber = WhisperCLITranscriber(
    configuration: .developmentDefault(modelsRootDirectory: modelsRoot)
)
// ...
transcriber: whisperTranscriber

// After
let moonshineTranscriber = MoonshineSherpaTranscriber(
    configuration: .developmentDefault(modelsRootDirectory: modelsRoot)
)
// ...
transcriber: moonshineTranscriber
```

### 変更: `AppDiagnostics.swift`

```swift
// Before
let whisperModelPath: String
let whisperModelReady: Bool
init(..., whisperConfiguration: WhisperCLITranscriberConfiguration, ...)

// After
let moonshineModelDirectory: String
let moonshineModelReady: Bool
init(..., moonshineConfiguration: MoonshineSherpaTranscriberConfiguration, ...)
```
