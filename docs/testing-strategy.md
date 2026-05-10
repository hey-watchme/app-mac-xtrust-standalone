# Mac Local-First Testing Strategy

Date: 2026-05-10 JST

## Objective

Test contracts before testing UI flows.

The product depends on local files, sidecar processes, and long-running jobs.
Those are predictable only if the pipeline is tested in layers with fixture
inputs and inspectable outputs.

## Testing principles

- unit-test state transitions without audio devices or model binaries
- integration-test filesystem and SQLite contracts with temporary directories
- run sidecar tests through dedicated job directories
- treat process exit code and output validation as separate checks
- keep UI smoke checks last

## Contract layers

### Layer 1: Domain state tests

Use for:

- session lifecycle
- utterance lifecycle
- transcription job lifecycle
- retry behavior
- failure isolation

Required examples:

- utterance cannot enter `transcribing` without a finalized audio artifact
- failed transcription does not change session status
- retry creates a new job attempt
- access session begins as `active` and ends as `logged_out` or `timed_out`

### Layer 2: Filesystem artifact tests

Use for:

- workspace directory layout
- job directory creation
- atomic promotion from job output to final artifact storage
- stale-file isolation

Required examples:

- stale files in `transcripts/` do not affect a new transcription job
- each job writes under `jobs/transcription/<job_id>/`
- final transcript is promoted only after validation

### Layer 3: SQLite integration tests

Use for:

- organizations, workspaces, devices, accounts, memberships
- access sessions
- sessions, topics, utterances
- recording artifacts
- transcription jobs
- transcript artifacts
- restart recovery

Required examples:

- one organization owns many workspaces
- one workspace owns many devices
- one device can have many access sessions
- one session owns many utterances
- one utterance can have multiple transcription attempts
- failed job evidence survives store reload
- stale `running` summary state is recovered on restart without DB intervention

### Layer 4: Fake sidecar tests

Use for:

- process runner behavior
- stdout/stderr capture
- generated file inspection
- success and failure mapping

Required examples:

- fake transcriber produces exactly one txt file and succeeds
- fake transcriber exits 0 but produces no txt file and fails validation
- fake transcriber exits nonzero and preserves stderr

### Layer 4.5: Summary runtime safety tests

Use for:

- serialized local summarization
- stale running-state recovery
- admission control before MLX launch

Required examples:

- two concurrent summary requests execute with max concurrency `1`
- interrupted `running` topic summaries are downgraded on restart
- prompt-too-large and low-memory starts fail before subprocess launch

### Layer 5: Real fixture sidecar tests

Use for:

- one short fixture wav
- one expected text artifact shape
- local Whisper runtime validation

Rules:

- mark these tests as explicit or developer-run if they require local model
  files
- keep them out of the fast unit-test loop unless the model is guaranteed
  present

### Layer 6: UI smoke checks

Use for:

- app launch
- operator-visible state
- manual microphone permission flow
- final end-to-end sanity checks

Rule:

- UI smoke checks should confirm an already-tested contract, not discover the
  contract for the first time.

## Fixture plan

Keep a minimal fixture set in `Fixtures/`:

- one short clean Japanese wav
- one expected transcript text file
- one fake sidecar script that writes a txt file
- one fake sidecar script that exits 0 without writing output
- one fake sidecar script that exits nonzero with stderr

Do not start with a large corpus.

## Verification by milestone

### Design reset

- docs review
- architecture contract review
- implementation sequence review

### Domain and persistence

- `Session`, `Topic`, `Utterance` unit tests
- `Organization`, `Workspace`, `Device`, `Account`, `OrganizationMembership`,
  and `AccessSession` store tests
- transcription job lifecycle unit tests
- SQLite CRUD tests for all domain and job tables

### Artifact filesystem

- temporary workspace tests
- job workspace tests
- stale final directory tests
- atomic promotion tests

### Transcription job runner

- fake sidecar success test
- fake sidecar no-output test
- fake sidecar nonzero-exit test
- optional real Whisper fixture test

### UI wiring

- launch app
- confirm locked shared-device start screen
- begin local access with the mock access path
- create/select session
- open `Settings`
- confirm organization / workspace / device / access details are visible
- confirm `Reset Stuck Summaries` is visible and disabled while a summary is
  actively queued
- show utterance list
- show transcription job state
- retry failed job from persisted state

## Manual checks

Manual checks should be short and confirm a known contract.

For ASR:

1. select or create one utterance with a finalized wav
2. start transcription
3. confirm a job row appears as `running`
4. confirm the job directory contains stdout/stderr and sidecar outputs
5. confirm the final transcript appears only after validation
6. relaunch and confirm the same state is visible
