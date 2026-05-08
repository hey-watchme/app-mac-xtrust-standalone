# Mac Local-First Meeting Notes PoC

Date: 2026-05-07 JST

This directory is reserved for a new standalone macOS PoC that runs on a
MacBook M1 Pro class machine and is independent from WatchMe / ZeroTouch cloud
infrastructure.

## Current status

This project now has a Milestone 1 scaffold:

- a real macOS Xcode project at `XTrustMacApp.xcodeproj`
- a minimal macOS `SwiftUI` app target at `XTrustMacApp/`
- a testable core library as a local package at `Packages/AppCore/`
- baseline unit and integration tests for workspace bootstrap and session
  persistence

Technical stack and implementation planning are tracked in:

- `docs/architecture.md`
- `docs/tech-stack-plan.md`
- `docs/milestones.md`
- `docs/testing-strategy.md`

## Why this project exists

This project establishes a laptop-first local-first product line, starting with
this MacBook M1 Pro.

## Goal

Build a simple and robust local-first meeting notes app for macOS that can:

```text
Capture meeting audio
  -> transcribe locally
  -> summarize locally
  -> save locally
  -> export locally
```

The first version should prioritize operational reliability over feature count.

## Product boundary

The macOS app should prove a stricter local-first posture than the cloud app.

Initial target:

- no required cloud API dependency
- no required account or login
- no required backend service
- local storage for audio, transcript, and summaries
- local ASR
- local LLM summarization
- explicit local model paths under app-managed directories

Allowed later, but not required for v1:

- optional export
- optional manual model import
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

## First PoC scope

Build only one vertical path first:

```text
Microphone input
  -> local wav recording
  -> local ASR
  -> transcript review
  -> local wrap-up summary
  -> local session save
```

Do not start with:

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
- first UI target: single local operator, single machine
- first runtime mode: offline-capable and local-first

## Success criteria

- Japanese meeting audio can be transcribed at practical speed on the target Mac
- local wrap-up quality is strong enough for meeting-note review
- the app remains stable during normal meeting-length operation
- audio, transcript, and summary artifacts remain inspectable on local storage

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
    ├── architecture.md
    ├── tech-stack-plan.md
    ├── milestones.md
    └── testing-strategy.md
```

## Current status

Implemented so far:

- app launch from `XTrustMacApp.xcodeproj`
- local workspace bootstrap under `~/Library/Application Support/XTrust/com.xtrust.mac-local-first/`
- local SQLite session store
- `New Session` creation and relaunch persistence
- microphone recording to local `wav`
- local playback of recorded audio
- manual file-based ASR trigger through the Python `whisper` CLI
- first successful local transcription confirmed end-to-end from the app UI
- explicit startup and runtime error surfacing without fallback workspace
- initial `recording artifact`, `transcription job`, and `transcript artifact`
  domain contracts in `AppCore`

Current verification:

- `swift build`
- `swift test`
- `xcodebuild -project XTrustMacApp.xcodeproj -scheme XTrustMacApp build`
- manual flow: create session -> record -> play back -> transcribe -> confirm
  transcript file under `transcripts/`

Open in Xcode:

1. Open `XTrustMacApp.xcodeproj` in Xcode.
2. Select the `XTrustMacApp` scheme.
3. Run the app on `My Mac`.

Note:

- use `XTrustMacApp.xcodeproj` for running the app
- keep `Package.swift` for command-line build and test workflows only

## ASR prerequisite

The current Milestone 3 path uses the locally installed Python `whisper` CLI.

The app does not download Whisper models at runtime. This is intentional, so
ASR does not depend on live network access or local SSL trust settings.

Place the model file here before pressing `Transcribe Recording`:

- `~/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/whisper/small.pt`

You can confirm the exact path in the app under `Diagnostics`:

- `Whisper Model`
- `Whisper Model Ready`

If the file is missing, ASR will fail with a direct local-path error instead of
trying to download the model.

## Recommended next step

The next implementation step is no longer another direct patch on
`Transcribe Recording`.

Build the first real transcription job runner:

- create one persisted `TranscriptionJob` per utterance transcription attempt
- use `jobs/transcription/<job_id>/` as the isolated sidecar working directory
- capture stdout, stderr, exit code, and generated files per job
- validate the transcript artifact before promoting it into final `transcripts/`
- have the UI read job state instead of directly owning the Whisper process

Before the next coding session, use these documents as the source of truth:

- `docs/product-requirements.md`
- `docs/milestones.md`
- `docs/design-reset.md`
- `docs/implementation-plan.md`
- `docs/architecture.md`
- `docs/next-session-handoff.md`
