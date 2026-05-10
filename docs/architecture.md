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
