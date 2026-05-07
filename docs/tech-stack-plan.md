# Mac Local-First Tech Stack Plan

Date: 2026-05-07 JST

## Objective

Define a simple and robust v1 stack for a local-first meeting notes app running
on Apple Silicon macOS, starting on a MacBook M1 Pro.

## Decision summary

Use a native macOS desktop app with local sidecar runtimes for ASR and LLM.

This means:

- native macOS UI and permissions handling
- inference isolated away from the main UI process where practical
- app-managed local files and SQLite storage
- `whisper.cpp` for offline ASR
- `llama.cpp` for offline meeting-summary generation
- browser delivery postponed until after the desktop flow is stable

## Recommended stack

### App shell

- `SwiftUI` for the main desktop UI
- `AppKit` interop only where macOS-specific controls are needed
- `Swift Concurrency` for background jobs and pipeline orchestration

Why:

- best fit for a Mac-only first release
- straightforward access to macOS permissions and file locations
- lower moving parts than Electron or browser-first architectures

### Audio capture

Primary:

- `AVAudioEngine` for microphone capture and local wav recording

Optional later:

- `ScreenCaptureKit` for system audio and screen capture when meeting sources
  beyond the mic are needed

Why:

- Apple-native APIs are the most direct path for stable capture on macOS
- v1 only needs microphone capture to validate the core notes workflow

### ASR

Primary:

- `whisper.cpp`

Execution mode for v1:

- start with sidecar CLI invocation for file-based transcription

Why:

- strong macOS / Apple Silicon support with Metal and Core ML acceleration
- offline by default
- easy to benchmark and easy to swap model sizes

### LLM summarization

Primary:

- `llama.cpp`

Execution mode for v1:

- start with sidecar CLI invocation for one-shot wrap-up summarization

Possible later upgrade:

- persistent local `llama-server` process if chat or multi-step workflows are
  required

Why:

- broad GGUF model support
- strong Apple Silicon Metal path
- operationally simpler than bringing in a Python runtime for v1

### Persistence

- `SQLite` for sessions, transcripts, and summaries
- app-managed local directories under Application Support for:
  - audio
  - transcripts
  - summaries
  - models

Why:

- durable and inspectable local state
- simple schema evolution path
- enough for a single-user local desktop app

### Packaging and runtime layout

- ship the macOS app separately from the Android apps
- package the UI as a signed macOS `.app`
- plan for `Developer ID` signing and notarization before distribution
- keep models outside the app bundle
- allow the app to point to or manage local model directories
- treat ASR and LLM runtimes as replaceable local components

Why:

- macOS distribution should not be an afterthought
- model files are large and may change more often than the UI shell
- app updates and model updates should remain decoupled

## Proposed v1 process model

```text
SwiftUI app
  -> capture mic audio to wav
  -> enqueue local transcription job
  -> run whisper.cpp sidecar on saved audio
  -> persist transcript to SQLite
  -> enqueue summary job
  -> run llama.cpp sidecar on selected transcript text
  -> persist summary to SQLite
  -> show session timeline and wrap-up result
```

This is intentionally file-based and batch-oriented.

It avoids premature complexity such as:

- realtime token streaming
- always-on local chat state
- direct in-process native inference bindings
- multimodal live pipelines

For v1, prefer helper or sidecar execution for heavy inference work so the UI
remains responsive and failures are easier to isolate.

## What to avoid in v1

- browser-only WebGPU stack
- Electron unless a web team constraint appears
- Python-first local runtime as a hard dependency
- real-time diarization
- cloud fallbacks as part of the main path
- model bundling into the app binary
- cross-platform abstraction before the macOS path is proven

## Why not browser-first

Browser local inference is improving, but it adds avoidable risk for v1:

- runtime behavior depends on browser WebGPU support and flags
- local file and long-running job control are weaker than in a desktop app
- system-level media capture and local runtime orchestration are less direct

For this PoC, the desktop app is the simpler and more defensible choice.

## Why not Electron first

Electron remains a valid fallback, but it is not the first recommendation here.

Tradeoff:

- pros: faster for a web-heavy team, easy Node-side process orchestration
- cons: larger runtime surface, more packaging complexity, weaker fit for a
  Mac-only v1 than native APIs

If the team later decides the app must share UI code with a web client, revisit
this choice then.

## Model strategy

### ASR model direction

Start with one or two `whisper.cpp` model sizes only.

Recommendation:

- first benchmark a small / medium Japanese-capable model
- keep one faster fallback and one higher-quality option
- do not start with a large model matrix

### LLM model direction

Start with one summarization-grade instruct model in `GGUF`.

Recommendation:

- choose one model that comfortably fits M1 Pro memory headroom
- optimize for stable wrap-up quality, not maximum benchmark size
- use one fixed prompt contract for title, bullets, and summary

## Initial local schema

```text
sessions
  id
  started_at
  ended_at
  status
  audio_path
  transcript_path
  summary_path
  created_at

transcripts
  id
  session_id
  source
  text
  language
  model
  duration_ms
  created_at

summaries
  id
  session_id
  title
  bullets
  summary
  model
  prompt_version
  created_at
```

## Phased implementation plan

### Phase 0: Feasibility benchmark

- confirm target Whisper and GGUF models on the MacBook M1 Pro
- record baseline latency, RAM pressure, and output quality

### Phase 1: App shell and local storage

- create the macOS app shell
- set up Application Support directories
- set up SQLite schema and session history

### Phase 2: Local recording and ASR

- capture microphone input
- save wav files locally
- transcribe them with `whisper.cpp`
- display transcript results and metrics

### Phase 3: Local summarization

- define one wrap-up prompt contract
- summarize saved transcript text with `llama.cpp`
- persist and display the result

### Phase 4: Operator workflow hardening

- add retry and failure states
- add export to Markdown or text
- add model-path validation and diagnostics

## Exit criteria for v1

- app runs on macOS without requiring a cloud API
- one meeting recording can be captured, transcribed, summarized, and saved
- local data remains inspectable on disk
- common failure states are visible and recoverable
