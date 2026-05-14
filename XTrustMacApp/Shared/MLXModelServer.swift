import AppCore
import Darwin
import Foundation

// MARK: - Shutdown registry

// Tracks live mlx_vlm.server PIDs spawned by the app so AppDelegate can
// synchronously terminate them on app exit. Memory-pressure kills still go
// through MemoryPressureMonitor; this registry is purely for clean shutdown.
enum MLXModelServerProcessRegistry {
    nonisolated(unsafe) private static var activePIDs: Set<pid_t> = []
    private static let lock = NSLock()

    static func register(pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        activePIDs.insert(pid)
    }

    static func unregister(pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        activePIDs.remove(pid)
    }

    static func terminateAll() {
        lock.lock()
        let snapshot = activePIDs
        activePIDs.removeAll()
        lock.unlock()

        for pid in snapshot {
            Darwin.kill(pid, SIGTERM)
        }
        Thread.sleep(forTimeInterval: 0.3)
        for pid in snapshot where Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
        }
    }
}

// MARK: - Configuration

struct MLXModelServerConfiguration: Sendable {
    let pythonExecutablePath: String
    let modelDirectory: String
    let host: String
    let readinessTimeout: TimeInterval
    let idleTimeout: TimeInterval
    let requestTimeout: TimeInterval

    init(
        pythonExecutablePath: String,
        modelDirectory: String,
        host: String = "127.0.0.1",
        readinessTimeout: TimeInterval = 120,
        idleTimeout: TimeInterval = 600,
        requestTimeout: TimeInterval = 300
    ) {
        self.pythonExecutablePath = pythonExecutablePath
        self.modelDirectory = modelDirectory
        self.host = host
        self.readinessTimeout = readinessTimeout
        self.idleTimeout = idleTimeout
        self.requestTimeout = requestTimeout
    }

    var modelReady: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: modelDirectory, isDirectory: &isDir) && isDir.boolValue
    }
}

// MARK: - Public message type

struct MLXChatTurn: Sendable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let text: String
    let imageData: [Data]

    init(role: Role, text: String, imageData: [Data] = []) {
        self.role = role
        self.text = text
        self.imageData = imageData
    }
}

// MARK: - Status snapshot

struct MLXModelServerStatus: Sendable {
    enum State: Sendable, Equatable {
        case stopped
        case starting
        case running
        case killed
        case failed
    }

    let state: State
    let modelDirectory: String
    let pid: pid_t?
    let port: Int?
    let startedAt: Date?
    let lastRequestAt: Date?
    let lastErrorMessage: String?
    let idleTimeout: TimeInterval
}

// MARK: - Errors

enum MLXModelServerError: LocalizedError {
    case modelMissing(expectedPath: String)
    case portAllocationFailed
    case spawnFailed(reason: String)
    case readinessTimedOut(seconds: TimeInterval, stderrTail: String)
    case requestFailed(status: Int, body: String)
    case responseDecodeFailed(reason: String)
    case emptyOutput
    case serverDied(stderrTail: String)
    case killedByMemoryPressure

    var errorDescription: String? {
        switch self {
        case let .modelMissing(path):
            return "Gemma 4 MLX model directory not found at: \(path)"
        case .portAllocationFailed:
            return "Could not allocate an ephemeral local port for the MLX server."
        case let .spawnFailed(reason):
            return "Failed to spawn mlx_vlm.server subprocess: \(reason)"
        case let .readinessTimedOut(seconds, tail):
            return "mlx_vlm.server did not become ready within \(Int(seconds))s. stderr tail: \(tail)"
        case let .requestFailed(status, body):
            return "mlx_vlm.server returned HTTP \(status). body: \(body)"
        case let .responseDecodeFailed(reason):
            return "Failed to decode mlx_vlm.server response: \(reason)"
        case .emptyOutput:
            return "mlx_vlm.server returned an empty completion."
        case let .serverDied(tail):
            return "mlx_vlm.server exited unexpectedly. stderr tail: \(tail)"
        case .killedByMemoryPressure:
            return "システムのメモリ圧迫が critical に達したため、ローカル LLM を停止しました。"
        }
    }
}

// MARK: - Actor

actor MLXModelServer {
    private struct RuntimeState {
        var process: Process
        var pid: pid_t
        var port: Int
        var startedAt: Date
        var stderrTail: RingBuffer
        var stdoutTail: RingBuffer
    }

    private enum Lifecycle {
        case stopped
        case starting
        case running(RuntimeState)
        case killed(reason: String, at: Date)
        case failed(error: String, at: Date)
    }

    let configuration: MLXModelServerConfiguration
    private let pressureMonitor: MemoryPressureMonitor
    private let urlSession: URLSession

    private var lifecycle: Lifecycle = .stopped
    private var lastRequestAt: Date?
    private var idleTimerTask: Task<Void, Never>?
    private var pendingStart: Task<RuntimeState, Error>?

    init(
        configuration: MLXModelServerConfiguration,
        pressureMonitor: MemoryPressureMonitor
    ) {
        self.configuration = configuration
        self.pressureMonitor = pressureMonitor
        let urlConfig = URLSessionConfiguration.ephemeral
        urlConfig.timeoutIntervalForRequest = configuration.requestTimeout
        urlConfig.timeoutIntervalForResource = configuration.requestTimeout + 30
        urlConfig.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: urlConfig)
    }

    // MARK: - Public API

    func chatCompletion(
        messages: [MLXChatTurn],
        maxTokens: Int
    ) async throws -> String {
        guard configuration.modelReady else {
            throw MLXModelServerError.modelMissing(expectedPath: configuration.modelDirectory)
        }

        let runtime = try await ensureRunning()
        let request = try buildHTTPRequest(
            runtime: runtime,
            messages: messages,
            maxTokens: maxTokens
        )

        lastRequestAt = Date()
        scheduleIdleTimerIfNeeded()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            try handleConnectionFailure(error: error)
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw MLXModelServerError.requestFailed(status: -1, body: "no http response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw MLXModelServerError.requestFailed(status: http.statusCode, body: body)
        }

        lastRequestAt = Date()
        return try decodeChatCompletion(data: data)
    }

    func stop() async {
        idleTimerTask?.cancel()
        idleTimerTask = nil
        if case let .running(state) = lifecycle {
            pressureMonitor.unregister(pid: state.pid)
            MLXModelServerProcessRegistry.unregister(pid: state.pid)
            terminate(process: state.process, pid: state.pid)
        }
        lifecycle = .stopped
        pendingStart = nil
    }

    func status() -> MLXModelServerStatus {
        switch lifecycle {
        case .stopped:
            return MLXModelServerStatus(
                state: .stopped,
                modelDirectory: configuration.modelDirectory,
                pid: nil,
                port: nil,
                startedAt: nil,
                lastRequestAt: lastRequestAt,
                lastErrorMessage: nil,
                idleTimeout: configuration.idleTimeout
            )
        case .starting:
            return MLXModelServerStatus(
                state: .starting,
                modelDirectory: configuration.modelDirectory,
                pid: nil,
                port: nil,
                startedAt: nil,
                lastRequestAt: lastRequestAt,
                lastErrorMessage: nil,
                idleTimeout: configuration.idleTimeout
            )
        case let .running(state):
            return MLXModelServerStatus(
                state: .running,
                modelDirectory: configuration.modelDirectory,
                pid: state.pid,
                port: state.port,
                startedAt: state.startedAt,
                lastRequestAt: lastRequestAt,
                lastErrorMessage: nil,
                idleTimeout: configuration.idleTimeout
            )
        case let .killed(reason, _):
            return MLXModelServerStatus(
                state: .killed,
                modelDirectory: configuration.modelDirectory,
                pid: nil,
                port: nil,
                startedAt: nil,
                lastRequestAt: lastRequestAt,
                lastErrorMessage: reason,
                idleTimeout: configuration.idleTimeout
            )
        case let .failed(error, _):
            return MLXModelServerStatus(
                state: .failed,
                modelDirectory: configuration.modelDirectory,
                pid: nil,
                port: nil,
                startedAt: nil,
                lastRequestAt: lastRequestAt,
                lastErrorMessage: error,
                idleTimeout: configuration.idleTimeout
            )
        }
    }

    // MARK: - Lifecycle

    private func ensureRunning() async throws -> RuntimeState {
        if case let .running(state) = lifecycle {
            if isProcessAlive(pid: state.pid) {
                return state
            }
            lifecycle = .killed(reason: "Process exited unexpectedly", at: Date())
            pressureMonitor.unregister(pid: state.pid)
            MLXModelServerProcessRegistry.unregister(pid: state.pid)
        }

        if let pending = pendingStart {
            return try await pending.value
        }

        let task = Task<RuntimeState, Error> { [self] in
            try await self.performStart()
        }
        pendingStart = task
        do {
            let state = try await task.value
            pendingStart = nil
            return state
        } catch {
            pendingStart = nil
            throw error
        }
    }

    private func performStart() async throws -> RuntimeState {
        lifecycle = .starting

        let port = try Self.allocateEphemeralPort()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.pythonExecutablePath)
        process.arguments = [
            "-m", "mlx_vlm.server",
            "--model", configuration.modelDirectory,
            "--host", configuration.host,
            "--port", String(port),
            "--log-level", "WARNING",
        ]
        process.environment = buildProcessEnvironment()

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        let stderrTail = RingBuffer(capacity: 4096)
        let stdoutTail = RingBuffer(capacity: 4096)

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrTail.append(data)
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutTail.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            lifecycle = .failed(error: error.localizedDescription, at: Date())
            throw MLXModelServerError.spawnFailed(reason: error.localizedDescription)
        }

        let pid = process.processIdentifier
        pressureMonitor.register(pid: pid, label: "mlx_vlm.server")
        MLXModelServerProcessRegistry.register(pid: pid)

        let startedAt = Date()
        let runtime = RuntimeState(
            process: process,
            pid: pid,
            port: port,
            startedAt: startedAt,
            stderrTail: stderrTail,
            stdoutTail: stdoutTail
        )

        do {
            try await waitForReady(runtime: runtime)
        } catch {
            terminate(process: process, pid: pid)
            pressureMonitor.unregister(pid: pid)
            MLXModelServerProcessRegistry.unregister(pid: pid)
            let tail = stderrTail.snapshot()
            lifecycle = .failed(error: error.localizedDescription, at: Date())
            throw MLXModelServerError.readinessTimedOut(
                seconds: configuration.readinessTimeout,
                stderrTail: tail
            )
        }

        lifecycle = .running(runtime)
        scheduleIdleTimerIfNeeded()
        return runtime
    }

    private func waitForReady(runtime: RuntimeState) async throws {
        let deadline = Date().addingTimeInterval(configuration.readinessTimeout)
        let healthURL = URL(string: "http://\(configuration.host):\(runtime.port)/health")!
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 5

        while Date() < deadline {
            if !isProcessAlive(pid: runtime.pid) {
                throw MLXModelServerError.serverDied(stderrTail: runtime.stderrTail.snapshot())
            }

            if let (data, response) = try? await urlSession.data(for: request),
               let http = response as? HTTPURLResponse,
               http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let loadedModel = json["loaded_model"] as? String,
               !loadedModel.isEmpty {
                return
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        throw MLXModelServerError.readinessTimedOut(
            seconds: configuration.readinessTimeout,
            stderrTail: runtime.stderrTail.snapshot()
        )
    }

    private func handleConnectionFailure(error: Error) throws {
        guard case let .running(state) = lifecycle else { return }
        let alive = isProcessAlive(pid: state.pid)
        if !alive {
            pressureMonitor.unregister(pid: state.pid)
            MLXModelServerProcessRegistry.unregister(pid: state.pid)
            let tail = state.stderrTail.snapshot()
            if process(state.process, wasKilledBy: SIGKILL) {
                lifecycle = .killed(reason: "SIGKILL (likely memory pressure)", at: Date())
                throw MLXModelServerError.killedByMemoryPressure
            }
            lifecycle = .failed(error: error.localizedDescription, at: Date())
            throw MLXModelServerError.serverDied(stderrTail: tail)
        }
    }

    // MARK: - Idle timer

    private func scheduleIdleTimerIfNeeded() {
        idleTimerTask?.cancel()
        idleTimerTask = Task { [weak self] in
            await self?.runIdleTimer()
        }
    }

    private func runIdleTimer() async {
        let pollInterval: TimeInterval = 30
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Task.isCancelled { return }
            idleTimerTick()
        }
    }

    private func idleTimerTick() {
        guard case .running = lifecycle else { return }
        guard let last = lastRequestAt else { return }
        if Date().timeIntervalSince(last) >= configuration.idleTimeout {
            if case let .running(state) = lifecycle {
                pressureMonitor.unregister(pid: state.pid)
                MLXModelServerProcessRegistry.unregister(pid: state.pid)
                terminate(process: state.process, pid: state.pid)
                lifecycle = .stopped
            }
            idleTimerTask?.cancel()
            idleTimerTask = nil
        }
    }

    // MARK: - Helpers

    private func buildHTTPRequest(
        runtime: RuntimeState,
        messages: [MLXChatTurn],
        maxTokens: Int
    ) throws -> URLRequest {
        let url = URL(string: "http://\(configuration.host):\(runtime.port)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": configuration.modelDirectory,
            "messages": messages.map(encodeMessage(_:)),
            "max_tokens": maxTokens,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        return request
    }

    private func encodeMessage(_ turn: MLXChatTurn) -> [String: Any] {
        if turn.imageData.isEmpty {
            return [
                "role": turn.role.rawValue,
                "content": turn.text,
            ]
        }

        var parts: [[String: Any]] = []
        for image in turn.imageData {
            let b64 = image.base64EncodedString()
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:image/png;base64,\(b64)"],
            ])
        }
        if !turn.text.isEmpty {
            parts.append(["type": "text", "text": turn.text])
        }
        return [
            "role": turn.role.rawValue,
            "content": parts,
        ]
    }

    private func decodeChatCompletion(data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MLXModelServerError.responseDecodeFailed(reason: "top-level JSON not an object")
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw MLXModelServerError.responseDecodeFailed(reason: "missing choices[0].message.content")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MLXModelServerError.emptyOutput
        }
        return trimmed
    }

    private func buildProcessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let pythonDir = URL(fileURLWithPath: configuration.pythonExecutablePath)
            .deletingLastPathComponent()
            .path(percentEncoded: false)
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        var entries = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for extra in [pythonDir] + extras {
            if !extra.isEmpty, !entries.contains(extra) {
                entries.append(extra)
            }
        }
        env["PATH"] = entries.joined(separator: ":")
        return env
    }

    private func isProcessAlive(pid: pid_t) -> Bool {
        Darwin.kill(pid, 0) == 0
    }

    private nonisolated func process(_ process: Process, wasKilledBy signal: Int32) -> Bool {
        guard !process.isRunning else { return false }
        return process.terminationReason == .uncaughtSignal && process.terminationStatus == signal
    }

    private nonisolated func terminate(process: Process, pid: pid_t) {
        guard process.isRunning else { return }
        Darwin.kill(pid, SIGTERM)
        let killDeadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < killDeadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            Darwin.kill(pid, SIGKILL)
        }
    }

    private static func allocateEphemeralPort() throws -> Int {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MLXModelServerError.portAllocationFailed }
        defer { Darwin.close(fd) }

        var enable: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &enable, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw MLXModelServerError.portAllocationFailed }

        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assigned) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.getsockname(fd, sockPtr, &len)
            }
        }
        guard nameResult == 0 else { throw MLXModelServerError.portAllocationFailed }

        let netPort = assigned.sin_port
        let hostPort = UInt16(bigEndian: netPort)
        return Int(hostPort)
    }
}

// MARK: - RingBuffer

private final class RingBuffer: @unchecked Sendable {
    private let capacity: Int
    private var bytes = Data()
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        bytes.append(data)
        if bytes.count > capacity {
            bytes.removeFirst(bytes.count - capacity)
        }
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: bytes, encoding: .utf8) ?? ""
    }
}
