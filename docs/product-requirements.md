# Ambient Memo v1 Requirements

Date: 2026-05-08 JST

## Purpose

Build a local-first, standalone ambient memo system that runs on a capable
laptop and captures spoken knowledge without requiring a cloud backend.

This work is a feasibility and foundation phase for the standalone line. The
goal is not feature breadth. The goal is to prove that the local pipeline can
monitor speech, structure captured content, and preserve it as knowledge.

## Product definition

The product is a local-first ambient memo application centered on one active
session at a time.

For v1, a session means one operator-opened capture window, typically one
meeting.

It should:

- let the operator open one local session
- monitor microphone input continuously while that session is open
- use VAD to decide when speech is present
- record only the detected speech spans
- persist each detected speech span as one utterance under the open session
- group utterances into topics over time
- transcribe detected speech locally
- remain usable even with no network connection

Assumption:

- `VOD` in prior discussion is treated as `VAD` (`voice activity detection`)

## Core data model

The system has three main aggregation levels.

### 1. Session

Definition:

- one operator-opened capture window
- typically one meeting or one bounded recording activity
- owns the topics and utterances created while it remains open
- becomes read-mostly once the operator closes it

Fields:

- `session_id`
- `started_at`
- `ended_at`
- `status`
- `title` later if needed
- `utterance_count`
- `topic_count`

### 2. Topic

Definition:

- a cluster of utterances within one session
- a topic continues while the gap between utterances does not exceed the topic
  boundary threshold
- the initial working rule is a new topic after 1 minute of silence
- the exact threshold remains tunable

Fields:

- `topic_id`
- `session_id`
- `started_at`
- `ended_at`
- `status`
- `utterance_ids`
- `topic_transcript`
- `topic_summary`
- `topic_keywords`
- optional embedding / knowledge link fields later

### 3. Utterance

Definition:

- one contiguous span of speech
- speech belongs to the same utterance while silence does not exceed 3 seconds

Fields:

- `utterance_id`
- `session_id`
- `topic_id` nullable until grouped
- `started_at`
- `ended_at`
- `duration_seconds`
- `audio_file_path`
- `transcript_text`
- `transcription_status`
- optional quality / confidence fields later

## Functional requirements

### Session lifecycle

- the operator can create one new local session
- the operator can explicitly start listening inside that session
- the operator can explicitly stop listening without deleting prior utterances
- the operator can explicitly close the session to finalize the captured set
- only one active listening session is required for v1

### Continuous listening

- the app can stay active for long periods while one session is open
- the microphone input is monitored continuously
- raw audio is not saved continuously
- recording begins only when VAD detects speech
- silence or non-speech is ignored instead of being saved as one continuous raw
  file

### Utterance segmentation

- speech separated by less than 3 seconds of silence remains one utterance
- speech separated by 3 seconds or more becomes a new utterance
- each utterance produces one saved audio artifact and one transcript artifact

### Topic segmentation

- topic grouping happens within one session
- utterances separated by less than 1 minute remain in the same topic
- utterances separated by 1 minute or more start a new topic
- topics are updated incrementally as new utterances arrive
- the 1-minute threshold is the first working rule, not a permanently frozen
  product constant

### Local ASR

- ASR must run locally
- the first validation target is correctness and repeatability, not final model
  optimization
- ASR failure must not crash the capture loop
- failed utterances remain visible and retryable

### Local summarization

- topic-level summarization runs locally
- summarization is not required to block utterance capture
- summary generation may be deferred or retried

### Knowledge accumulation

- sessions, utterances, and topics persist locally
- the local store should support later promotion into a knowledge layer
- v1 only needs the persistence model and retrieval hooks, not a full knowledge
  UI

## Non-functional requirements

### Local-first

- no cloud dependency for the standalone line
- app remains functional offline
- models are local files, not runtime downloads

### Robustness

- failures in ASR or summary jobs are isolated and recoverable
- long-running capture should not require manual file repair
- app restart should preserve state

### Observability

- operator can inspect current capture state
- operator can inspect session, topic, and utterance states
- operator can inspect errors, model paths, and job status

### Simplicity

- v1 should prefer a narrow vertical slice over broad features
- avoid premature multimodal expansion
- avoid premature knowledge UI expansion

## Explicit non-goals for v1

- cloud sync
- collaboration
- system-audio capture
- video understanding
- speaker diarization
- live chat over all captured knowledge
- large-scale retrieval UX

## Recommended v1 vertical slice

The first meaningful standalone proof should be:

1. always-on microphone monitoring inside one open session
2. operator-opened session lifecycle
3. VAD-based utterance detection
4. utterance audio save
5. local utterance ASR
6. topic grouping by silence-gap rule
7. local persistence and inspection UI

That is the real v1. Everything else is secondary.
