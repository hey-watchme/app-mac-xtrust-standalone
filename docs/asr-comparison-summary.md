# ローカル ASR 比較サマリー（調査依頼用）

作成日: 2026-05-12

---

## 背景・要件

macOS（Apple Silicon M1 Pro）上で動作する会議録音アプリのローカル ASR を探している。

**必須条件**
- 完全オフライン・ネットワーク不要
- 日本語の会議音声を認識できる
- Apple Silicon Mac（M1 Pro）で実用速度（RTF < 0.5 程度）で動く
- Python サブプロセスとして呼び出せる（既存の Swift アプリから subprocess で起動する構造）

**入力フォーマット**
- 16kHz・モノラル・16bit PCM WAV
- 1発話あたり 1〜10 秒程度（VAD で区切り済み）

---

## 試したモデルと問題点

### Whisper small（OpenAI）

- **実装**: Python `whisper` パッケージ、CPU 推論
- **速度**: 遅い。1発話（3〜5秒）の転写に 6〜8秒かかる
- **精度**: 日本語認識自体は悪くない
- **問題**: 発話の冒頭や末尾に言っていない定型句を勝手に付け加える
  - 例：「ご清聴ありがとうございました」「ありがとうございました」
  - 発表・講演コーパスで訓練されているため、会議音声を「発表」と解釈しやすい
  - `no_speech_threshold`・`condition_on_previous_text=False` 等のパラメータで一定抑制できるが、完全には解消しない
- **現状**: コードは残っているが、上記の問題で現在は非アクティブ

---

### SenseVoice（Alibaba FunAudioLLM）

- **実装**: sherpa-onnx 経由、`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8` モデル
- **実績**: Android 版で動作確認済み（Mac 版への移植は未実施）
- **速度**: 速い（CTC のため Whisper より高速）
- **精度**: 日本語認識は実用レベル
- **問題**: CJK 文字（漢字・かな）の間に余分なスペースが入る場合がある
  - 例：「会議 の 内容 を まとめ ます」のようになる
  - 後処理の正規表現（CJK 間スペース除去）でほぼ対応可能
- **hallucination**: CTC アーキテクチャのため、Whisper・Moonshine で見られる末尾への無関係テキスト付加は発生しにくい
- **現状**: Mac 版への移植が次の候補として有力

---

### Moonshine Base JA（UsefulSensors / sherpa-onnx）

- **実装**: sherpa-onnx 経由、`sherpa-onnx-moonshine-base-ja-quantized` モデル（量子化版）
- **速度**: 速い（RTF ≈ 0.02）、Whisper より大幅に高速
- **精度**: 発話内容の転写自体は正確
- **問題**: 発話末尾に言っていない文章を必ず付け加える（発生率ほぼ 100%）
  - 例：「あいうえお」と言うと「あいうえおそうですね、その」のようになる
  - 付加されたテキストは常に文の途中で終わる
  - 純粋な無音 2 秒を入力すると「私のことですよ」と、彼は言った。「それは私」のような架空の小説テキストを生成する
  - 原因：量子化により EOS トークンの確信度が低下し、モデルがトークン上限まで生成し続ける
- **現状**: 現在アクティブだが、上記の問題があり品質に課題あり

---

## まとめ表

| モデル | 速度 | 日本語精度 | hallucination | 現状 |
|---|---|---|---|---|
| Whisper small | 遅い | 良い | 冒頭・末尾に定型句 | 非アクティブ |
| SenseVoice int8 | 速い | 実用的 | 少ない（CTC） | Android のみ動作確認済み |
| Moonshine Base JA（量子化） | 速い | 良い | 末尾に必ず付加（深刻） | 現在アクティブ |

---

## 探しているもの

以下の条件を満たす日本語対応 ASR モデル・エンジンがあれば教えてほしい。

- **hallucination が少ない**（これが最優先）
- Apple Silicon Mac でオフライン動作する
- Python から呼び出せる（sherpa-onnx・faster-whisper・その他ライブラリ経由でも可）
- 実用的な速度（RTF < 0.5 程度）
- モデルサイズは問わない（数 GB まで許容）

候補として名前が挙がっているが未検証のもの:
- ReazonSpeech v2（NeMo CTC、日本語特化）
- faster-whisper + initial_prompt チューニング
- whisper.cpp（Apple Silicon Metal 対応）
- k2 / icefall 系 Zipformer
