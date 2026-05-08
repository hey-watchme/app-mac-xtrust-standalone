# Ambient Memo Milestones

Date: 2026-05-08 JST

## Working rule

Every milestone must end with:

- one operator-visible outcome
- one reproducible manual check
- one explicit definition of what is deferred

Do not move to the next milestone while the current milestone still depends on
manual file surgery or unclear operator behavior.

## Milestone 0: Product and data contract

Goal:

- freeze the product definition before more implementation

Scope:

- confirm the standalone product purpose
- confirm `utterance -> topic -> memo` hierarchy
- define silence thresholds
- define local-only requirement
- define first non-goals

Exit criteria:

- one written requirements document exists
- one written milestone sequence exists
- one written decision list exists for unresolved product choices

Deferred:

- code changes

## Milestone 1: Runtime skeleton

Goal:

- establish a production-shaped runtime skeleton without pretending the product
  is already working

Scope:

- app shell
- runtime bootstrap
- local workspace bootstrap
- local persistence bootstrap
- diagnostics screen
- stable launch / relaunch behavior

Exit criteria:

- app launches reliably
- app relaunches without state loss
- diagnostics can show paths, model readiness, and storage readiness

Deferred:

- always-on capture
- real VAD
- real topic formation

## Milestone 2: Continuous microphone monitoring

Goal:

- prove that the app can remain active and monitor microphone input without
  manual start/stop recording

Scope:

- microphone permission flow
- input pipeline setup
- audio level monitoring
- lifecycle handling for long-running capture
- diagnostics for capture state

Exit criteria:

- app can remain active and monitor input for an extended period
- operator can see whether listening is active
- no continuous raw recording file is required yet

Deferred:

- utterance save
- ASR
- topic grouping

## Milestone 3: VAD-based utterance capture

Goal:

- convert continuous monitoring into utterance artifacts

Scope:

- VAD integration
- 3-second silence rule for utterance boundaries
- one audio artifact per utterance
- utterance persistence
- utterance list / inspection UI

Exit criteria:

- normal speech creates utterance records automatically
- silence >= 3 seconds creates a new utterance boundary
- saved utterances are visible after restart

Deferred:

- ASR
- topic grouping
- summarization

## Milestone 4: Local utterance ASR

Goal:

- transcribe saved utterances locally and reliably

Scope:

- explicit model-path management
- local ASR adapter
- transcript file persistence
- utterance transcription status
- retryable failure handling

Exit criteria:

- one saved utterance can be transcribed locally with no cloud access
- transcript result is attached to the utterance
- failure is visible and retryable from the UI

Deferred:

- topic grouping
- summarization

## Milestone 5: Topic formation

Goal:

- group utterances into topics using the 1-minute silence-gap rule

Scope:

- topic creation logic
- topic extension logic
- topic closure logic
- topic persistence
- topic detail UI

Exit criteria:

- utterances within 1 minute stay in one topic
- utterances separated by >= 1 minute start a new topic
- topic boundaries survive restart

Deferred:

- memo-level summaries
- knowledge projections

## Milestone 6: Local topic summarization

Goal:

- generate a usable local summary per topic

Scope:

- topic prompt contract
- local summarizer adapter
- topic summary persistence
- summary retry behavior

Exit criteria:

- a topic can produce a local summary with no cloud dependency
- failed summary jobs do not corrupt the topic state

Deferred:

- memo-level synthesis
- knowledge indexing

## Milestone 7: Memo aggregation

Goal:

- define and implement the first operator-facing memo unit

Scope:

- choose initial memo boundary strategy
- aggregate topics into one memo
- memo summary or wrap-up generation
- exportable memo representation

Exit criteria:

- operator can inspect one memo composed of topics
- memo can be exported or copied in a stable format

Deferred:

- advanced knowledge UX

## Milestone 8: Knowledge projection

Goal:

- persist the captured structure in a form that can later support knowledge use

Scope:

- stable identifiers
- local search-ready schema
- metadata needed for later embeddings or retrieval
- non-destructive migration strategy

Exit criteria:

- utterances, topics, and memos can be traversed and queried locally
- schema is stable enough for future knowledge features

Deferred:

- full RAG
- chat UX

## Milestone 9: Hardening

Goal:

- make the ambient loop reliable enough for repeated daily use

Scope:

- restart recovery
- job retry policy
- model-path validation
- longer capture tests
- disk-growth controls

Exit criteria:

- the system can run through a normal real-world usage period without manual
  intervention
- common failure modes are recoverable from the product surface

Deferred:

- multimodal expansion
- collaboration

## Open product decisions

These should be answered before Milestone 7:

- what is the first memo boundary: day, manual session, or another rule
- whether topic summaries are generated eagerly or on idle time
- whether failed utterance ASR blocks topic summarization or not
- how much raw audio should be retained after transcription
