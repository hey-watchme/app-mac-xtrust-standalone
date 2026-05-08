# Next Session Handoff

Date: 2026-05-08 JST

## Current decision

The first UI-triggered local transcription has succeeded.

What this proved:

- session creation works
- microphone recording works
- playback works
- Whisper model discovery works
- `ffmpeg` resolution from the app process works
- transcript output can be produced under the local workspace

What this did not change:

- the current `Transcribe Recording` path is still scaffolding
- ASR is still invoked directly from the UI flow
- transcription attempts are not yet persisted as first-class jobs
- output still needs to move to a dedicated job workspace model

## What to carry forward

The next session should start from:

- `docs/product-requirements.md`
- `docs/milestones.md`
- `docs/design-reset.md`
- `docs/implementation-plan.md`
- `docs/architecture.md`

## What not to do first

Do not resume with:

- more point fixes in the current direct ASR button path
- more UI polish
- more playback or convenience controls

Those are secondary until the product path is fixed.

## First discussion for the next session

The first task in the next session should be to confirm:

1. the `TranscriptionJob` persistence shape
2. the isolated `jobs/transcription/<job_id>/` workspace contract
3. the final transcript promotion rule from job workspace to `transcripts/`
4. the first UI state model for queued/running/completed/failed transcription
5. the retention policy for raw audio and job diagnostics after success

## Recommended restart point

Restart implementation from the `TranscriptionJob` boundary, not from more ad
hoc session-level ASR fixes.

Recommended restart sequence:

- first wire persisted transcription jobs and isolated job directories
- then move Whisper execution behind that runner
- only after that resume VAD and utterance segmentation work
