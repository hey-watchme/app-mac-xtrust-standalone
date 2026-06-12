# Manual Verification Checklist

Date: 2026-06-12 JST

## Purpose

Fix the exact manual checks that must pass for the rebuilt realtime meeting
pipeline (SpeechAnalyzer streaming ASR -> live transcript -> meeting minutes).

Each check confirms a specific contract, not a UI effect. If a check fails,
the failure points to a broken contract boundary — not to a UI bug.

## Prerequisites

- macOS 26 on Apple Silicon
- App built and running **from Xcode** with `Signing Certificate: Development`
  (the SPM `swift run` binary has no `Info.plist`, so microphone permission
  behaves differently — do not use it for manual verification)
- Gemma 4 model directory present at
  `~/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/gemma4-mlx/`
  (required for minutes generation and chat)
- No ASR model installation is required; the OS downloads the ja-JP speech
  asset on first use

## Workspace root

```
~/Library/Application Support/XTrust/com.xtrust.mac-local-first/
├── audio/
│   └── <capture_session_id>.wav   (one wav per capture session)
├── models/
│   └── gemma4-mlx/
└── xtrust-mac-local-first.sqlite
```

---

## Shared-device checks

### Check 0 — Locked start state

Goal: confirm the app launches into a neutral shared-device screen when no
access session is active.

Steps:

1. Launch the app.
2. Confirm the first screen is the locked room-device screen.
3. Confirm it shows:
   - organization
   - workspace
   - device
4. Confirm no prior meeting list is visible before access begins.

Pass: the app starts locked and no prior meeting contents are casually visible.

### Check 1 — Begin local access and inspect settings

Goal: confirm local guest access opens the shared-device UI and the settings
screen shows current scope metadata.

Steps:

1. From the locked screen, begin access (`利用を開始`).
2. Confirm the meeting UI becomes visible.
3. In the left sidebar footer, press `Settings`.
4. Confirm the settings screen shows:
   - organization
   - workspace
   - workspace code
   - device
   - device location
   - bootstrap account
   - active access
   - access status

Pass: access begins successfully and settings reflect the current shared-device
scope.

### Check 2 — Logout resets the shared UI

Goal: confirm leaving access returns the app to a neutral shared-device state.

Steps:

1. While access is active, run one meeting if needed.
2. Press `退出` in the sidebar header.
3. Confirm the app returns to the locked room-device screen.
4. Confirm the prior visible meeting list is no longer shown.

Pass: logout resets the shared UI and returns to the locked screen.

---

## Meeting pipeline checks

### Check 3 — Cold start: speech asset download is visible

Goal: confirm that when the ja-JP speech asset is not yet installed, the app
surfaces the download state instead of failing or hanging silently.

Steps:

1. On a machine (or after an OS state) where the ja-JP speech asset is not
   installed, open `Settings` and confirm `Diagnostics` shows:
   - `Speech Locale Supported: Yes`
   - `Speech Assets Installed: No`
2. Press `会議を開始`.
3. Confirm the capture state pill shows the asset download step (with
   progress) before recording starts.
4. Wait for the download to complete. Confirm the pill proceeds to `録音中`
   without relaunching the app.
5. Confirm `Diagnostics` now shows `Speech Assets Installed: Yes`.

Pass: the missing asset is downloaded on demand with visible progress, and
the meeting starts afterwards.

Note: if the asset is already installed, this check is satisfied by
confirming `Speech Assets Installed: Yes` in `Diagnostics`.

### Check 4 — Meeting start latency and level meter

Goal: confirm the capture pipeline starts fast and audio is flowing
immediately.

Steps:

1. With the speech asset installed, press `会議を開始`.
2. Confirm the capture state pill walks through preparation (permission
   check -> asset check -> starting) and reaches `録音中` within about 2
   seconds.
3. Confirm the audio level meter moves immediately when you speak or tap the
   microphone.

Pass: `録音中` within ~2 s and the level meter responds immediately.

### Check 5 — Live transcript: volatile then finalized

Goal: confirm the streaming ASR contract — fast volatile partials that become
durable finalized rows.

Steps:

1. While recording, speak a few sentences in Japanese.
2. Confirm gray volatile (partial) text appears within about 1 second of
   speaking.
3. Confirm that when you pause, the volatile text is replaced by a finalized
   transcript row with a `HH:MM:SS` timestamp.
4. Speak again and confirm new finalized rows append in order; earlier rows
   do not change.

Pass: volatile text < 1 s, finalized rows are timestamped and stable.

### Check 6 — Close meeting: minutes generation and crash recovery

Goal: confirm minutes are generated on close, and that interrupted generation
recovers automatically on relaunch.

Steps:

1. After speaking enough content, press `会議を終了して議事録を作成`.
2. Confirm the meeting closes and minutes generation starts with a visible
   progress state (`議事録を生成中…`).
3. Confirm the completed minutes render in Japanese with the expected
   sections (会議サマリー / 決定事項 / 未決事項 / アクションアイテム) and can
   be copied / exported as Markdown together with the timestamped transcript.
4. Run a second meeting, close it, and **force-quit the app (Cmd+Opt+Esc or
   `kill -9`) while minutes generation is still running**.
5. Relaunch the app and begin access.
6. Confirm the interrupted minutes are recovered automatically: the stored
   `running` state is reset to `pending` and generation re-runs without
   manual intervention. `Diagnostics` shows `Recovered Minutes` > 0.

Pass: minutes generate with progress, and a force-quit mid-generation heals
itself on the next launch.

### Check 7 — Diagnostics surface

Goal: confirm the operator can inspect the speech asset and local LLM runtime
state.

Steps:

1. Open `Settings` -> `Diagnostics`.
2. Confirm the speech rows are present:
   - `Speech Locale` (ja-JP)
   - `Speech Locale Supported`
   - `Speech Assets Installed`
3. Confirm the `MLX Server` section shows the current state
   (Stopped / Starting / Running / Killed / Failed), PID, port, uptime, and
   last request time.
4. Confirm `Gemma 4 MLX Ready` reflects whether the local model directory
   exists.

Pass: asset status and MLX server state are inspectable without a terminal.

### Check 8 — Logout returns to the locked screen

Goal: confirm the shared-device privacy boundary after a full meeting cycle.

Steps:

1. Complete a meeting (Checks 4-6).
2. Press `退出`.
3. Confirm the app returns to the locked room-device screen and the prior
   meeting content is not casually visible.

Pass: same as Check 2, verified after a real meeting cycle.

---

## Local LLM runtime checks

### Check 9 — MLX server residency lifecycle

Goal: confirm that the local LLM (`mlx_vlm.server`) runs as a long-lived
subprocess that is reused across minutes / chat calls, auto-stops when idle,
and restarts cleanly after an external kill or memory-pressure shutdown.

Background: subprocess isolation is still required (see
`summary-runtime-safety.md`). This check verifies the lifecycle only.

Steps:

1. Launch the app. Begin access. Open `Settings`.
2. In the `Diagnostics` card, confirm the `MLX Server` section is visible.
   Initial state should be:
   - `State: Stopped`
   - `PID: —`
   - `Port: —`
3. Trigger one LLM call (close a meeting to generate minutes, or send one
   chat message). Within 60 s, observe `MLX Server` transitions:
   - `State: Starting` → `State: Running`
   - `PID` is populated (a positive integer)
   - `Port` is populated (e.g. an ephemeral port in the 49152–65535 range)
   - `Uptime` starts counting from 0
4. Run a second minutes or chat call within 10 minutes. Confirm:
   - `PID` is unchanged
   - `Port` is unchanged
   - `Uptime` keeps increasing (it is not reset)
   - `Last Request` updates to `just now` / a small number of seconds
5. From a terminal, externally kill the server:
   ```
   kill -9 <pid shown in Settings>
   ```
   Trigger another minutes / chat call. Confirm:
   - The first call after the kill may briefly surface an error (server died)
   - The very next call shows the server restarted with a **new** PID and a
     new Port
   - `Uptime` resets to a small value
6. Press `Stop MLX Server` in the `MLX Server Control` card. Confirm:
   - `State: Stopped`
   - `PID` and `Port` become `—`
   - No `mlx_vlm.server` process remains under
     `ps aux | grep mlx_vlm.server`
7. Idle teardown: leave the app open with no minutes / chat activity for
   slightly over the configured idle timeout (default 10 minutes). Confirm:
   - `MLX Server` returns to `State: Stopped`
   - No `mlx_vlm.server` process remains
8. (Optional, requires `stress-ng`) Force memory pressure during inference:
   ```
   stress-ng --vm 4 --vm-bytes 12G --timeout 30s
   ```
   While stress is active, trigger a minutes generation. Confirm:
   - `MemoryPressureMonitor` sends SIGKILL to the registered PID
   - `MLX Server` flips to `State: Killed` with `Last Error` mentioning
     memory pressure
   - The host Mac remains responsive
   - A subsequent call after stress ends spawns a fresh server

Pass: the model process is reused across requests, idle-stops automatically,
restarts after kill, and surfaces memory-pressure kills as a distinct state
without taking down the host.

---

## Failure handling reference

| Symptom | Likely contract failure |
|---------|------------------------|
| Pill stuck in asset download forever | OS speech asset download stalled; `SpeechAssetStatusProvider` / install request not completing |
| Pill never reaches `録音中` | Microphone permission denied, or audio engine failed to start (`CaptureEngineFailure`) |
| Level meter moves but no volatile text | Transcriber stream not delivering volatile results; check locale support in Diagnostics |
| Volatile text never finalizes | Finalization events not emitted or not consumed by `MeetingStore` |
| Finalized rows missing after relaunch | `Utterance` rows not persisted by `LiveMeetingRecorder` (write-behind broken) |
| Minutes stuck in `running` after relaunch | `MinutesRecoveryService` not re-enqueueing on startup |
| Minutes fail immediately | Gemma model directory missing, or `mlx_vlm.server` failed to start (see MLX Server state) |
| Wav file missing or zero bytes | Capture engine did not write `audio/<capture_session_id>.wav` |

---

## After all checks pass

All checks passing means:

- the streaming capture contract (volatile -> finalized -> persisted) holds
- meeting minutes generation is durable across force-quit
- the speech asset and LLM runtime are operator-inspectable
- the shared-device privacy boundary holds after a full meeting cycle
