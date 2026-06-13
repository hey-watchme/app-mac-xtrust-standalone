# Mac Local-First Ambient Memo

Date: 2026-06-12 JST

This directory contains a standalone macOS local-first ambient memo product
line that is independent from WatchMe / ZeroTouch cloud infrastructure.

## Current status

The realtime meeting-transcription core has been rebuilt (2026-06):

- ASR now uses Apple `SpeechAnalyzer` / `SpeechTranscriber` — the macOS 26
  on-device streaming speech API (ja-JP) — producing live volatile partial
  results and finalized utterances. The previous Python ASR stack (Whisper /
  Moonshine via sherpa-onnx, per-utterance wav files, subprocess
  `TranscriptionJob` pipeline, RMS-threshold VAD) has been deleted.
- The domain root is `CaptureSession` (Milestone 11 complete). `Topic`,
  `TranscriptionJob`, and per-utterance recording/transcript artifacts are
  retired. `Utterance` carries transcribed text and time offsets directly,
  and each capture session records one wav file (`audio/<id>.wav`).
- Closing a meeting generates one Japanese meeting-minutes document
  (`MeetingMinutes`) with Gemma 4 E4B via a long-lived local
  `mlx_vlm.server`.
- The shared-device foundation remains: organization-owned,
  workspace-scoped, device-centered, short-lived operator access,
  privacy-safe between meetings (`Organization` / `Workspace` / `Device` /
  `Account` / `OrganizationMembership` / `AccessSession`).
- Local SQLite persistence is at schema v2 (`PRAGMA user_version`); legacy
  capture tables were dropped destructively in this rebuild.
- Deployment target is macOS 26 (built with Xcode 26.5).

Project layout:

- a real macOS Xcode project at `XTrustMacApp.xcodeproj`
- a native `SwiftUI` app target at `XTrustMacApp/`
- a testable core library as a local package at `Packages/AppCore/`

Technical stack and implementation planning are tracked in:

- `docs/product-requirements.md`
- `docs/architecture.md`
- `docs/tech-stack-plan.md`
- `docs/implementation-plan.md`
- `docs/milestones.md`
- `docs/testing-strategy.md`
- `docs/design-system.md`
- `docs/manual-verification.md`
- `docs/summary-runtime-safety.md`

## Why this project exists

This project establishes a laptop-first local-first product line, starting with
this MacBook M1 Pro and evolving toward an organization-managed shared-device
deployment model.

## Goal

Build a simple and robust local-first ambient memo device for macOS that can:

```text
Room device access
  -> capture meeting audio
  -> transcribe locally
  -> summarize locally
  -> show / print / export on-site
  -> reset safely for the next meeting
```

The first versions should prioritize privacy boundaries and operational
reliability over feature count.

## Product boundary

The macOS app should prove a stricter local-first posture than the cloud app.

Current redesign target:

- no required cloud API dependency for core capture
- no required backend service for local processing
- local storage for audio, transcript, summaries, and policy metadata
- local ASR
- local LLM summarization
- explicit local model paths under app-managed directories
- short-lived access on a shared room device
- strong privacy between consecutive meetings

Allowed later, but not required for v1:

- badge / SSO integration
- optional export
- optional manual model import or device bootstrap tooling
- optional system-audio / screen capture

## Decision

Create a separate sibling project here:

```text
/Users/kaya.matsumoto/projects/xtrust/app/mac-local-first/
```

Reason:

- the target OS, runtime, permissions, packaging, and UI conventions are
  different
- mixing Android and macOS assumptions in one app tree would make planning and
  maintenance harder

## Recommended app shape

Build a native macOS desktop app first.

Why:

- microphone, files, background work, and local model execution are easier to
  control than in a browser-only app
- local ASR / LLM orchestration is simpler and more robust in a desktop app
- the first version only needs one machine target: Apple Silicon macOS

## Restart guide

If you are resuming work from zero, read in this order:

1. `docs/product-requirements.md`
2. `docs/architecture.md`
3. `docs/implementation-plan.md`
4. `docs/milestones.md`
5. this `README.md`

The first PoC scope that is already complete was:

```text
Microphone input
  -> local wav recording
  -> local ASR
  -> transcript review
  -> local wrap-up summary
  -> local session save
```

The redesign intentionally revisited earlier assumptions. In particular:

- the old `Session` concept has been split into `AccessSession` and
  `CaptureSession`
- the app is no longer treated as a personal single-operator tool
- shared-device privacy and retention are now core product behavior

The original PoC did not yet include:

- accounts or workspace management
- cloud sync
- web dashboard integration
- multi-user collaboration
- realtime remote sharing
- diarization
- image or video understanding
- browser-first deployment

## Working assumptions

- primary machine: MacBook Pro with M1 Pro
- primary platform: macOS desktop
- current deployment target: one shared room device per room or field site
- current runtime mode: offline-capable and local-first

## Success criteria

- Japanese meeting audio can be transcribed at practical speed on the target Mac
- local meeting-minutes quality is strong enough for meeting-note review
- the app remains stable during normal meeting-length operation
- on-device results are available during the active meeting flow
- prior meeting content is not casually visible to the next room user
- retention and purge behavior become explicit and testable

## Relationship to other tracks

- this project is the Mac local-first / zero-trust-oriented line

## Suggested structure

```text
mac-local-first/
├── Package.swift
├── XTrustMacApp.xcodeproj
├── project.yml
├── XTrustMacApp/
├── Packages/
├── Tests/
├── Fixtures/
├── ThirdParty/
├── scripts/
├── README.md
└── docs/
    ├── product-requirements.md
    ├── architecture.md
    ├── implementation-plan.md
    ├── tech-stack-plan.md
    ├── milestones.md
    └── testing-strategy.md
```

## Current implementation status

Core meeting flow (implemented and working):

- locked shared-device screen (dark navy, XTRUST branding) -> begin local
  access -> `会議を開始` in the main content pane
- capture state pill in the header walks through: permission check -> speech
  asset check / download -> starting -> `録音中` (REC badge with live
  elapsed timer)
- live transcript: Slack-style feed where volatile (partial) text appears as
  a typing-indicator row at the bottom; each finalized utterance becomes a
  timestamped message row; the UI is event-driven
  (`AsyncStream<CaptureEngineEvent>` consumed by `MeetingStore`) with no
  polling
- `会議を終了して議事録を作成` -> Gemma 4 E4B (via the long-lived
  `mlx_vlm.server`) generates Japanese meeting minutes -> result displayed in
  the AI Insights Inspector (要約 tab); copy / export as Markdown
- interrupted minutes generation auto-recovers on relaunch
  (`running` -> `pending`, then re-run automatically)
- AI chat: the **XTRUST AI** entry in the sidebar DM section opens the chat
  panel backed by the same local Gemma 4 E4B model
- logout (退出 in the sidebar user strip) resets the shared UI and returns to
  the locked screen

Key components:

UI shell (`XTrustMacApp/Features/Shell/`):

- `WorkspaceRail`: decorative 60 px left rail with XTRUST logo and workspace
  tiles (placeholder workspaces for vision presentation)
- `SlackSidebar`: 264 px dark navy sidebar — mode switch (会議 / 資料),
  search, main nav, DEALS / PORTFOLIO channel groups, DM list (including
  XTRUST AI chat entry), user strip with 退出
- `SlackMeetingView`: main content column with `MeetingHeader` (breadcrumb,
  title, REC badge, status pills, stacked participant avatars), Slack-style
  transcript feed (`SlackTranscriptRow` for real utterances, `DemoTranscriptRow`
  for idle/demo state), `ComposerBar` (record start/stop, waveform driven by
  `audioLevel`, volatile caption, elapsed timer)
- `AIInspector`: 384 px collapsible right panel — 要約 tab shows real
  `MeetingMinutes` content; 決定 / アクション / リスク / ナレッジ tabs are
  placeholder cards for vision presentation

Core services (unchanged):

- `SpeechAnalyzerCaptureEngine` (app target, `XTrustMacApp/Capture/`):
  microphone capture, on-device streaming ASR, audio level metering, and one
  wav file per capture session
- `AppCore` (local package): domain (`CaptureSession`, `Utterance`,
  `MeetingMinutes`, shared-device entities) and services
  (`CaptureSessionService`, `LiveMeetingRecorder`, `MeetingMinutesService`,
  `MinutesRecoveryService`, `AccessSessionService`), backed by SQLite
- `MLXModelServer` / `MLXSummarizer` / `MLXChatRunner`: local LLM runtime as
  a long-lived `mlx_vlm.server` subprocess with idle teardown and
  memory-pressure kill (see `docs/llm-server-residency.md`)
- `Diagnostics`: speech asset status, Gemma 4 model readiness, MLX server
  state, recovered minutes count, and current organization / workspace /
  device / access scope
- UI design system (`XT` token namespace extended with Slack-style palette) —
  see `docs/design-system.md`

Verification:

- `swift build` and `swift test` at the repository root
- `xcodebuild -project XTrustMacApp.xcodeproj -scheme XTrustMacApp build`
- manual checks: see `docs/manual-verification.md`

Open in Xcode:

1. Open `XTrustMacApp.xcodeproj` in Xcode.
2. Select the `XTrustMacApp` scheme.
3. Run the app on `My Mac`.

Note:

- use `XTrustMacApp.xcodeproj` for running the app
- keep `Package.swift` for command-line build and test workflows only
- manual verification must use the Xcode-built app: the SPM (`swift run`)
  binary has no `Info.plist`, so microphone permission behaves differently
- for stable microphone permission retention, prefer `Signing Certificate:
  Development`; `Sign to Run Locally` may cause repeated permission prompts on
  this app

## Prerequisites

### ASR (no installation required)

Speech recognition uses the macOS on-device speech model
(`SpeechAnalyzer` / `SpeechTranscriber`, ja-JP). There is no ASR model file
to install: the OS downloads the ja-JP speech asset on first use, the app
shows the download progress in the capture state pill, and `Diagnostics`
shows the asset status (`Speech Locale Supported` / `Speech Assets
Installed`). Requires macOS 26.

### Gemma 4 E4B (local LLM minutes generation and chat)

The app does not download this model at runtime. Install Apple Silicon
native `python3`, `mlx-vlm`, and download the model before first use:

```bash
pip install mlx-lm mlx-vlm
hf download mlx-community/gemma-4-e4b-it-4bit \
  --local-dir "$HOME/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/gemma4-mlx/"
```

- use native arm64 `python3` on Apple Silicon; Rosetta-based Python is not
  supported for this path
- the app resolves a local model directory at
  `~/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/gemma4-mlx/`
  rather than a single model file
- the model is served by a long-lived `python3 -m mlx_vlm.server` subprocess
  owned by the app (see `docs/llm-server-residency.md`)

Diagnostics keys: `Gemma 4 MLX Model` / `Gemma 4 MLX Ready`

If the Gemma model directory is missing, minutes generation and chat will
fail with a direct local-path error instead of attempting a network
download.

## Investigation log

### MTP (Multi-Token Prediction) drafter — 2026-05-14

Google released MTP drafters for the Gemma 4 family on 2026-05-05, claiming up to 3x speedup via
speculative decoding. We investigated whether this could be integrated into the current stack.

**What was tried**

- `mlx_vlm 0.5.0` already supports `--draft-model`, `--draft-kind mtp`, and `--draft-block-size`
  in the CLI — no stack change required at the API level.
- Downloaded `mlx-community/gemma-4-E4B-it-assistant-bf16` (183 MB, 4-layer MTP head).
- Benchmarked against the current `gemma4-mlx` (4-bit quantized target) on M1 Pro 16 GB.

**Benchmark results (128-token generation, temperature 0)**

| Configuration | Generation | Accepted tokens/round | Wall time |
|---|---|---|---|
| 4-bit target, no drafter | — | — | 17.1 s |
| 4-bit target + bf16 drafter, block-size 2 | 24.9 t/s | 0.21 | 19.0 s |
| 4-bit target + bf16 drafter, block-size 3 | 19.5 t/s | 0.27 | 20.2 s |
| 4-bit target + bf16 drafter, block-size 4 | 15.4 t/s | 0.28 | 21.7 s |

**Root cause**

The MTP drafter is a 4-layer head that reads the target model's hidden states (dim 2560) directly.
It was trained against bf16 hidden states. When the target is 4-bit quantized the hidden state
distribution drifts enough that almost all draft predictions are rejected, producing a net slowdown.
The published drafter models are bf16-only; no 4-bit drafter for E4B is currently available.

**Conclusion**

MTP is not viable on the current hardware/model combination:

- bf16 target would require ~14–16 GB weights — not feasible on a 16 GB M1 Pro.
- 8-bit target (~9.7 GB) is worth retesting if acceptance rate improves to ≥ 1.5/round.
- The full 3× gain requires a 32 GB+ machine or a dedicated 4-bit-trained drafter.

No Swift code was changed. The drafter model was deleted after testing.

---

## Recommended next step

The realtime pipeline rebuild (SpeechAnalyzer migration + Milestone 11) is
complete.

Concrete next candidates:

- idle-timeout handling for the shared-device access session (Milestone 10
  remainder)
- Milestone 12: privacy-safe room flow
- Milestone 13: retention and purge policy

Current project state should be read as:

- Milestones 0-9: complete
- Milestone 10: partially complete (idle-timeout and real auth adapters open)
- Milestone 11: complete (`Session` → `CaptureSession`, done as part of the
  realtime pipeline rebuild)
- Chat feature: implemented as a standalone panel outside the milestone sequence

Use these documents as the source of truth:

- `docs/milestones.md`
- `docs/architecture.md`
- `docs/manual-verification.md`
- `docs/summarization-prompt-design.md`
- `docs/asr-comparison-summary.md` — ASR 比較サマリー（Whisper / SenseVoice / Moonshine の現状、調査依頼用・歴史的記録）
- `docs/asr-hallucination-investigation.md` — ASR ハルシネーション詳細調査（根本原因と代替候補・歴史的記録）

Note: the ASR hallucination problem documented in the two ASR investigation
docs was resolved by migrating ASR to Apple `SpeechAnalyzer`; they are kept
as history.
