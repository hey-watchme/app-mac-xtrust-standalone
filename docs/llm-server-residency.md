# LLM Server Residency Design

Date: 2026-05-15 JST

## Background

Both `MLXSummarizer` and `MLXChatRunner` currently launch a fresh
`python3 -m mlx_vlm generate` subprocess for **every** call. Each invocation
pays the full cost of:

- Python interpreter startup
- `mlx_vlm` library import
- Reading the Gemma 4 E4B 4bit weights from disk (~4.86 GB)
- Tokenizer / processor initialization

Empirically this means each summary or chat turn takes 15–25 seconds even
before any tokens are generated. On a shared room device this is the dominant
source of perceived latency.

The crash-prevention design documented in `summary-runtime-safety.md` is the
reason the model was put behind a subprocess in the first place. That design
is intentionally retained — the change here only modifies the **lifecycle** of
that subprocess, not its existence.

## Goal

Keep the model loaded in memory across multiple requests, while preserving
the subprocess isolation that lets the parent SwiftUI app kill the model
process under memory pressure.

## Non-goals

- Embedding MLX directly inside the SwiftUI app process. The subprocess
  isolation is a hard requirement; co-locating MLX with the UI process would
  remove the kill-switch that protects the host Mac.
- Replacing `mlx_vlm` with `mlx_lm`. The product roadmap includes image input
  (whiteboard capture). `mlx_vlm.server` already supports `--vision-cache-size`
  and OpenAI-style multimodal `messages` (`image_url` content parts).
- Streaming responses. Not required for the current product flow. Can be added
  later without redesign because the server already supports it.

## Architecture

```
[SwiftUI app process]
  │
  │  spawns + monitors + can SIGKILL
  ▼
[python3 -m mlx_vlm.server (FastAPI, uvicorn)]
  │  127.0.0.1:<port>
  │  ─ model held in Metal/Unified Memory
  │  ─ OpenAI-compatible /v1/chat/completions
  │
[MLXSummarizer]   [MLXChatRunner]
  └─── HTTPS POST ─┘
       (via shared MLXModelClient)
```

### Verified facts (PoC, 2026-05-15)

- `mlx_vlm 0.5.0` ships `mlx_vlm.server` with full OpenAI-compatible
  `/v1/chat/completions`
- `/health` endpoint reports `loaded_model` (non-null after model load) and
  `continuous_batching_enabled` — sufficient for readiness detection
- The `model` field in chat completion requests must equal the absolute path
  passed to `--model` at startup. Mismatched names cause the server to attempt
  a HuggingFace download (404)
- Image input works as OpenAI-style content parts:
  `{"type":"image_url","image_url":{"url":"data:image/png;base64,..."}}`
- On M1 Pro 16 GB:
  - Warm cache: ready ~10 s after process spawn
  - Cold (after SIGKILL): ready ~45 s
  - 2nd text request (model resident): ~3.4 s for 20 tokens
- Server process RSS stays small (~11 MB); model weights live in Metal/Unified
  Memory and are released when the process exits

## Components

### New: `MLXModelServer` (app target)

Responsibilities:

- Spawn and own the `mlx_vlm.server` subprocess
- Wait for readiness via `/health` polling (max ~120 s)
- Provide a single `chatCompletion(messages:images:maxTokens:)` entrypoint
- Register the subprocess PID with `MemoryPressureMonitor` so the existing
  `.critical` → SIGKILL pathway continues to work unchanged
- Detect that the subprocess has died (HTTP connection refused or
  `terminationStatus`) and restart it on the next request
- Auto-terminate the subprocess after a configurable idle window (default
  10 minutes) to release ~5 GB of Unified Memory when the model is not in use

Public API (sketch):

```swift
actor MLXModelServer {
    init(configuration: MLXModelServerConfiguration,
         pressureMonitor: MemoryPressureMonitor)

    // Lazy: starts the server if it is not running.
    // Throws if startup fails or readiness times out.
    func chatCompletion(
        messages: [MLXChatTurn],
        images: [Data],
        maxTokens: Int
    ) async throws -> String

    // Best-effort shutdown. Called from app teardown or by the
    // idle timer.
    func stop() async
}

struct MLXChatTurn: Sendable {
    enum Role { case system, user, assistant }
    let role: Role
    let text: String
}
```

Behavior notes:

- `chatCompletion` is the only public method. Both `MLXSummarizer` and
  `MLXChatRunner` build their own prompt content and call this one method
- `images` is `[Data]` of PNG/JPEG bytes; the actor handles base64 encoding
  before sending. This keeps the encoding boundary inside the controller
- The actor serializes its own lifecycle transitions (spawn / kill / restart)
  but does not serialize concurrent inference requests — the server supports
  continuous batching internally

### Changed: `MLXSummarizer`

- Drop `Process` / `Pipe` machinery, `parseOutput()` separator logic, and the
  per-call `validateSanityCheck()` startup memory probe (the controller owns
  startup decisions now)
- Build a `SummarizationRequest`-shaped prompt as today, but submit it as a
  single user-turn message via `MLXModelServer.chatCompletion`
- Existing error semantics preserved by mapping controller errors:
  `MLXSummarizerError.killedByMemoryPressure`,
  `MLXSummarizerError.processFailed`, `MLXSummarizerError.emptyOutput`

### Changed: `MLXChatRunner`

- Drop `Process` / `Pipe` and manual `[ユーザー] / [アシスタント]` prompt
  splicing — the server-side chat template handles role boundaries when given
  proper `messages`
- Pass conversation history as a `[MLXChatTurn]` array
- Image attachments (existing `ChatMessage.imagePath`) are read by the runner
  and handed to the controller as `Data`

### Unchanged: `MemoryPressureMonitor`

The monitor stays exactly as it is. The only behavioral change is **what gets
registered**: instead of registering a short-lived PID per call, the
controller registers the long-lived server PID once at spawn and unregisters
it on stop/kill. The `.critical` → SIGKILL pathway is identical to today.

### Unchanged: `SerializedSummarizer`

The wrapper that serializes summary execution stays in place. It serves a
different purpose (it prevents two summary jobs from clobbering each other's
prompts and output state), and we now also benefit from it as a request
back-pressure boundary.

## Lifecycle

```
[lazy spawn]
  First inference request → MLXModelServer spawns the server subprocess
  ↓
[ready wait]
  Poll GET /health (every 0.5 s, max 120 s) until loaded_model is non-null
  ↓
[normal]
  HTTP POST /v1/chat/completions per request
  Idle timer resets on each request
  ↓
[idle teardown]
  After 10 min idle → SIGTERM (then SIGKILL after 3 s if still alive)
  ↓
[memory critical]
  MemoryPressureMonitor sends SIGKILL directly to the registered PID
  ↓
[crash / kill]
  Next request detects dead server (URLSession connection refused) and
  triggers a fresh spawn
```

Spawn arguments (initial):

```
python3 -m mlx_vlm.server
  --model "<absolute model dir>"
  --host 127.0.0.1
  --port <ephemeral, see below>
  --log-level WARNING
  --max-tokens 1024
```

Port selection:

- Bind to an ephemeral port that the controller picks before spawn by opening
  and immediately closing a TCP socket on `127.0.0.1:0` and reading the
  assigned port. This avoids fixed-port collisions with other dev work.
- Loopback-only (`127.0.0.1`). Never `0.0.0.0`.

Process options:

- Set `Process.terminationHandler` so the actor learns about unexpected exits
- Capture stdout/stderr to a ring buffer (last ~64 KB) for diagnostics. Do
  **not** try to drain pipes in a synchronous wait — use a background reader
  task

## Failure modes and responses

| Scenario | Detection | Response |
|---|---|---|
| Server fails to start (model missing) | Readiness times out, log shows error | Throw `serverStartupFailed` with stderr tail |
| Subprocess dies mid-request | URLSession connection error | Mark server dead, surface error, next call restarts |
| Memory critical during request | `MemoryPressureMonitor` SIGKILLs | URLSession returns connection error, surface as `killedByMemoryPressure` |
| Port allocation race | bind() succeeds but server can't bind | Throw `serverStartupFailed` with port hint |
| Idle teardown timing race (request arrives mid-shutdown) | URLSession error mid-stop | Restart and retry once, then surface error |

## Test strategy

### Unit tests (no network)

- `MLXModelServerConfiguration` URL building / port allocation
- Prompt-to-`MLXChatTurn` mapping in summarizer (string equality)
- Idle timer behavior with an injected clock

### Integration tests (skipped by default in CI)

- One end-to-end "summarize one short transcript" test gated behind an env
  flag `XTRUST_LIVE_MLX=1`. Must verify that:
  - Two consecutive summary calls reuse the same PID
  - SIGKILL via `MemoryPressureMonitor` causes the next call to spawn a fresh
    PID
  - Idle timeout in test mode (set very short via configuration) terminates
    the process

### Manual verification

- Section in `docs/manual-verification.md` describing:
  - Open Diagnostics → "MLX Server" shows `Stopped`
  - Trigger a summary → status flips to `Starting` → `Running (PID, port)`
  - Trigger another summary within 10 minutes → still `Running` with same PID
  - Wait 11 minutes → status returns to `Stopped`
  - Force memory pressure (e.g. `stress-ng --vm 4 --vm-bytes 12G`) during
    inference → status shows `Killed (memory pressure)` and Mac stays alive

## Diagnostics additions

`DiagnosticsView` gains:

- "MLX Server" section showing: state (Stopped / Starting / Running / Killed),
  PID, port, model path, uptime, idle timeout remaining, last error tail
- A manual `Stop MLX Server` button for development

`AppDiagnostics` gets a new `mlxServerStatus` snapshot field, populated on
view appearance.

## Migration steps

1. Add `MLXModelServer` and `MLXModelClient` types in the app target
2. Refactor `MLXSummarizer` to consume the controller; preserve existing error
   enum so call sites need no change
3. Refactor `MLXChatRunner` similarly
4. Wire the controller through `AppRuntime`; inject it into both consumers
   and into `AppDiagnostics`
5. Delete `parseOutput()` separator logic from both consumers (the server
   returns clean JSON-encoded content)
6. Delete per-call subprocess startup probes (`validateSanityCheck`,
   `validatePromptSize` stays — that one is genuinely about the model's
   context limit, not host memory)
7. Update Diagnostics view
8. Update `docs/manual-verification.md`

## Out of scope (followups)

- Streaming responses to UI as tokens arrive
- Multiple concurrent server instances for A/B model comparison
- Cross-app server sharing (would require socket discovery and lock files)
- Vision input UI wiring (the controller will already accept images; the chat
  UI needs a file picker)
- Replacing `SerializedSummarizer` with a server-side queue (works today; no
  reason to change)
