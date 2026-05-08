# Mac Local-First Architecture

Date: 2026-05-07 JST

## Objective

Fix a minimal architecture boundary before implementation starts.

The intent is to keep the macOS UI thin, keep logic testable, and isolate heavy
local inference work from the main app process as much as practical.

## High-level shape

```text
XTrustMacApp (SwiftUI macOS app)
  -> AppRuntime (dependency wiring only)
    -> AppCore (pure Swift package)
      -> SQLite / filesystem / sidecar wrappers
        -> whisper.cpp / llama.cpp
```

## Layers

### `XTrustMacApp`

Responsibilities:

- app entry point
- window and navigation structure
- macOS permission handling
- dependency wiring
- operator-facing screens and status
- presentation state only

Keep out:

- direct SQL logic
- workspace bootstrap logic
- prompt construction details
- raw process execution details
- transcript and summary business rules

### `AppRuntime`

Responsibilities:

- bootstrap `WorkspacePaths`
- initialize the SQLite store
- wire infrastructure adapters into `AppCore`
- return one stable runtime object to the UI layer

Keep out:

- SwiftUI view logic
- session state transitions
- direct transcript or summary business rules

### `AppCore`

Responsibilities:

- domain models such as `Session`, `Transcript`, and `Summary`
- session state transitions on domain entities
- application services such as `SessionService`
- ports for storage, audio capture, transcription, summarization, and clock
- testable state transitions and validation rules

Keep out:

- `SwiftUI`
- `AppKit`
- hard-coded file locations tied to one machine

### Infrastructure adapters

Responsibilities:

- SQLite-backed stores
- application-support path resolution
- sidecar process execution
- local artifact file management

Adapters should implement `AppCore` ports and remain replaceable.

### Sidecar runtimes

Responsibilities:

- `whisper.cpp` execution for file-based ASR
- `llama.cpp` execution for transcript summarization

Rules:

- do not bundle models into source control
- capture stdout, stderr, exit code, and duration
- treat inference failures as normal job outcomes, not crashes

## First implementation boundary

Start with the smallest split that still helps testing:

- `XTrustMacApp/` for UI and wiring
- `Packages/AppCore/` for pure logic and protocols
- `Tests/` for unit and integration coverage

Do not over-abstract beyond this until the first vertical slice is working.

## Recommended repository skeleton

```text
XTrustMacApp/
  App/
  Features/
  Shared/
  Resources/
Packages/
  AppCore/
    Sources/
    Tests/
Tests/
  AppCoreIntegrationTests/
  XTrustMacUITests/
Fixtures/
  audio/
  transcripts/
  summaries/
ThirdParty/
scripts/
```

## Dependency direction

Keep the dependency flow one-way:

```text
XTrustMacApp -> AppRuntime -> AppCore -> Ports -> Infrastructure/Sidecars
```

`AppCore` must not depend on the macOS UI layer.

## Fake-first rule

Before wiring real `whisper.cpp` or `llama.cpp`, start with fake adapters for:

- transcriber
- summarizer
- audio capture where useful

This allows:

- unit tests for flow control
- integration tests for persistence
- UI progress without model binaries being ready

## Initial non-goals

- streaming ASR
- live token streaming
- RAG
- cross-device sync
- multi-user workflows
