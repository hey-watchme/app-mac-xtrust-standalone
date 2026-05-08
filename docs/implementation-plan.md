# Ambient Memo Implementation Plan

Date: 2026-05-08 JST

## Objective

Rebuild the implementation sequence around explicit contracts instead of UI
button flows.

The desired product shape remains:

```text
session -> topic -> utterance
```

The next engineering target is narrower:

```text
recorded utterance audio -> transcription job -> validated transcript artifact
```

## Why the previous path drifted

The project started with a useful manual scaffold, but the scaffold was treated
as if it were the product architecture.

That created several failure modes:

- `Session` carried recording and transcription fields that belong on
  `Utterance`.
- `Transcribe Recording` launched a sidecar directly from UI state instead of
  from a persisted job.
- Whisper wrote into the shared `transcripts/` directory instead of an isolated
  job workspace.
- The app checked for one expected file path without retaining a structured
  record of the process run.
- There was no durable state for `queued`, `running`, `succeeded`, `failed`, or
  `retrying`.

The result was predictable: when a file was missing, the app could say what it
expected but not prove which contract had failed.

## Working principles

- design data ownership before wiring UI buttons
- persist state transitions before running long jobs
- isolate each sidecar run in its own working directory
- validate artifacts before referencing them from domain models
- make failure evidence durable
- add UI only after the underlying state can be tested without the UI

## Phase 0: Design reset

Goal:

- make the pipeline explainable before changing behavior

Deliverables:

- architecture document defining domain, artifact, and job ownership
- implementation plan based on job boundaries
- testing strategy based on deterministic fixtures

Exit criteria:

- the next code change can be described as a contract implementation, not as a
  button behavior tweak

## Phase 1: Domain and persistence contract

Goal:

- move toward `Session -> Topic -> Utterance` without mixing concerns

Deliverables:

- `Session` as a capture container
- `Topic` as a grouping container
- `Utterance` as the owner of audio and transcription state
- SQLite tables for sessions, topics, utterances, transcription jobs, and
  artifact metadata

Exit criteria:

- one session can own many utterances
- one utterance can have recording metadata and transcription state
- transcription attempts can be stored separately from transcript results

## Phase 2: Artifact filesystem contract

Goal:

- make file ownership deterministic

Deliverables:

- final artifact directories:
  - `audio/`
  - `transcripts/`
  - `jobs/transcription/`
- atomic file promotion from job workspace to final storage
- validation helpers for audio and transcript artifacts

Exit criteria:

- final directories contain only validated artifacts
- job directories contain process outputs and diagnostics
- stale final artifacts cannot affect the result of a new job

## Phase 3: Transcription job runner

Goal:

- make ASR execution predictable and testable

Deliverables:

- `TranscriptionJob` model
- `TranscriptionJobStore`
- `Transcriber` port
- `ProcessRunner` port
- Whisper adapter that uses a dedicated job directory
- fake transcriber for tests

Execution contract:

```text
record job as queued
  -> mark running
  -> create isolated job directory
  -> run Whisper
  -> capture stdout/stderr/exit code/duration
  -> inspect only the job directory
  -> validate transcript output
  -> promote transcript artifact
  -> mark utterance transcribed
```

Exit criteria:

- a fixture wav can be transcribed through the job runner without the app UI
- failure records include command, args, stdout, stderr, exit code, and file
  listing

## Phase 4: UI on top of jobs

Goal:

- let the operator see the durable state instead of transient button effects

Deliverables:

- session detail shows utterances
- utterance card shows recording artifact state
- utterance card shows transcription job state
- retry action creates a new job attempt

Exit criteria:

- UI can be closed and reopened while preserving job state
- a failed ASR job remains diagnosable after restart

## Phase 5: Capture runtime split

Goal:

- separate continuous listening from utterance recording

Deliverables:

- microphone monitor
- VAD boundary detector
- utterance recorder
- recording artifact finalizer

Exit criteria:

- app can listen without writing one unbounded raw recording
- detected speech creates finalized utterance audio artifacts

## Phase 6: Topic formation

Goal:

- group utterances after the utterance pipeline is reliable

Deliverables:

- topic assignment service
- first silence-gap rule
- topic persistence
- grouped session view

Initial rule:

- if the gap between utterances is 1 minute or more, start a new topic

Exit criteria:

- a session can show utterances grouped into topics

## Phase 7: Topic summary and session close

Goal:

- make a closed session useful as a meeting artifact

Deliverables:

- topic summary jobs
- explicit session close action
- session-level export or wrap-up

Exit criteria:

- closing a session leaves behind a readable structured record

## Immediate next code task

The main line is now the persisted `TranscriptionJob` runner and the first
operator-visible job UI.

Complete the remaining Phase 4 work before starting capture runtime split:

1. show transcript artifact history per transcription attempt, not only the
   latest artifact
2. reduce remaining session-level transcription fields so the UI depends more
   directly on utterance-owned durable state
3. harden the manual verification checklist for restart persistence, retry
   history, and diagnostics retention
4. once those are stable, start Phase 5 by splitting microphone monitoring,
   VAD boundary detection, and utterance recording into separate runtime
   responsibilities
