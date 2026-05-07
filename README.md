# Mac Local-First Meeting Notes PoC

Date: 2026-05-07 JST

This directory is reserved for a new standalone macOS PoC that runs on a
MacBook M1 Pro class machine and is independent from WatchMe / ZeroTouch cloud
infrastructure.

## Current status

This project is in planning bootstrap.

Technical stack and implementation planning are tracked in:

- `docs/tech-stack-plan.md`

## Why this project exists

The Android standalone local-LLM PoC was useful as an edge-device validation,
but it hit practical limits on a 4 GB RAM class tablet:

- local LLM runtime capacity was not sufficient for stable day-to-day use
- swap pressure and system slowdown were too severe
- the device was good enough for API-connected workflows, but not for the
  local-only meeting-notes target

The local-first product line now shifts to a laptop-first target, starting with
this MacBook M1 Pro. The tablet line continues separately as an API-connected
product.

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

Do not extend `app/android-standalone/` for this line.

Reason:

- the target OS, runtime, permissions, packaging, and UI conventions are
  different
- mixing Android and macOS assumptions in one app tree would make planning and
  maintenance harder
- the Android local-only findings should remain preserved as a closed
  validation branch

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
- the tablet line continues separately as the API-connected product path
- Android local-only findings remain preserved in `app/android-standalone/`

## Suggested structure

```text
mac-local-first/
├── README.md
└── docs/
    └── tech-stack-plan.md
```

## Recommended next step

1. Fix the v1 tech stack and process model.
2. Decide the local model formats and storage paths.
3. Create the macOS app shell.
4. Prove `record -> transcribe -> summarize -> save`.
