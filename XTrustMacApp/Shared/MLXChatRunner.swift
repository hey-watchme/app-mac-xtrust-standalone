import Darwin
import Foundation

// Chat runner backed by the same MLX/Gemma-4 model used for summarization.
// Conversation history is provided by the caller; each call includes full context.
struct MLXChatRunner: Sendable {
    let configuration: MLXSummarizerConfiguration

    func chat(messages: [ChatMessage]) async throws -> String {
        guard configuration.modelReady else {
            throw MLXChatError.modelMissing(expectedPath: configuration.modelDirectory)
        }

        let prompt = buildPrompt(messages: messages)
        let result = try await runProcess(prompt: prompt)

        if result.terminationReason == .uncaughtSignal && result.exitCode == SIGKILL {
            throw MLXChatError.killedByMemoryPressure
        }

        guard result.exitCode == 0 else {
            throw MLXChatError.processFailed(
                exitCode: result.exitCode,
                stderr: result.standardError ?? "(no stderr)"
            )
        }

        let raw = (result.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw MLXChatError.emptyOutput
        }

        return parseOutput(raw)
    }

    private func buildPrompt(messages: [ChatMessage]) -> String {
        var lines: [String] = [
            "あなたは親切で有能な日本語アシスタントです。ユーザーの質問や依頼に的確に回答してください。",
            ""
        ]
        for message in messages {
            switch message.role {
            case .user:
                lines.append("[ユーザー]: \(message.text)")
            case .assistant:
                lines.append("[アシスタント]: \(message.text)")
            }
            lines.append("")
        }
        lines.append("[アシスタント]:")
        return lines.joined(separator: "\n")
    }

    // Uses the same separator-based output parsing as MLXSummarizer.
    private func parseOutput(_ raw: String) -> String {
        let separatorPrefix = "=========="
        let modelTurnMarker = "<|turn>model"
        let lines = raw.components(separatedBy: "\n")

        var separatorIndices: [Int] = []
        for (i, line) in lines.enumerated() {
            if line.hasPrefix(separatorPrefix) { separatorIndices.append(i) }
        }

        if separatorIndices.count >= 2 {
            let blockLines = Array(lines[(separatorIndices[0] + 1)..<separatorIndices[1]])
            let block = blockLines.joined(separator: "\n")
            if let markerRange = block.range(of: modelTurnMarker, options: .backwards) {
                let afterMarker = String(block[markerRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterMarker.isEmpty { return afterMarker }
            }
            return blockLines
                .filter { !$0.hasPrefix("Files:") && !$0.hasPrefix("Prompt:") }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let filtered = lines.filter { line in
            guard !line.hasPrefix(separatorPrefix) else { return false }
            let prefixes = ["Prompt:", "Generation:", "Peak memory:", "Fetching", "Files:"]
            return !prefixes.contains(where: { line.hasPrefix($0) })
        }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let preferredExecutableDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    private func runProcess(prompt: String) async throws -> ChatProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.pythonExecutablePath)
        process.arguments = [
            "-m", "mlx_vlm", "generate",
            "--model", configuration.modelDirectory,
            "--prompt", prompt,
            "--max-tokens", "1024",
        ]
        process.environment = buildProcessEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ChatProcessResult(
                    exitCode: process.terminationStatus,
                    terminationReason: process.terminationReason,
                    standardOutput: String(data: stdoutData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    standardError: String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
    }

    private func buildProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let currentPathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let pythonDirectory = URL(fileURLWithPath: configuration.pythonExecutablePath)
            .deletingLastPathComponent()
            .path(percentEncoded: false)

        var mergedEntries: [String] = []
        for entry in currentPathEntries + [pythonDirectory] + Self.preferredExecutableDirectories {
            guard !entry.isEmpty, !mergedEntries.contains(entry) else { continue }
            mergedEntries.append(entry)
        }

        environment["PATH"] = mergedEntries.joined(separator: ":")
        return environment
    }
}

private struct ChatProcessResult: Sendable {
    let exitCode: Int32
    let terminationReason: Process.TerminationReason
    let standardOutput: String?
    let standardError: String?
}

enum MLXChatError: LocalizedError {
    case modelMissing(expectedPath: String)
    case processFailed(exitCode: Int32, stderr: String)
    case emptyOutput
    case killedByMemoryPressure

    var errorDescription: String? {
        switch self {
        case let .modelMissing(path):
            return "Gemma 4 MLX model missing at: \(path)"
        case let .processFailed(exitCode, stderr):
            return "mlx_vlm.generate exited with code \(exitCode). stderr: \(stderr)"
        case .emptyOutput:
            return "mlx_vlm.generate produced no output."
        case .killedByMemoryPressure:
            return "システムのメモリ圧迫が critical に達したため、チャット応答を停止しました。"
        }
    }
}
