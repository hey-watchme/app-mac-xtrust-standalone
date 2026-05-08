# Next Session Handoff

Date: 2026-05-08 JST

## Current decision

Whisper transcription now runs through a persisted `TranscriptionJob` runner
with isolated job workspaces, and the UI reads that durable state.

What this proved:

- session creation works
- microphone recording works
- playback works
- Whisper model discovery works
- `ffmpeg` resolution from the app process works
- transcript output can be produced under the local workspace
- one transcription attempt becomes one persisted `TranscriptionJob`
- Whisper output is isolated under `jobs/transcription/<job_id>/`
- stdout, stderr, exit code, and generated files are retained as job evidence
- validated transcript output is promoted into final `transcripts/`
- retry creates a new job attempt instead of overwriting prior state
- `Session Detail` can survive restart and still show job state and attempts

What this did not change:

- the current recording path still materializes one utterance from the session-
  level recording scaffold
- the app is not yet doing continuous listening, VAD, or automatic utterance
  creation
- transcript artifact history is not yet shown per attempt
- topics and summaries still do not exist in the runtime path

## What to carry forward

The next session should start from:

- `docs/product-requirements.md`
- `docs/milestones.md`
- `docs/design-reset.md`
- `docs/implementation-plan.md`
- `docs/architecture.md`

## What not to do first

Do not resume with:

- more point fixes in old session-level transcription fields
- topic or summary work before utterance capture is reliable
- cosmetic UI polish before the remaining durable state is visible

Those are secondary until the product path is fixed.

## First discussion for the next session

The first task in the next session should be to confirm:

1. how transcript artifacts should be shown per job attempt
2. which remaining session-level transcription fields can now be removed or
   downgraded to migration scaffolding
3. the exact manual verification checklist for retry history and restart
   persistence
4. where the capture runtime split should start:
   microphone monitor, VAD boundary detector, or utterance recorder
5. the retention policy for successful job diagnostics and raw audio artifacts

## Recommended restart point

Restart from the remaining Phase 4 cleanup, not from more ad hoc button-path
fixes.

Recommended restart sequence:

- first add transcript artifact history per job attempt
- then reduce the remaining session-level transcription scaffolding
- then lock in manual restart and retry verification
- only after that resume capture runtime split, VAD, and utterance generation
