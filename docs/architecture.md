# Mac Local-First Architecture

Date: 2026-05-08 JST

## Objective

Define the architecture before adding more behavior.

The app must make the local pipeline predictable. Recording, ASR, topic
formation, and summarization should each have clear ownership, explicit input
and output contracts, and persisted state transitions.

Error handling policy:

- do not hide startup or runtime failures behind fallback workspaces
- do not substitute unavailable services with silent placeholders
- surface the real error to the operator together with the failed contract
- use diagnostics to explain the failure, not to continue past it invisibly

The immediate design target is not VAD quality or summary quality. The target
is a reliable artifact pipeline:

```text
session
  -> utterance recording artifact
  -> transcription job
  -> transcript artifact
  -> topic assignment
  -> topic summary job
```

## Current design problem

The current scaffold grew from a manual demo path:

```text
press Start Recording
  -> write one wav file on the session
press Stop Recording
  -> mark the session completed
press Transcribe Recording
  -> run Whisper directly from the UI state path
  -> look for a txt file in the shared transcripts directory
```

That shape is useful for a smoke test, but it is not a production design.

The weak points are:

- `Session` is doing too much: it is both the meeting container and the single
  recording/transcription target.
- UI actions directly trigger long-running side effects without a durable job
  boundary.
- ASR output is written into a shared final directory, so old output can confuse
  diagnosis.
- The app assumes a transcript path before the ASR job has produced and
  validated the artifact.
- stdout, stderr, exit code, duration, input path, and output files are not
  persisted as first-class job evidence.

This is why recent debugging became narrow and reactive. The code did not give
us a stable state machine to inspect. It only gave us a button path and an error
string after the fact.

## Domain model

### Session

Top-level capture container.

Responsibilities:

- owns topics and utterances
- represents one operator-opened meeting or capture window
- tracks lifecycle: `draft`, `listening`, `paused`, `closed`, `failed`

Keep out:

- individual audio file paths
- individual transcript text
- raw ASR process details

### Topic

Cluster of utterances inside one session.

Responsibilities:

- owns a contiguous or semantically grouped subset of utterances
- tracks summary status
- stores topic-level summary artifacts

Keep out:

- microphone capture state
- per-utterance transcription process details

### Utterance

Smallest persisted speech unit.

Responsibilities:

- points to one finalized audio artifact
- owns transcription lifecycle
- can later be assigned to a topic

Lifecycle:

```text
detected
  -> recording
  -> recorded
  -> transcriptionQueued
  -> transcribing
  -> transcribed
  -> failed
```

Rules:

- an utterance cannot be transcribed until its audio artifact is finalized
- an utterance transcription failure must not corrupt the session
- retrying ASR creates a new job attempt, not an overwrite of history

## Artifact model

Artifacts are files that have passed validation and can be referenced from
SQLite.

### Recording artifact

Created only after recording has stopped and the file has been verified.

Required metadata:

- `artifact_id`
- `utterance_id`
- final `audio_file_path`
- byte size
- duration
- sample rate
- channel count
- created timestamp

Validation:

- file exists
- file size is greater than zero
- duration is greater than the minimum useful utterance duration
- file path is inside the app-managed workspace

### Transcript artifact

Created only after a transcription job has produced and validated text.

Required metadata:

- `artifact_id`
- `utterance_id`
- final `transcript_file_path`
- text
- model identifier
- language
- created timestamp

Validation:

- transcript file exists
- transcript text can be read as UTF-8
- transcript output belongs to the current job workspace

## Job model

Any long-running or fallible operation must be represented as a job.

### Transcription job

Input:

- one finalized recording artifact
- one model configuration
- one dedicated job working directory

Output:

- one transcript artifact on success
- one failed job record on failure

Execution contract:

```text
create job directory
  -> run ASR sidecar with job directory as output_dir
  -> wait for process completion
  -> capture stdout, stderr, exit code, and duration
  -> inspect only the job directory
  -> require exactly one txt output for the input audio
  -> move validated transcript to final transcript storage
  -> update utterance transcription state
```

Rules:

- sidecars must not write directly to final artifact directories
- shared final directories are storage locations, not job workspaces
- stdout and stderr are diagnostic artifacts and should be retained for failed
  jobs
- process success is not enough; output validation is mandatory
- if validation or process setup fails, show that failure directly instead of
  falling back to a weaker path

## Layering

```text
XTrustMacApp
  -> AppRuntime
    -> AppCore
      -> Ports
        -> Infrastructure adapters
          -> SQLite / filesystem / sidecar processes
```

### `XTrustMacApp`

Responsibilities:

- app entry point
- window and navigation structure
- macOS permission handling
- operator-facing screens and status
- dispatch user intents to application services

Keep out:

- SQL
- raw process execution
- path naming rules
- ASR output validation
- domain state transitions

### `AppRuntime`

Responsibilities:

- bootstrap `WorkspacePaths`
- initialize infrastructure adapters
- wire stores, artifact services, and job runners into AppCore services

Keep out:

- SwiftUI view logic
- business state transitions
- ASR prompt or output rules

### `AppCore`

Responsibilities:

- `Session`, `Topic`, `Utterance`
- artifact metadata models
- job models and state transitions
- application services for session lifecycle, recording completion,
  transcription scheduling, and topic assignment
- ports for storage, filesystem artifacts, sidecars, and clock

Keep out:

- `SwiftUI`
- `AppKit`
- hard-coded user-specific paths
- direct `Process` usage

### Infrastructure adapters

Responsibilities:

- SQLite-backed stores
- app workspace path resolution
- atomic file movement
- sidecar process execution
- artifact validation

Adapters must implement AppCore ports and remain replaceable.

## Required ports

The next implementation should introduce these boundaries before adding more
product behavior:

- `SessionStore`
- `TopicStore`
- `UtteranceStore`
- `RecordingArtifactStore`
- `TranscriptionJobStore`
- `ArtifactFileStore`
- `Transcriber`
- `ProcessRunner`
- `Clock`

## Sidecar rules

Sidecars are external programs such as Whisper and later llama.cpp.

Rules:

- do not execute sidecars from UI code
- do not let sidecars write directly into final artifact directories
- do not infer success from exit code alone
- capture command, arguments, stdout, stderr, exit code, duration, input files,
  and generated output files
- make every failed sidecar run inspectable after app restart

## First design milestone

Before more VAD or topic work, implement the predictable ASR job boundary:

```text
existing wav fixture
  -> TranscriptionJob
  -> isolated job directory
  -> validated transcript artifact
  -> persisted utterance transcription state
```

Exit criteria:

- the same fixture wav produces the same transcript artifact path every time
- stale files in `transcripts/` cannot affect job success or failure
- failures preserve enough evidence to explain what happened without rerunning
  the app
