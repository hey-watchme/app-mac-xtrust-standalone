# Next Session Handoff

Date: 2026-05-08 JST

## Current decision

Implementation work is paused.

Reason:

- the current effort drifted into incremental debugging before the product
  contract was frozen
- continuing implementation without a fixed product definition will waste more
  time

## What to carry forward

The next session should start from:

- `docs/product-requirements.md`
- `docs/milestones.md`
- `docs/architecture.md`

## What not to do first

Do not resume with:

- more point fixes in the current ASR path
- more UI polish
- more playback or convenience controls

Those are secondary until the product path is fixed.

## First discussion for the next session

The first task in the next session should be to confirm:

1. the exact meaning of `memo`
2. the exact background runtime behavior on macOS
3. the first VAD strategy to adopt
4. the first local ASR runtime to standardize on
5. the retention policy for raw audio after transcription

## Recommended restart point

Restart implementation from Milestone 2 or 3, not from the current ad hoc ASR
flow:

- Milestone 2 if the microphone monitoring runtime is not yet production-shaped
- Milestone 3 if the runtime is accepted and the next real proof is utterance
  segmentation
