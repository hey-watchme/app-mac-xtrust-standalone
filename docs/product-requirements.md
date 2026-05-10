# Ambient Memo Room Device Requirements

Date: 2026-05-09 JST

## Purpose

Build a local-first ambient memo system for shared room devices.

This product is not a personal notes app. It is a device that belongs to an
organization, is installed in a room or field site, and is used temporarily by
people who are physically present there.

The design target is:

- local capture and local processing
- organization-owned operation
- short-lived operator access
- strong privacy between one meeting and the next

## Product definition

The product is a shared, room-installed meeting device.

Typical usage:

1. A device is assigned to one room or one field location.
2. A person with permission starts access on that device.
3. The device captures one meeting or one bounded recording activity.
4. The result is viewed, copied, or printed on the spot.
5. Access ends and the next person must not see the prior meeting contents.

This is closer to a whiteboard or copier interaction model than to a personal
workspace app.

## Core domain model

The system has four structural levels above captured content.

### 1. Organization

Definition:

- top-level owner of data and policy
- usually one company or one legal operating unit
- owns workspaces and devices

Fields:

- `organization_id`
- `name`
- `status`
- `created_at`

### 2. Workspace

Definition:

- one operating unit under an organization
- typically a branch, office, site, department, or business unit
- owns multiple devices

Fields:

- `workspace_id`
- `organization_id`
- `name`
- `code`
- `status`
- `created_at`

### 3. Device

Definition:

- one installed shared machine
- typically one room device or one field device
- belongs to one workspace
- acts as the physical boundary for in-room use

Fields:

- `device_id`
- `organization_id`
- `workspace_id`
- `display_name`
- `location_label`
- `status`
- `retention_policy_id`
- `created_at`

### 4. Account

Definition:

- one human identity with permission to use the system
- not the owner of meeting data
- may change frequently over time

Fields:

- `account_id`
- `display_name`
- `employee_code` later if needed
- `status`
- `created_at`

### Organization membership

Definition:

- links one account to one organization
- carries role and access policy

Fields:

- `membership_id`
- `organization_id`
- `account_id`
- `role`
- `status`
- `created_at`

## Session model

The word `session` must be split into two meanings.

### 1. AccessSession

Definition:

- one temporary access grant on one device
- begins when a permitted person authenticates or unlocks the device
- ends by logout, timeout, or forced reset

Fields:

- `access_session_id`
- `device_id`
- `account_id`
- `started_at`
- `ended_at`
- `status`
- `authentication_method`

### 2. CaptureSession

Definition:

- one meeting or one bounded capture run
- created on one device inside one workspace
- may be initiated by a current access session
- owns topics and utterances

Fields:

- `capture_session_id`
- `organization_id`
- `workspace_id`
- `device_id`
- `started_by_account_id`
- `access_session_id` nullable
- `started_at`
- `ended_at`
- `status`
- `meeting_context_profile`
- `utterance_count`
- `topic_count`

## Captured content model

### Topic

Definition:

- a cluster of utterances within one capture session
- the first working rule remains a new topic after 1 minute of silence

Fields:

- `topic_id`
- `capture_session_id`
- `started_at`
- `ended_at`
- `status`
- `summary_text`
- `summary_status`
- `summary_error`

### Utterance

Definition:

- one contiguous span of speech
- speech belongs to the same utterance while silence does not exceed 3 seconds

Fields:

- `utterance_id`
- `capture_session_id`
- `topic_id` nullable until grouped
- `started_at`
- `ended_at`
- `duration_seconds`
- `audio_file_path`
- `transcript_text`
- `transcription_status`
- `transcription_error`

## Ownership rules

- `Organization` is the root owner of operational data.
- `Workspace` is an operational grouping under one organization.
- `Device` is the physical execution point under one workspace.
- `Account` is an identity and permission subject, not the root owner of
  captured meeting data.
- `CaptureSession` belongs to `organization + workspace + device`.
- `AccessSession` belongs to `device + account`.
- `Topic` and `Utterance` inherit organization/workspace/device scope through
  `CaptureSession`.

## Privacy and retention requirements

Privacy isolation is a first-class product requirement.

The device must be safe for consecutive meetings by different people in the
same room.

Required behavior:

- a person must not see the prior meeting by default when arriving at the
  device
- the UI must reset after logout or timeout
- access to prior captured content must require explicit policy and permission
- the system must support automatic purge or sealed retention based on device
  policy

The product must support device-level policy such as:

- `require_login_to_start_capture`
- `auto_logout_after_seconds`
- `retain_capture_after_logout`
- `purge_after_minutes`
- `allow_print`
- `allow_export`
- `allow_reopen_closed_capture`

## Functional requirements

### Shared device boot

- one device is assigned to one workspace
- device identity is fixed at bootstrap and does not need daily re-selection
- the device can show its organization, workspace, and room identity in
  diagnostics

### Access control

- a permitted person can start an `AccessSession`
- access may later be backed by badge tap, SSO, QR, PIN, or another short-lived
  authentication method
- access automatically ends after logout, inactivity, or policy timeout
- capture start can be blocked when access is required but missing

### Capture lifecycle

- a permitted person can create one `CaptureSession`
- only one active capture session is required for the first implementation
- the device can monitor microphone input continuously while capture is active
- VAD determines speech spans
- each detected span is stored as one utterance under the active capture session
- topic grouping happens within one capture session

### Local processing

- ASR runs locally
- summarization runs locally
- failure in ASR or summarization must not crash the capture runtime
- failed work remains visible for operator inspection while access is active

### On-site result delivery

- the primary result path is on-device review
- the system may support copy, export, or print depending on device policy
- output should be treated as bounded to the current access period unless policy
  explicitly allows retention

### Purge and reset

- the system can reset the room UI after access ends
- the system can purge local artifacts after a configured TTL
- purge must cover audio, transcript, summary, and transient job evidence when
  policy requires full deletion

## Non-functional requirements

### Local-first

- no required cloud dependency for core capture and summary
- app remains functional offline after local setup
- models are local files, not runtime downloads

### Privacy

- room-to-room and meeting-to-meeting isolation is mandatory
- prior meeting content must not remain casually browsable on a shared device

### Robustness

- failures in ASR, summary, purge, or auth timeout handling are isolated and
  observable
- app restart should preserve durable state according to retention policy
- interrupted summary execution must not leave indefinite `running` state that
  requires direct database intervention

### Observability

- operator can inspect current device identity
- operator can inspect current access state
- operator can inspect active capture state, jobs, and errors
- operator can trigger a safe maintenance recovery path for stale summary state
- diagnostics must make policy and storage behavior explainable

## Explicit non-goals for the next phase

- cloud sync
- multi-device content sharing
- web dashboard integration
- large-scale knowledge retrieval UX
- speaker diarization
- browser-first deployment

## Immediate design consequences

- the current `Session` concept must be reinterpreted as `CaptureSession`
- a new `AccessSession` concept is required
- organization, workspace, device, account, and membership tables are required
- retention and purge policy must be designed as core product behavior, not as
  cleanup later

## First redesign vertical slice

The next meaningful implementation slice is:

1. bootstrap one organization, workspace, and device
2. create one local operator account model and one membership model
3. add short-lived `AccessSession`
4. rename current meeting `Session` into `CaptureSession`
5. attach all captured content to `organization + workspace + device`
6. enforce UI reset and non-browsable prior meeting behavior after access end
7. add policy-driven purge groundwork

That is the real baseline for the room-device version.
