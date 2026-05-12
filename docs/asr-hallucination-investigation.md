# ASR ハルシネーション調査レポート

調査日: 2026-05-12

---

## 概要

ローカル ASR として試したモデルがどちらも、実際には発話していない内容を文字起こし結果に
混入させる「ハルシネーション」問題を抱えている。
現時点では両者とも本番運用に耐える品質には達しておらず、チューニングまたは代替モデルの
検討が必要。

このドキュメントは将来の意思決定のための比較資料として残す。

---

## 試験済みモデル

### 1. Moonshine Base JA（現在稼働中）

**実装**: `MoonshineSherpaTranscriber` + `scripts/moonshine_transcribe.py`
**モデル**: `csukuangfj2/sherpa-onnx-moonshine-base-ja-quantized-2026-02-27`
**移行経緯**: Whisper より軽量・高速なため 2026-05-10 に移行（`asr-migration-moonshine.md` 参照）

#### 症状

- **発話末尾への余計な一言の追加**: 話し終わった後に「そうですね、その」のような
  会話的フィラーや、全く関係のない文章が付加される
- **追加された部分は必ず途中で終わる**: 完結した文として終わることがなく、
  常に文の途中で切れる
- **短い発話ほど顕著**: 「あいうえお」のような短い発話では、実際の内容より
  長い幻覚テキストが追加される場合がある
- **発生頻度**: ほぼ 100%

#### 再現テスト（2026-05-12 実施）

```bash
# 純粋な無音 WAV で実行した結果
無音 0.5 秒 → 「疖
無音 2.0 秒 → 「私のことですよ」と、彼は言った。「それは私
実音声 3 秒 → （実際の発話内容）未来の        ← 実内容に続いて幻覚が付く
実音声 5 秒 → （実際の発話内容）に実行可能なクリアな意思決定を与えられたか
```

無音から完全に架空の小説テキストを生成することを確認。

#### 根本原因

Moonshine は encoder-decoder アーキテクチャ。エンコーダーが音声を
hidden state に変換し、デコーダーがトークンを自己回帰的に生成する。

問題はデコーダーの EOS（文終端トークン）検出にある:

1. 量子化（4bit 相当）により EOS トークンの確信度スコアが低下している
2. デコーダーは EOS を出力する前に「次の日本語として最もありそうな単語」を
   生成し続ける
3. モデルのトークン上限（推定 100〜150 トークン）に達した時点で強制終了する
4. 強制終了するため、追加テキストは常に「途中で切れた」形になる

音声内容ではなく「日本語の会話として自然な続き」を生成するため、
学習データ（小説・対話コーパス等）に引っ張られた文章が出やすい。

#### 試みた緩和策

現時点では後処理による緩和策は実装していない。
以下のアプローチが技術的には可能:

- **長さ比率トリミング**: 音声長から期待文字数を計算し（日本語: 約 7 文字/秒）、
  超過分を最終文末記号（。！？）で切る
  - リスク: 長い発話では本物の末尾が削られる可能性がある
- **会話フィラー検出**: 「そうですね」「なるほど」等のパターンを正規表現で除去
  - リスク: パターンが有限で、任意の幻覚には対応できない
- `sherpa_onnx.OfflineRecognizer.from_moonshine_v2()` には EOS しきい値や
  ビームサイズ等のパラメータが公開されていない

---

### 2. Whisper small（旧実装、現在コードは残存）

**実装**: `WhisperCLITranscriber`（`AppRuntime.swift` の DI を変更すれば即切り戻し可能）
**モデル**: `whisper/small.pt`（244MB）

#### 症状

- **発話の冒頭または末尾への定型句の追加**: 実際には言っていない
  「ご清聴ありがとうございました」「ありがとうございました」等のフォーマル定型句が
  前後に挿入される
- **音楽・環境音の誤認識**: 無音や環境音を音楽や拍手と誤認識し、
  字幕的な記述（「♪〜」等）を出力することがある
- Whisper 固有の `no_speech_prob` チェック・trailing silence 除去等の
  ハードニングは実装済みだが、フォーマル定型句の混入は残存する

#### 根本原因

Whisper は英語講演・スピーチのコーパスで訓練されており、
日本語会議音声に対しては「発表・講演」のコンテキストとして解釈しやすい。
結果として発表の締めくくりフレーズ（「ご清聴ありがとうございました」等）を
hallucinate する傾向がある。

Whisper small (244M params) を日本語会議に使う場合の既知問題で、
large-v3 でも発生するが頻度は下がる傾向がある。

---

## 現時点の評価まとめ

| 観点 | Moonshine Base JA | Whisper small |
|---|---|---|
| 発話内容の転写精度 | 高（実音声部分は正確） | 中（日本語精度は低くない） |
| ハルシネーション種別 | 末尾に会話的フィラーや架空テキスト | 冒頭・末尾にフォーマル定型句 |
| 発生頻度 | ほぼ 100% | 頻繁（短い発話で特に多い） |
| 処理速度 | 速い（RTF ≈ 0.02） | 遅い（6〜8秒/発話、CPU） |
| 後処理で改善可能か | 部分的（末尾パターンなら） | 部分的（定型句フィルターなら） |
| コードベースでの切り替え | 現在稼働中 | `AppRuntime.swift` 1行で復帰可能 |

**結論**: 現時点ではどちらも同程度に不便。Moonshine の方が速度面では有利だが、
品質面では同等の問題を抱えている。

---

## 今後の検討候補

### A. 現行モデルの後処理チューニング

Moonshine または Whisper を継続使用しつつ、スクリプト側で hallucination を除去する。

Moonshine 向け後処理のアイデア:
```python
# 案 1: 長さ比率チェック（音声長 × 期待文字数を超えたら末尾を除去）
MAX_CHARS_PER_SEC = 10
expected = int(duration_sec * MAX_CHARS_PER_SEC)
if len(text) > expected + 10:
    # 最終の 。！？ まで切り戻す
    ...

# 案 2: 文末記号以降の短い不完全フレーズを除去
# 。や！で終わっていなければ末尾の N 文字を疑う
```

Whisper 向け後処理のアイデア:
```python
# 案: 既知の定型句を頭・末尾から除去
FORMAL_CLOSINGS = ['ご清聴ありがとうございました', 'ありがとうございました', '以上です']
for phrase in FORMAL_CLOSINGS:
    text = text.strip(phrase)  # 前後から除去
```

### B. Moonshine Tiny JA への切り替え

- モデル: `sherpa-onnx-moonshine-tiny-ja-quantized`（未試験）
- サイズ: Base より小さい（Base の約半分）
- 仮説: アーキテクチャが小さいほどトークン生成が保守的になる可能性がある
- リスク: 精度が Base より低くなる可能性がある

試験方法: Base JA と同じテスト WAV で比較実行する。

### C. Whisper large-v3 または turbo

- `whisper-large-v3` または `whisper-large-v3-turbo` は日本語精度が high
- hallucinate する定型句の頻度が small より低い可能性がある
- ただしモデルサイズが大きい（large-v3: 1.5GB）
- Apple Silicon では Core ML 変換版（whisper.cpp 経由）で速度改善の可能性あり

### D. faster-whisper / whisper.cpp

- `faster-whisper`: CTranslate2 ベース、CPU でも Whisper より高速
- `whisper.cpp`: C++ 実装、Apple Silicon Metal 対応
- どちらも `initial_prompt` で「これは日本語の社内会議の音声です」などを渡せる
- `initial_prompt` で hallucination を抑制する既知のテクニックがある

```bash
# faster-whisper の例
faster-whisper transcribe audio.wav \
  --language ja \
  --initial_prompt "これは日本語の社内会議の音声です。" \
  --no_speech_threshold 0.6
```

### E. SenseVoice（sherpa-onnx 経由、実績あり）

- 開発: Alibaba FunAudioLLM
- アーキテクチャ: CTC ベース（encoder-decoder ではないため hallucination が構造的に起きにくい）
- 対応言語: 日本語・中国語・英語・韓国語・広東語（多言語）
- モデル: `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09`（int8 量子化）
- **実績**: 同プロジェクトの Android スタンドアロン版（`xtrust/app/android-standalone/`）で
  sherpa-onnx + SenseVoice を実際に動作させた記録がある（`docs/session-log.md` 参照）
- Mac 版への移植は `MoonshineSherpaTranscriber` と同じ sherpa-onnx 呼び出しパターンで可能
- Python 側の変更点: `from_moonshine_v2()` → `from_sense_voice_v2()` への切り替え

```python
# SenseVoice 用の recognizer 初期化例
def make_recognizer(model_dir):
    return sherpa_onnx.OfflineRecognizer.from_sense_voice_v2(
        model=os.path.join(model_dir, "model.int8.onnx"),
        tokens=os.path.join(model_dir, "tokens.txt"),
        language="ja",
        use_itn=True,
        num_threads=4,
    )
```

- Android 側で確認された問題: CJK 文字間に余分なスペースが入る場合がある
  → `MoonshineSherpaTranscriber` に実装済みの CJK スペース除去処理（`_CJK_SPACE_RE`）で対応可能

### F. SpeechBrain / ESPNET / k2 系の日本語 CTC モデル

- CTC（Connectionist Temporal Classification）アーキテクチャは encoder-decoder より
  hallucination が起きにくい
- decoder が自己回帰的に生成しないため、音声に存在しないトークンを生成しない
- 日本語 CTC モデルの候補:
  - `pyannote/speech-brain`
  - `reazon-research/reazonspeech-nemo-v2`（日本語特化、NeMo ベース）
  - `julius` の DNN-HMM ハイブリッド

### F. ReazonSpeech（最有力候補）

- 開発: レアゾンホールディングス
- 学習データ: 日本語コーパス 35000 時間（最大規模クラス）
- モデル形式: NeMo CTC
- hallucination リスク: CTC アーキテクチャのため構造的に低い
- ローカル動作: 可能（pip install reazon-speech）
- 参考: https://research.reazon.jp/projects/ReazonSpeech/

```bash
pip install reazonspeech-nemo-v2
python3 -c "
from reazonspeech.nemo.asr import load_model, transcribe, audio_from_path
model = load_model()
audio = audio_from_path('audio.wav')
print(transcribe(model, audio).text)
"
```

---

## 切り替え手順（Moonshine ↔ Whisper）

`AppRuntime.swift` の transcriber 初期化箇所を変更するだけで切り替え可能。
`WhisperCLITranscriber.swift` と `MoonshineSherpaTranscriber.swift` は
どちらも現在コードベースに残っている。

```swift
// Moonshine（現在）
let moonshineTranscriber = MoonshineSherpaTranscriber(
    configuration: .developmentDefault(modelsRootDirectory: modelsRoot)
)

// Whisper に戻す場合
// let whisperTranscriber = WhisperCLITranscriber(
//     configuration: .developmentDefault(modelsRootDirectory: modelsRoot)
// )
```

新しいモデルを試す場合は `Transcriber` プロトコルを実装した新しいアダプターを
`Packages/AppCore/Sources/AppCore/Infrastructure/` に追加し、
`AppRuntime.swift` の DI 箇所を差し替える。

---

## 次のアクション候補

優先順位（提案）:

1. **SenseVoice（sherpa-onnx 経由）を Mac 版に移植する** ← 最有力
   - Android 版ですでに sherpa-onnx + SenseVoice を動作させた実績がある
   - CTC アーキテクチャで hallucination が構造的に起きにくい
   - 既存の `MoonshineSherpaTranscriber` とほぼ同じ構造でアダプターを実装できる
   - CJK スペース除去処理もすでに実装済み

2. **ReazonSpeech v2 を試験導入する**
   - 日本語特化・学習データ量が最大クラス
   - CTC アーキテクチャ（NeMo ベース）

3. **Moonshine に長さ比率後処理を追加して症状を緩和する**
   - 短期的な応急処置として有効
   - SenseVoice 試験と並行して実施可能

4. **faster-whisper + `initial_prompt` を試す**
   - Whisper の定型句問題を initial_prompt で抑制できるか検証する

---

## 関連ドキュメント

- `docs/asr-migration-moonshine.md` — Whisper → Moonshine 移行の詳細
- `Packages/AppCore/Sources/AppCore/Infrastructure/MoonshineSherpaTranscriber.swift`
- `Packages/AppCore/Sources/AppCore/Infrastructure/WhisperCLITranscriber.swift`
- `scripts/moonshine_transcribe.py`
