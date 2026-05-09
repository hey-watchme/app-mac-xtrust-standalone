# Summarization Prompt Design

Date: 2026-05-09 JST

## Purpose

This document records the current summarization prompt design for Ambient Memo
so prompt tuning can continue without re-reading the implementation first.

The target is not a generic "nice summary." The target is a reusable work memo
for real meetings:

- engineering discussions
- product / planning discussions
- recruiting / HR conversations
- general business meetings

## Current architecture

Summarization now distinguishes two scopes:

- `topic`
- `meeting`

The app sends a structured `SummarizationRequest` with:

- `scope`
- `contextProfile`
- `transcripts`

Current context profiles:

- `general`
- `engineering`
- `product`
- `recruiting_hr`

The profile is stored on each `Session` and selected from the UI before
summarization.

## Design intent

The prompt is optimized for business usefulness rather than conversational
fluency.

Core rules:

- summarize facts, not vibes
- separate `決定事項` and `未決事項`
- extract `アクション`
- avoid inventing owners or deadlines
- explicitly write `要確認` when the source is ambiguous
- produce output that can be pasted into an internal work memo as-is

This is important for Ambient Memo because the operator is likely to review the
memo after a meeting and act on it, not just read a narrative recap.

## Current prompt structure

Every request has the same high-level layout:

1. role and quality rules
2. meeting context description from `contextProfile`
3. extraction priorities from `contextProfile`
4. task instruction from `scope`
5. numbered input text
6. fixed output schema

### Shared rules

The current shared rules instruct the model to:

- stay fact-based
- avoid unsupported inference
- separate decisions from unresolved items
- mark unclear ownership / deadlines as `要確認`
- avoid filler or commentary
- write in concise Japanese suitable for internal notes

### Topic scope

`topic` is used when summarizing utterances inside a single topic.

Current output schema:

- `トピック`
- `決定事項`
- `未決事項`
- `アクション`
- `リスク・懸念`

Intent:

- preserve the local meaning of one discussion block
- make unresolved design or execution issues visible
- keep action extraction close to the original utterances

### Meeting scope

`meeting` is used when summarizing already-generated topic summaries into one
session wrap-up.

Current output schema:

- `会議サマリー`
- `決定事項`
- `未決事項`
- `アクション`
- `フォローアップ観点`

Intent:

- deduplicate topic-level overlap
- make whole-meeting conclusions easy to review
- surface what must be followed up after the meeting

## Current profile guidance

### `general`

Priorities:

- what was decided
- what remains unresolved
- who does what next
- risks and follow-up items

### `engineering`

Priorities:

- specification changes
- implementation direction
- architectural decisions
- bugs, technical constraints, dependencies, risks
- ownership, priority, release timing

### `product`

Priorities:

- target users and problems
- hypotheses and planning options
- prioritization and decision rationale
- next validation steps and open questions

### `recruiting_hr`

Priorities:

- observable facts
- confirmation items
- next operational actions
- sensitive items that should not be overstated

Special caution:

- avoid overconfident judgments
- prefer `要確認` to invented interpretation

## Known limitations

The current design is intentionally narrow.

- No free-text session brief is passed yet.
- No custom profile per team or project exists yet.
- No profile-specific output schema is configurable from the UI.
- Topic summaries and meeting summaries still share one summarizer
  implementation; only the request shape changes.
- There is no offline evaluation harness yet for comparing prompt variants.

## Recommended tuning approach

Tune prompts with real meeting samples, not synthetic examples.

Recommended evaluation axes:

- decision recall
- unresolved-item recall
- action extraction quality
- false certainty rate
- verbosity
- usefulness as a next-day work memo

Suggested process:

1. Collect 10-20 representative sessions per profile.
2. Save baseline outputs from the current prompt.
3. Change one dimension at a time.
4. Compare outputs side by side.
5. Keep changes only if they improve factual usefulness, not just style.

## Safe tuning directions

Good next experiments:

- split `engineering` into `daily sync`, `design review`, `incident`
- split `product` into `planning`, `spec review`, `roadmap`
- add stronger instructions for decisions vs proposals
- add explicit extraction of blockers and dependencies
- tune meeting-level wrap-up to produce cleaner executive summaries

Risky changes:

- asking for too much interpretation
- forcing owners or deadlines when the transcript does not support them
- adding excessive formatting that hides uncertainty
- making one prompt serve every meeting type equally

## Future extension points

If tuning continues, the next logical additions are:

- session-level free-text context note
- project / team-specific custom prompt templates
- persisted prompt version metadata on summaries
- prompt regression fixtures for representative meetings

## Source of truth in code

- `Packages/AppCore/Sources/AppCore/Ports/Summarizer.swift`
- `Packages/AppCore/Sources/AppCore/Domain/Session.swift`
- `Packages/AppCore/Sources/AppCore/Application/TopicSummaryRunner.swift`
- `XTrustMacApp/App/AppState.swift`
- `XTrustMacApp/Shared/MLXSummarizer.swift`
