# Mac Local-First Room Device Architecture

Date: 2026-05-09 JST

## Objective

Define the architecture for the next phase of the macOS local-first product.

The first PoC proved the local capture pipeline:

```text
session
  -> utterance recording artifact
  -> transcription job
  -> transcript artifact
  -> topic assignment
  -> topic summary job
```

That vertical slice works, but it assumes a personal or single-operator usage
shape. The next product shape is different: one organization-owned device in one
room, used briefly by many different people over time.

## Architectural shift

The new root is not the personal session.

The new root is:

```text
organization
  -> workspace
    -> device
      -> access session
      -> capture session
```

This changes the design pressure in three ways:

- identity becomes short-lived and replaceable
- privacy isolation between meetings becomes mandatory
- retention and purge become first-class behavior

## Design principles

- treat `Organization` as the root owner of data and policy
- treat `Device` as the physical execution point
- treat `Account` as an identity and permission subject, not the data owner
- separate temporary device access from captured meeting content
- enforce explicit policy around retention, export, and purge

## Domain model

### Organization

Responsibilities:

- owns workspaces and devices
- owns policy defaults
- is the top-level data ownership boundary

### Workspace

Responsibilities:

- groups devices under one operating unit
- usually maps to a branch, office, site, or department

### Device

Responsibilities:

- represents one installed room or field device
- anchors physical-local behavior
- owns device policy such as login requirement, timeout, and purge policy

### Account

Responsibilities:

- represents one person who may use the device
- participates in permission checks and audit trails

Keep out:

- ownership of captured meeting data

### OrganizationMembership

Responsibilities:

- links accounts to organizations
- carries roles and authorization state

### AccessSession

Responsibilities:

- represents a temporary grant to use one device
- starts on authentication or device unlock
- ends on logout, inactivity, timeout, or forced reset

Keep out:

- capture artifacts
- topic state
- transcript state

### CaptureSession

Responsibilities:

- represents one meeting or bounded capture activity
- belongs to one organization, one workspace, and one device
- may record which access session and account initiated it
- owns topics and utterances

This is the renamed and narrowed successor to the current `Session`.

### Topic

Responsibilities:

- groups utterances inside one capture session
- stores topic-level summary state

### Utterance

Responsibilities:

- points to one finalized recording artifact
- owns transcription lifecycle
- belongs to one capture session

## Session split

The word `session` is overloaded and must be separated in both code and docs.

### AccessSession lifecycle

```text
requested
  -> active
  -> idleTimedOut | loggedOut | revoked
```

### CaptureSession lifecycle

```text
draft
  -> listening
  -> paused
  -> closed
  -> purged
  -> failed
```

Rules:

- a capture session may require an active access session before it can start
- ending an access session does not necessarily delete a capture session
  immediately, but it must make the prior content non-browsable on the shared
  UI unless policy explicitly allows otherwise
- purge is a separate state transition, not an implicit side effect hidden from
  diagnostics

## Ownership and foreign key direction

Recommended ownership graph:

```text
Organization --< Workspace --< Device
Account --< OrganizationMembership >-- Organization
Device --< AccessSession >-- Account
Device --< CaptureSession
Account --< CaptureSession (started_by)
AccessSession --< CaptureSession (optional link)
CaptureSession --< Topic --< Utterance
Utterance --< RecordingArtifact
Utterance --< TranscriptionJob --< TranscriptArtifact
```

Recommended foreign keys:

- `workspaces.organization_id`
- `devices.organization_id`
- `devices.workspace_id`
- `organization_memberships.organization_id`
- `organization_memberships.account_id`
- `access_sessions.device_id`
- `access_sessions.account_id`
- `capture_sessions.organization_id`
- `capture_sessions.workspace_id`
- `capture_sessions.device_id`
- `capture_sessions.started_by_account_id`
- `capture_sessions.access_session_id`
- `topics.capture_session_id`
- `utterances.capture_session_id`

## Authentication model

### Current state: guest login

The login flow is currently hard-coded to a single guest account.

When the locked screen is shown, the user taps "ゲストとして利用を開始". This
creates an `AccessSession` with `authenticationMethod: .guest` and the bootstrap
account (displayName: "ゲスト"). No credential is checked.

This is intentional for the current prototype phase. It proves the
`AccessSession` boundary — locked screen, session isolation, and logout reset —
without requiring real identity infrastructure.

The guest account is the `bootstrapAccount` created by
`SharedDeviceBootstrapService` during first-run bootstrap. It is stored in
SQLite and reused on subsequent launches.

### Target state: FeliCa / organizational card login

The intended production authentication method is employee card tap (FeliCa).

Flow:
```text
employee touches FeliCa card to device reader
  -> card ID looked up in organization account directory
  -> AccessSession created with authenticationMethod: .badge
  -> operator lands in the active device view
  -> logout or timeout ends the access session
```

This requires:
- a card reader driver or OS NFC integration
- a local or remotely-synced account directory
- `OrganizationMembership` lookup to verify the card holder is authorized

Design seam:

`AccessSessionService.beginAccess(deviceID:accountID:authenticationMethod:)` is
already parameterized by `AuthenticationMethod`. The guest flow and the badge
flow both call the same service method. Swapping the auth source does not
require changing `AccessSessionService`, `CaptureSession`, or any downstream
capture logic.

`AccessSession.AuthenticationMethod` already includes `.badge`, `.sso`, `.pin`,
and `.qr` as future options. `.guest` replaces the earlier `.localMock` for
prototype use.

### Deferred

- FeliCa / NFC reader integration
- organizational account directory sync
- PIN or QR fallback flows
- SSO integration

## Policy model

Shared room privacy depends on policy, not only on UI courtesy.

At minimum the device policy model should support:

- `require_login_to_start_capture`
- `auto_logout_after_seconds`
- `retain_capture_after_logout`
- `purge_after_minutes`
- `allow_print`
- `allow_export`
- `allow_reopen_closed_capture`

The architecture must allow these policies to be evaluated without rewriting the
capture pipeline itself.

## Storage model

Durable storage stays local and inspectable.

Recommended local stores:

- SQLite for metadata, lifecycle state, policies, and audit evidence
- Application Support directories for audio, transcripts, summaries, and job
  workspaces

The current artifact pipeline remains valid:

```text
capture session
  -> utterance recording artifact
  -> transcription job
  -> transcript artifact
  -> topic summary
```

What changes is the scope attached to the artifacts:

- every durable record should be attributable to `organization + workspace +
  device`

## Summary runtime safety

Topic and meeting summarization are local heavy jobs and must be treated as a
bounded shared device resource.

Rules:

- the device must not launch multiple MLX summary subprocesses concurrently from
  repeated button presses
- summary admission must not block normal operation with conservative static
  thresholds; the host crash boundary is enforced by OS memory pressure events
  and subprocess kill, not by pre-flight byte budgets
- any `summary_status = running` state found after app restart is stale by
  definition and must be recoverable without direct SQLite intervention
- access history and purge history should be independently inspectable

The detailed crash-prevention architecture (multi-layer defense with
`DispatchSource` memory pressure monitoring and subprocess kill) is documented
separately in `summary-runtime-safety.md`.

## Local LLM runtime

Both `MLXSummarizer` (topic and meeting summarization) and `MLXChatRunner`
(general chat) share one local LLM execution path. The execution model is a
long-lived subprocess that holds the model resident in Unified Memory across
many requests.

```text
[SwiftUI app process]
  │
  │  spawns + owns + can SIGKILL
  ▼
[python3 -m mlx_vlm.server]  ─ 127.0.0.1:<ephemeral port>
  │  OpenAI-compatible /v1/chat/completions
  │  model resident in Metal / Unified Memory
  │
[MLXSummarizer]   [MLXChatRunner]   ── HTTP POST ─┘
```

Rules:

- the LLM never runs in-process; it always runs as a subprocess so the parent
  app can SIGKILL it under memory pressure
- one server instance is shared by both the summarizer and the chat runner
- the server is spawned lazily on the first request, not at app startup
- the server outlives individual requests; the model is loaded once and
  reused across many calls
- after a configurable idle window (default 10 minutes), the server is
  terminated to release Unified Memory back to the rest of the device
- the subprocess PID is registered with `MemoryPressureMonitor`; OS-level
  `.critical` memory pressure SIGKILLs the server, and the next request
  triggers a fresh spawn
- if the subprocess dies for any reason (external kill, crash, OOM kill),
  the next request observes the dead connection and respawns transparently

The `MLXModelServer` actor in the app target owns this lifecycle (spawn,
readiness polling on `GET /health`, idle timer, restart-on-death). The
`MLXSummarizer` and `MLXChatRunner` types are thin call sites that build
their own prompts and call one shared `chatCompletion(messages:maxTokens:)`
method on the controller.

`AppDiagnostics` exposes the current server state (Stopped / Starting /
Running / Killed / Failed), PID, ephemeral port, uptime, last request time,
and last error message.

The detailed design, PoC measurements, and failure-mode handling are
documented separately in `llm-server-residency.md`. The crash-prevention
subprocess-kill design (independent of subprocess lifetime) remains in
`summary-runtime-safety.md`.

## Security and privacy boundaries

### UI boundary

- after logout or timeout, the device must reset to a neutral screen
- prior capture content must not remain open in the shared view

### Data boundary

- prior meeting data may exist temporarily according to retention policy
- existence on disk does not imply operator visibility
- visibility must be gated by access state and policy

### Purge boundary

- when policy requires purge, delete audio, transcripts, summaries, and job
  artifacts together
- purge should be observable as a first-class job or event

## Application services

Recommended services for the redesign:

- `OrganizationBootstrapService`
- `DeviceBootstrapService`
- `AccessSessionService`
- `CaptureSessionService`
- `DevicePolicyService`
- `RetentionService`
- existing `TopicAssignmentService`
- existing transcription and summarization runners

## Migration strategy

Do not bolt the new concepts into the current schema ad hoc.

Recommended order:

1. add new root tables: organization, workspace, device, account, membership
2. add access session and device policy tables
3. introduce `CaptureSession` naming in domain and persistence layers
4. attach current content records to the new root identifiers
5. add UI reset and retention flows

## Why this refactor is necessary

The current PoC is valid for proving local ASR and local summarization.

It is not yet valid for:

- a shared room device
- organization-owned deployment
- rapid account turnover
- strong between-meeting privacy
- policy-driven logout and purge

The redesign is therefore structural, not cosmetic.
