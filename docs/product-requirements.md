# Ambient Memo v1 Requirements

Date: 2026-05-08 JST

## Purpose

Build a local-first, standalone ambient memo system that runs on a capable
laptop and accumulates spoken knowledge without requiring a cloud backend.

This work is a feasibility and foundation phase for the standalone line. The
goal is not feature breadth. The goal is to prove that the local pipeline can
run continuously, detect speech, structure captured content, and preserve it as
knowledge.

## Product definition

The product is an always-on ambient memo application.

It should:

- stay running in the background on a local machine
- listen continuously
- use VAD to decide when speech is present
- record only when speech is detected
- transcribe detected speech locally
- accumulate transcribed speech into progressively larger knowledge units
- remain usable even with no network connection

Assumption:

- `VOD` in prior discussion is treated as `VAD` (`voice activity detection`)

## Core data model

The system has three main aggregation levels.

### 1. Utterance

Definition:

- one contiguous span of speech
- speech belongs to the same utterance while silence does not exceed 3 seconds

Fields:

- `utterance_id`
- `started_at`
- `ended_at`
- `duration_seconds`
- `audio_file_path`
- `transcript_text`
- `transcription_status`
- optional quality / confidence fields later

### 2. Topic

Definition:

- a cluster of utterances
- a topic continues while the gap between utterances does not exceed 1 minute
- if the silent gap exceeds 1 minute, a new topic starts

Fields:

- `topic_id`
- `started_at`
- `ended_at`
- `utterance_ids`
- `topic_transcript`
- `topic_summary`
- `topic_keywords`
- optional embedding / knowledge link fields later

### 3. Memo / Minutes

Definition:

- a larger operator-facing memo unit composed of multiple topics
- the exact session boundary is a product decision and should not be hard-coded
  too early
- for v1, this can be a daily memo or an explicitly opened capture window

Fields:

- `memo_id`
- `started_at`
- `ended_at`
- `topic_ids`
- `memo_summary`
- `export_status`

## Functional requirements

### Always-on capture

- the app can stay active for long periods
- the microphone input is monitored continuously
- raw audio is not saved continuously
- recording begins only when VAD detects speech

### Utterance segmentation

- speech separated by less than 3 seconds of silence remains one utterance
- speech separated by 3 seconds or more becomes a new utterance
- each utterance produces one saved audio artifact and one transcript artifact

### Topic segmentation

- utterances separated by less than 1 minute remain in the same topic
- utterances separated by 1 minute or more start a new topic
- topics are updated incrementally as new utterances arrive

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

- utterances, topics, and memo summaries persist locally
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
- operator can inspect utterance, topic, and memo states
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

1. always-on microphone monitoring
2. VAD-based utterance detection
3. utterance audio save
4. local utterance ASR
5. topic grouping by silence-gap rule
6. local topic summary
7. local persistence and inspection UI

That is the real v1. Everything else is secondary.
