# Manual Verification Checklist

Date: 2026-05-08 JST

## Purpose

Fix the exact manual checks that must pass before starting capture runtime split
(Phase 5: microphone monitor, VAD boundary detector, utterance recorder).

Each check confirms a specific persisted contract, not a UI effect. If a check
fails, the failure points to a broken contract boundary — not to a UI bug.

## Prerequisites

- Whisper model present at:
  `~/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/whisper/small.pt`
- App built and running from Xcode with `Signing Certificate: Development`
- All workspace paths visible in Diagnostics screen

## Workspace root

```
~/Library/Application Support/XTrust/com.xtrust.mac-local-first/
├── audio/
├── transcripts/
├── jobs/
│   └── transcription/
│       └── <job_id>/
│           ├── stdout.txt
│           ├── stderr.txt
│           └── <output_files>
└── xtrust-mac-local-first.sqlite
```

---

## Check 1 — Basic flow

Goal: confirm that one full recording → transcription cycle produces the
expected artifacts on disk and shows correct state in the UI.

Steps:

1. Launch the app. Create a new session.
2. Press `Start Recording`. Speak a few words in Japanese. Press `Stop Recording`.
3. Confirm in Session Detail:
   - `Status: completed`
   - `Audio File` shows a path under `audio/`
   - `Duration` shows a non-zero value
4. Open Finder at `audio/`. Confirm the wav file exists and has a non-zero size.
5. Press `Transcribe Recording`.
6. While transcription is running, confirm in Session Detail:
   - `Transcription: running`
   - `Transcribe Recording` button is disabled
7. After completion, confirm in Session Detail:
   - `Transcription: completed`
   - `Transcribe Recording` button is enabled
8. Confirm `Job Attempts` section shows one attempt with:
   - `Status: completed`
   - `Stdout` path and `Stderr` path are shown (or absent if empty)
   - `Transcript ID` and `Transcript File` are shown under this attempt
   - Transcript text is visible under the file path
9. Confirm `Transcript` section at the bottom shows the same transcript text.
10. Open Finder at `transcripts/`. Confirm one `.txt` file exists.
11. Open Finder at `jobs/transcription/`. Confirm one `<job_id>/` directory
    exists containing at least `stdout.txt` or `stderr.txt`.

Pass: all artifact paths exist on disk and all UI fields match.

---

## Check 2 — Restart persistence

Goal: confirm that job state and transcript artifacts survive app quit and
relaunch without data loss.

Steps:

1. Complete Check 1 so that one completed transcription job exists.
2. Note the following values from Session Detail:
   - Session ID
   - Job ID from Job Attempts
   - Transcript ID from Job Attempts
3. Quit the app completely (Cmd+Q).
4. Relaunch the app.
5. Select the same session by Session ID.
6. Confirm in Session Detail:
   - `Transcription: completed`
   - Job Attempts section shows the same Job ID as noted
   - Transcript ID under the attempt matches the noted value
   - Transcript text is still visible
7. Confirm the same files still exist on disk (audio wav, transcript txt, job
   directory).

Pass: all noted values are identical after restart. No fields are blank or reset
to idle.

---

## Check 3 — Retry creates a new job

Goal: confirm that retrying transcription creates a new job with a new ID and
does not overwrite or remove the previous job's evidence.

Steps:

1. Complete Check 1 so that one completed transcription job exists.
2. Note:
   - Job ID of the first attempt (Attempt 1)
   - Transcript ID of the first attempt
3. Press `Retry Transcription`.
4. Wait for completion.
5. Confirm in Job Attempts:
   - Two attempts are listed
   - Attempt 1 still shows the original Job ID
   - Attempt 2 shows a new, different Job ID
   - Attempt 2 shows a new Transcript ID
   - Attempt 2 shows transcript text
6. Confirm on disk:
   - `jobs/transcription/` contains two separate directories (one per job ID)
   - `transcripts/` contains two separate txt files (one per artifact ID)
7. Confirm the `Transcript` section at the bottom shows the transcript from the
   latest attempt.

Pass: two independent job directories and two independent transcript files exist.
The first job's evidence is intact.

---

## Check 4 — Failure diagnostics

Goal: confirm that a failed transcription job retains its stderr and failure
message, and that this evidence is visible in the UI and on disk.

Steps:

1. Temporarily remove the Whisper model file or rename it so it cannot be found:
   ```
   mv ~/Library/Application\ Support/XTrust/com.xtrust.mac-local-first/models/whisper/small.pt \
      ~/Library/Application\ Support/XTrust/com.xtrust.mac-local-first/models/whisper/small.pt.bak
   ```
2. Create a new session. Record a short wav. Stop recording.
3. Press `Transcribe Recording`.
4. Wait for failure.
5. Confirm in Session Detail:
   - `Transcription: failed`
6. Confirm in Job Attempts:
   - One attempt with `Status: failed`
   - `Stderr` path is shown
   - `Failure` message describes the error (not a generic crash)
7. Open the Stderr file path shown in the UI. Confirm it contains output from
   Whisper or the process runner.
8. Confirm on disk:
   - `jobs/transcription/<job_id>/stderr.txt` exists with non-zero content
   - No file was promoted to `transcripts/`
9. Restore the model file:
   ```
   mv ~/Library/Application\ Support/XTrust/com.xtrust.mac-local-first/models/whisper/small.pt.bak \
      ~/Library/Application\ Support/XTrust/com.xtrust.mac-local-first/models/whisper/small.pt
   ```
10. Press `Retry Transcription` on the same session.
11. Confirm retry succeeds and Check 3 conditions hold.

Pass: failure evidence is retained on disk and visible in UI. Recovery by retry
works after model is restored.

---

## Check 5 — Attempt-level transcript artifact linkage

Goal: confirm that after multiple attempts, each attempt in Job Attempts shows
only its own transcript artifact — not a shared or latest-only artifact.

Steps:

1. Complete Check 3 so that two successful attempts exist.
2. In Job Attempts, open Attempt 1 and note its `Transcript ID`.
3. Open Attempt 2 and note its `Transcript ID`.
4. Confirm the two Transcript IDs are different.
5. Open each Transcript File path in Finder. Confirm they are distinct files.
6. (Optional) If the two recordings produced different text, confirm each
   attempt shows its own transcript text in the UI.

Pass: each attempt shows a distinct Transcript ID and Transcript File. No
attempt borrows another attempt's artifact.

---

## Failure handling reference

| Symptom | Likely contract failure |
|---------|------------------------|
| Transcript shows `idle` after successful run | Session-level transcription state was not removed from write path (Task 2 regression) |
| Job Attempts empty after restart | SQLite job rows not persisted or not loaded on restart |
| Retry shows only one attempt | New job not inserted; old job overwritten |
| Stderr path shown but file missing | Job workspace directory was deleted after completion |
| Transcript ID same across attempts | `transcriptionJobID` linkage broken in `TranscriptArtifactMetadata` |
| Transcript section shows wrong text | `allTranscriptTexts` aggregation using wrong artifact sort order |

---

## After all checks pass

All five checks passing means:

- the persisted job pipeline is stable enough to proceed
- failure evidence is durable and diagnosable from the UI
- retry creates independent evidence per attempt
- restart does not lose any persisted state

At this point, Phase 5 (capture runtime split) can begin with a known baseline.
