# Design Reset Notes

Date: 2026-05-08 JST

## Why this reset is needed

Recent work exposed a real design gap.

The project had a useful manual path for proving that the app could record a
wav file and launch Whisper. That path was then used as the basis for continued
development even though it did not define the durable contracts needed by the
product.

The immediate symptom was a transcript file lookup failure. The deeper problem
was that the system could not answer these questions from persisted state:

- which artifact was finalized
- which transcription job ran
- what command and arguments were used
- where the sidecar was allowed to write
- what files the sidecar produced
- whether the output was validated
- which state transition failed

Without those answers, debugging naturally became reactive.

## Root cause

The root cause is not Whisper unpredictability.

The root cause is that the implementation started from a UI smoke path:

```text
Session has one audio path
Session has one transcript path
Button starts recording
Button stops recording
Button runs transcription
Shared directory is inspected for output
```

That path has no durable job boundary and no isolated workspace per ASR run.

## Design correction

The project should move to this model:

```text
Session owns Topics
Topic owns or references Utterances
Utterance owns RecordingArtifact
Utterance has TranscriptionJobs
TranscriptionJob produces TranscriptArtifact
```

Each long-running operation becomes a persisted job with:

- input artifact ids
- command configuration
- status
- started and ended timestamps
- stdout path
- stderr path
- exit code
- generated file listing
- validation result

## Development rule going forward

Do not add product behavior directly behind UI buttons until the underlying
state transition can be tested without the UI.

Do not hide failures behind fallback behavior.

If workspace bootstrap, model discovery, sidecar launch, artifact validation,
or persistence fails, the app should show the actual failure clearly and stop at
that contract boundary.

The correct order is:

1. domain model
2. persistence contract
3. artifact filesystem contract
4. fake adapter tests
5. real sidecar adapter
6. UI wiring

## Immediate implication

The current direct session-level `Transcribe Recording` path should be treated
as temporary scaffolding.

Before building VAD or topic summarization, the app needs a proper utterance
and transcription job pipeline.
