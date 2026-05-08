# MLX への移行計画（LiteRT-LM → MLX-LM）

Date: 2026-05-08 JST

## なぜ MLX の方が良いか

LiteRT-LM は Google の汎用オンデバイスランタイム（Android/iOS/Desktop 向け）。
MLX は Apple が Apple Silicon 専用に設計した ML フレームワーク。

| 観点 | LiteRT-LM | MLX |
|------|-----------|-----|
| 設計対象 | クロスプラットフォーム | Apple Silicon 専用 |
| GPU | Metal（汎用パス） | Metal（ネイティブ最適化） |
| メモリ | CPU/GPUメモリ分離 | Unified Memory を直接活用 |
| モデル管理 | `.litertlm` 独自フォーマット | HuggingFace 標準 safetensors |
| コミュニティ | Google 主導 | mlx-community（活発） |

Apple Silicon の Unified Memory（CPUとGPUがメモリを共有）を最大限に活かせるのは MLX。
LiteRT-LM ではモデルウェイトのコピーオーバーヘッドが残る。

## 移行先の仕様

### インストール
```bash
pip install mlx-lm
```
Python 3.9 以上、arm64 ネイティブ版必須（Rosetta 不可）。

### モデル
```
mlx-community/gemma-4-e4b-it-4bit
```
- サイズ: 約 4.86 GB（現在の LiteRT-LM モデル 3.4GB より約 1.5GB 大きい）
- フォーマット: safetensors（HuggingFace 標準）
- M1 Pro 16GB 統合メモリで余裕あり

### CLI インターフェース
```bash
# 基本構文
mlx_lm.generate \
  --model /path/to/local/model \
  --prompt "プロンプトテキスト" \
  --max-tokens 512

# HuggingFace 直接参照（初回ダウンロードあり）
mlx_lm.generate \
  --model mlx-community/gemma-4-e4b-it-4bit \
  --prompt "プロンプトテキスト"
```

**重要**: `mlx_lm.generate` はバイナリではなく Python モジュール。
Swift から呼ぶ場合は `python3 -m mlx_lm.generate ...` の形式になる。

### ローカルパスへのダウンロード（local-first 原則維持）
```bash
hf download mlx-community/gemma-4-e4b-it-4bit \
  --local-dir "$HOME/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/gemma4-mlx/"
```

## Swift 実装の変更差分

### 変更が必要なファイル
`XTrustMacApp/Shared/LiteRTLMSummarizer.swift` を `MLXSummarizer.swift` に置き換える。

### プロセス呼び出しの変更
```swift
// 現在 (LiteRT-LM)
process.executableURL = URL(fileURLWithPath: "/path/to/litert-lm")
process.arguments = [
    "run", modelPath,
    "--prompt", prompt,
    "--backend", "gpu",
]

// 移行後 (MLX-LM)
process.executableURL = URL(fileURLWithPath: "/path/to/python3")
process.arguments = [
    "-m", "mlx_lm.generate",
    "--model", modelDirectory,   // ローカルパスまたは HF repo ID
    "--prompt", prompt,
    "--max-tokens", "512",
]
```

### 設定クラスの変更点
```swift
struct MLXSummarizerConfiguration: Sendable {
    let pythonExecutablePath: String  // python3 のパス
    let modelDirectory: String        // モデルの local dir
}
```

`executablePath` が `litert-lm` バイナリから `python3` に変わる。
モデル参照が `.litertlm` ファイルパスからディレクトリパスに変わる。

### 出力パースの注意点
`mlx_lm.generate` の stdout には余分なメタデータが含まれる可能性がある。
実際の出力を確認してからパース処理を追加する（先頭行の除去など）。

### Diagnostics の変更
`gemmaModelPath` → `mlxModelDirectory` にリネーム。
ファイル存在確認 → ディレクトリ存在確認に変更。

## 移行手順（次セッションでやること）

1. **MLX-LM インストール**
   ```bash
   pip install mlx-lm
   ```

2. **モデルダウンロード**
   ```bash
   hf download mlx-community/gemma-4-e4b-it-4bit \
     --local-dir "$HOME/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/gemma4-mlx/"
   ```

3. **CLI 動作確認**
   ```bash
   python3 -m mlx_lm.generate \
     --model "$HOME/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/gemma4-mlx/" \
     --prompt "日本語で「テスト成功」と一言だけ答えてください。" \
     --max-tokens 64
   ```
   stdout の実際の出力フォーマットを確認する（パース設計のため）。

4. **`MLXSummarizer.swift` を新規作成**（`LiteRTLMSummarizer.swift` を参考に）

5. **`AppRuntime.swift` で差し替え**

6. **旧モデルの削除（任意）**
   ```bash
   rm -rf "$HOME/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/gemma4/"
   ```

## 既存 LiteRT-LM 実装の保持方針

移行が完了し動作確認できるまで `LiteRTLMSummarizer.swift` は残す。
`AppRuntime.swift` のコンストラクタで差し替えるだけなので、ロールバックは容易。

## 未確認事項（次セッションで確認）

- `mlx_lm.generate` の stdout 出力フォーマット（メタデータ混入有無）
- Thinking トークン（`<thinking>...</thinking>`）の出力有無と除去方法
- `--max-tokens` の適切な値（会議要約用途）
- M1 Pro での実際のトークン生成速度（LiteRT-LM との比較）
- python3 のパス解決（pyenv 環境での `python3 -m` の挙動）
