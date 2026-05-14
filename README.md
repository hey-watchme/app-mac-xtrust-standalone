# Mac Local-First Ambient Memo

Date: 2026-05-10 JST

This directory contains a standalone macOS local-first ambient memo product
line that is independent from WatchMe / ZeroTouch cloud infrastructure.

## Current status

This project has completed the first end-to-end local meeting notes PoC
vertical slice through the original Milestone 7:

- a real macOS Xcode project at `XTrustMacApp.xcodeproj`
- a native `SwiftUI` app target at `XTrustMacApp/`
- a testable core library as a local package at `Packages/AppCore/`
- local SQLite persistence for sessions, utterances, topics, jobs, and summary
  state
- end-to-end capture -> transcription -> topic summary -> session wrap-up
- baseline unit and integration tests for workspace bootstrap, persistence, and
  job flows

The next phase is a structural redesign.

The product is now being reframed as a shared room device:

- organization-owned
- workspace-scoped
- device-centered
- short-lived operator access
- privacy-safe between meetings

This means the current `Session`-centric model is no longer sufficient by
itself. The upcoming redesign introduces:

- `Organization`
- `Workspace`
- `Device`
- `Account`
- `OrganizationMembership`
- `AccessSession`
- `CaptureSession`

Implemented in the redesign so far:

- SQLite root tables for `Organization`, `Workspace`, `Device`, `Account`,
  `OrganizationMembership`, and `AccessSession`
- default local shared-device bootstrap for development
- diagnostics exposure for current organization / workspace / device scope
- persistent `AccessSession` service with local mock login and logout
- locked room-device start screen when no active access session exists
- `Settings` view in the left sidebar for shared-device metadata inspection

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

The redesign now intentionally revisits earlier assumptions. In particular:

- the old `Session` concept is being split
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
- local wrap-up quality is strong enough for meeting-note review
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

Implemented so far:

- app launch from `XTrustMacApp.xcodeproj`
- local workspace bootstrap under `~/Library/Application Support/XTrust/com.xtrust.mac-local-first/`
- local SQLite session store
- `New Session` creation and relaunch persistence
- microphone recording to local `wav`
- local playback of recorded audio
- first successful local transcription confirmed end-to-end from the app UI
- explicit startup and runtime error surfacing without fallback workspace
- initial `recording artifact`, `transcription job`, and `transcript artifact`
  domain contracts in `AppCore`
- persisted `TranscriptionJob` runner backed by isolated
  `jobs/transcription/<job_id>/` workspaces
- Whisper execution moved behind `AppCore` ports instead of the direct UI path
- durable capture of stdout, stderr, exit code, output files, and validation
  before transcript promotion into final `transcripts/`
- retryable transcription attempts that create new jobs instead of overwriting
  prior evidence
- `Session Detail` UI that shows latest job state, diagnostics paths, and per-
  utterance job attempt history
- live UI refresh for `queued`, `running`, `completed`, and `failed`
  transcription job state
- VAD-based continuous capture via `CaptureRuntime` / `AVAudioCaptureController`
  (RMS threshold 0.01, 3-second silence boundary)
- `utteranceFinalized` events persisted as `Utterance` + `RecordingArtifact` in
  SQLite
- `TopicAssignmentService` groups utterances into topics on a 60-second silence
  gap rule
- `Summarizer` port and `TopicSummaryRunner` for per-topic local LLM
  summarization
- `MLXSummarizer` adapter — calls `python3 -m mlx_vlm generate` as a subprocess
  with a local model directory under `models/gemma4-mlx/`
- `Gemma 4 E4B` running locally via MLX / `mlx_vlm`
  (`mlx-community/gemma-4-e4b-it-4bit`, ~4.86 GB, 4bit); end-to-end Japanese
  meeting summary confirmed
- `Session.Status.closed` + `SessionService.closeSession()`
- per-topic `Summarize` button, summary status badge, and summary text display
- `Close Session` button and `Copy Wrap-Up` (Markdown to clipboard)
- Diagnostics screen shows Whisper and Gemma 4 model paths and ready status
- old one-shot recording path removed from `AppState`; VAD capture is the
  primary recording flow
- UI design system (`XT` token namespace, custom components, Ambient Memo concept)
  — see `docs/design-system.md`
- root entity persistence for `Organization`, `Workspace`, `Device`, `Account`,
  and `OrganizationMembership`
- default local shared-device bootstrap via `SharedDeviceBootstrapService`
- `AccessSession` domain, SQLite persistence, and `AccessSessionService`
- locked shared-device screen before local access begins
- logout path that resets the shared UI and clears visible session history from
  the current operator flow
- `Settings` screen available from the left sidebar footer
- diagnostics now show current organization / workspace / device and access
  status
- Whisper invocation hardened against common no-speech / trailing-silence
  hallucination at utterance boundaries
- trailing silence is no longer written into finalized utterance wav files
- empty or no-output transcription results are treated as discarded noise, not
  as operator-facing failures
- topic and meeting summarization now run through one serialized queue instead
  of launching concurrent MLX jobs
- MLX summarization now rejects oversized prompts and low-memory starts before
  launching the subprocess
- stale `summary_status = running` rows are recovered automatically on app
  startup
- `Settings` now includes a self-service `Reset Stuck Summaries` maintenance
  action
- left sidebar restructured into a collapsible **会議** section (session list)
  and a **チャット** top-level item
- `MLXChatRunner` adapter — freeform local chat backed by the same Gemma 4 E4B
  model via `mlx_vlm generate`; conversation history is accumulated in-memory
  and sent as context on each turn
- `ChatView` — conversational chat UI with per-role message bubbles, animated
  typing indicator, and auto-scroll to latest message

Current verification of the completed PoC slice:

- `swift build`
- `swift test` — 41 tests pass
- `xcodebuild -project XTrustMacApp.xcodeproj -scheme XTrustMacApp build`
- manual flow: locked screen -> begin local access -> inspect `Settings` ->
  create session -> start VAD capture -> speak -> silence 3s -> utterance
  created -> transcribe locally (Moonshine) -> summarize topic locally (Gemma 4
  E4B via MLX) -> close session -> copy wrap-up -> logout -> return to locked
  screen
- chat flow: begin local access -> select **チャット** in sidebar -> type a
  message -> receive reply from Gemma 4 E4B running locally
- recovery flow: force-stop during summary -> relaunch -> confirm stale running
  summaries are auto-recovered or can be reset from `Settings`

Open in Xcode:

1. Open `XTrustMacApp.xcodeproj` in Xcode.
2. Select the `XTrustMacApp` scheme.
3. Run the app on `My Mac`.

Note:

- use `XTrustMacApp.xcodeproj` for running the app
- keep `Package.swift` for command-line build and test workflows only
- for stable microphone permission retention, prefer `Signing Certificate:
  Development`; `Sign to Run Locally` may cause repeated permission prompts on
  this app

## Prerequisites

The app does not download models at runtime. Place both model files before
first use. Exact paths are shown in the app under `Diagnostics`.

### Whisper (ASR)

Install the `whisper` Python package and ensure `ffmpeg` is available in
`PATH`. Place the model file at:

- `~/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/whisper/small.pt`

Diagnostics keys: `Whisper Model` / `Whisper Model Ready`

### Gemma 4 E4B (local LLM summarization)

Install Apple Silicon native `python3`, `mlx-vlm`, and download the model:

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
- summarization is invoked as `python3 -m mlx_vlm generate ...` from
  `MLXSummarizer`

Diagnostics keys: `Gemma 4 Model` / `Gemma 4 Model Ready`

If either model file is missing, the corresponding feature will fail with a
direct local-path error instead of attempting a network download.

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

The chat feature provides a general-purpose local LLM interface alongside the
meeting workflow.

Concrete next candidates:

- image upload in the chat panel — drag-and-drop or file picker, passed as
  base64 to `mlx_vlm generate` for vision input (whiteboard capture use case)
- `Session` → `CaptureSession` rename (Milestone 11)
- idle-timeout handling for the shared-device access session (Milestone 10
  remainder)

Current project state should be read as:

- Milestones 0-10: complete or partially complete
- Milestone 11: open (`Session` → `CaptureSession` rename)
- Chat feature: implemented as a standalone panel outside the milestone sequence

Use these documents as the source of truth:

- `docs/milestones.md`
- `docs/architecture.md`
- `docs/manual-verification.md`
- `docs/summarization-prompt-design.md`
- `docs/asr-comparison-summary.md` — ASR 比較サマリー（Whisper / SenseVoice / Moonshine の現状、調査依頼用）
- `docs/asr-hallucination-investigation.md` — ASR ハルシネーション詳細調査（根本原因と代替候補）
