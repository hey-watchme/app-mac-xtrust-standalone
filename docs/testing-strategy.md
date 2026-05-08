# Mac Local-First Testing Strategy

Date: 2026-05-07 JST

## Objective

Keep implementation incremental and testable from the first milestone.

## Principles

- test the smallest useful slice first
- prefer deterministic file-based checks over complex live automation early on
- isolate pure logic so it can be unit-tested without audio devices or models
- add fixture-driven integration tests before broad end-to-end coverage

## Test layers

### Layer 1: manual smoke checks

Use for:

- window launch
- permission prompts
- microphone capture
- local file creation
- visible job status transitions

Rule:

- every milestone must end with one short smoke checklist that can be rerun in
  a few minutes

### Layer 2: unit tests

Use for:

- prompt builders
- file-path resolution
- session state reducers
- export formatting
- database mapping helpers

Rule:

- pure logic should not depend on audio devices, model binaries, or UI state

### Layer 3: integration tests

Use for:

- SQLite schema and CRUD flows
- sidecar process wrappers
- transcript import / parse flows
- summary result parsing

Rule:

- integration tests should use canned fixtures and fake sidecar outputs where
  possible

### Layer 4: fixture-based end-to-end checks

Use for:

- `wav -> ASR -> transcript save`
- `transcript -> LLM -> summary save`

Rule:

- keep the fixture set small and stable
- run these checks only after unit and integration layers are green

## Early fixture plan

Keep a minimal fixture set in `Fixtures/`:

- one short clean Japanese sample
- one longer meeting-like Japanese sample
- one expected transcript sample
- one expected summary-format sample

Do not start with a large corpus.

## Repository skeleton

Recommended initial directories:

```text
XTrustMacApp/
  App/
  Features/
  Shared/
  Resources/
Packages/
  AppCore/
    Sources/
    Tests/
Tests/
  AppCoreIntegrationTests/
  XTrustMacUITests/
Fixtures/
  audio/
  transcripts/
  summaries/
ThirdParty/
scripts/
```

Purpose:

- `XTrustMacApp/App/`: app entry, window, and dependency wiring
- `XTrustMacApp/Features/`: recording, transcript, summary, and settings flows
- `XTrustMacApp/Shared/`: reusable UI and small presentation helpers
- `Packages/AppCore/`: pure logic, use cases, ports, and core tests
- `Tests/AppCoreIntegrationTests/`: DB and process-wrapper tests
- `Tests/XTrustMacUITests/`: a very small UI smoke suite
- `Fixtures/`: stable sample data for repeatable checks
- `ThirdParty/`: sidecar placement policy and version notes
- `scripts/`: benchmark and local developer helper scripts

## Verification by milestone

### Milestone 0

- docs review
- folder sanity check

### Milestone 1

- app launch smoke check
- directory bootstrap test
- `AppCore` package unit-test smoke

Recommended manual checklist:

- launch `XTrustMacApp` from Xcode and confirm one window appears
- confirm the diagnostics panel shows paths for workspace and database
- confirm `audio`, `transcripts`, `summaries`, and `models` are marked ready
- press `New Session` and confirm one draft session appears in the list
- quit and relaunch the app and confirm the draft session is still listed

### Milestone 2

- manual mic recording check
- file existence assertion

Recommended manual checklist:

- start from a clean launch and create or select a draft session
- press `Start Recording` and allow microphone access when prompted
- speak for 5-10 seconds and press `Stop Recording`
- confirm the selected session becomes `completed`
- confirm `Audio File` and `Duration` appear in the session detail
- relaunch the app and confirm the completed session and recorded file path persist

### Milestone 3

- fake process-runner ASR wrapper test
- one real fixture-based ASR wrapper test
- one real manual transcription run

Recommended manual checklist:

- select a session that has a saved `wav`
- press `Transcribe Recording`
- wait for the `Transcription` status to move from `running` to `completed`
- confirm transcript text appears in the detail view
- confirm `Transcript File` is created under `transcripts/`

### Milestone 4

- prompt contract unit test
- fixture-based summary parsing test
- fake summarizer integration test
- one real manual summary run

### Milestone 5

- failure recovery regression checklist
- long-session manual smoke run
