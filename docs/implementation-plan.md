# Room Device Implementation Plan

Date: 2026-05-10 JST

## Purpose

Translate the room-device redesign into an implementation order that can be
executed without losing the already-proven local capture pipeline.

This plan assumes:

- the current PoC already proves local capture, ASR, topic grouping, and local
  summarization
- the next work is a structural refactor
- privacy and retention are now product features, not cleanup tasks

## Progress snapshot

Completed so far:

- Step 1: language and ownership were frozen in docs
- Step 2: root entities were added to SQLite and `AppCore`
- Step 3: one development shared-device bootstrap path was added

Partially completed:

- Step 4: `AccessSession`, local mock login, locked screen, logout path, and
  settings visibility are implemented
- Step 6 has partial hardening now: summary execution is serialized, startup can
  recover stale `running` summary rows, and operators have a self-service reset
  path in `Settings`

Still open from Step 4:

- idle-timeout handling
- real auth integration seam beyond local mock access

## Planned execution order

### Step 1: Freeze language and ownership

Work:

- use the same terms everywhere: `Organization`, `Workspace`, `Device`,
  `Account`, `OrganizationMembership`, `AccessSession`, `CaptureSession`
- stop using the old overloaded `Session` term in new design docs
- confirm the ownership rule:
  `Organization -> Workspace -> Device -> CaptureSession -> Topic -> Utterance`

Deliverable:

- aligned docs and naming plan

### Step 2: Add root entities to persistence

Work:

- add SQLite tables for:
  - `organizations`
  - `workspaces`
  - `devices`
  - `accounts`
  - `organization_memberships`
  - `device_policies`
- add domain models and stores in `AppCore`

Deliverable:

- the app can persist organization/workspace/device/account metadata

### Step 3: Bootstrap one installed device

Work:

- define how this Mac identifies itself as one room device
- create a first-run bootstrap path for one organization, workspace, and device
- expose the current device scope in diagnostics

Deliverable:

- the app can state which organization/workspace/device it is running as

### Step 4: Introduce access sessions

Work:

- add `AccessSession` model, store, and service
- add minimal local auth mock flow suitable for development
- implement logout and idle-timeout handling
- add a neutral locked screen when no active access session exists

Deliverable:

- the device can be entered and exited as a temporary shared resource
- the UI can return to a locked screen after logout
- the operator can inspect device scope from a settings surface

### Step 5: Rename current session into capture session

Work:

- rename the current `Session` domain concept to `CaptureSession`
- migrate SQLite schema and app services
- attach `organization_id`, `workspace_id`, `device_id`,
  `started_by_account_id`, and optional `access_session_id`
- update UI language and diagnostics accordingly

Deliverable:

- captured meeting data now lives under the shared-device hierarchy

### Step 6: Preserve the proven local pipeline

Work:

- keep the existing flow working under `CaptureSession`:
  - VAD-based utterance creation
  - recording artifact validation
  - transcription jobs
  - topic assignment
  - topic summarization
  - wrap-up generation
- harden local summary execution so that repeated operator input cannot launch
  parallel MLX jobs on the same device
- recover interrupted topic summary state on restart without requiring manual
  SQLite edits

Deliverable:

- the redesign does not regress the already-proven local speech pipeline
- the operator can recover from interrupted summary state from the product UI

### Step 7: Enforce privacy-safe UI behavior

Work:

- hide prior capture content when access ends
- reset the app to a neutral device state on logout or timeout
- prevent casual browsing of earlier meetings from the shared UI by default

Deliverable:

- the next room user cannot simply open the prior meeting contents

### Step 8: Add retention and purge behavior

Work:

- implement device policy evaluation
- add purge scheduling and purge execution
- delete or seal artifacts according to policy
- make purge observable in diagnostics

Deliverable:

- retention is explicit, testable, and not left to manual cleanup

### Step 9: Add bounded output flows

Work:

- support on-device review
- add policy-controlled copy/export/print actions
- ensure output flow does not reopen archived browsing behavior

Deliverable:

- the current meeting can retrieve results safely on-site

### Step 10: Prepare for real authentication methods

Work:

- introduce an auth adapter seam
- keep local mock auth for development
- allow later integration of badge, SSO, PIN, or QR flows

Deliverable:

- auth integration can evolve without redesigning capture logic again

## Dependency rules

- do not add real auth before `AccessSession` exists
- do not retrofit purge after broad history browsing is added
- do not attach account ownership directly to utterances or topics
- do not keep the old `Session` term after `CaptureSession` migration begins

## Risks to manage

### Risk 1: Naming confusion

If old `Session` and new `AccessSession` coexist unclearly, both code and docs
will drift.

Mitigation:

- rename early

### Risk 2: Privacy gaps during transition

If the room-device UI is added before logout/reset behavior, the product may
look more complete while still leaking prior meeting visibility.

Mitigation:

- ship access boundary and reset behavior before richer browsing

### Risk 3: Migration complexity

The current SQLite schema is `sessions`-rooted.

Mitigation:

- add new root entities first
- then migrate current `sessions` into `capture_sessions`
- keep migration steps explicit and testable

## Completed runtime safety work

The summary crash-prevention design (`summary-runtime-safety.md`) has shipped:
`MemoryPressureMonitor` is in place, `MLXSummarizer` registers its subprocess
PID with the monitor, and `.critical` memory pressure triggers SIGKILL. The
static 8 GB pre-flight check has been replaced by a minimal sanity check.

## Completed LLM server residency work

The LLM execution path has shipped as a long-lived `mlx_vlm.server`
subprocess shared by both `MLXSummarizer` and `MLXChatRunner` (formerly each
call spawned its own short-lived `mlx_vlm generate` subprocess). The
`MLXModelServer` actor in the app target owns the lifecycle: lazy spawn on
the first request, readiness polling on `GET /health`, idle teardown after
10 minutes without requests, and restart-on-death. The subprocess PID is
still registered with `MemoryPressureMonitor`, so the SIGKILL pathway is
unchanged — only the subprocess lifetime is longer. `AppDiagnostics` and
`SettingsView` expose the server state for manual inspection.

The formal architecture is now in `architecture.md` (section
"Local LLM runtime"). The detailed design, PoC measurements, and
failure-mode handling are in `llm-server-residency.md`.

## Recommended next coding task

1. rename the current `Session` domain model into `CaptureSession`
2. migrate SQLite and service boundaries so meeting data belongs to
   `organization + workspace + device`
3. attach optional `access_session_id` and `started_by_account_id`

That is the cleanest next structural move before adding idle-timeout or richer
auth flows.
