import AppCore
import Foundation

struct MLXSummarizerConfiguration: Sendable {
    let pythonExecutablePath: String
    let modelDirectory: String
    let maxTokens: Int

    var modelReady: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: modelDirectory, isDirectory: &isDir) && isDir.boolValue
    }

    init(pythonExecutablePath: String, modelDirectory: String, maxTokens: Int = 512) {
        self.pythonExecutablePath = pythonExecutablePath
        self.modelDirectory = modelDirectory
        self.maxTokens = maxTokens
    }

    static func developmentDefault(modelsRootDirectory: String) -> MLXSummarizerConfiguration {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let pyenvVersionsBase = "\(home)/.pyenv/versions"

        var candidates: [String] = []
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: pyenvVersionsBase) {
            candidates = versions.sorted().reversed().map {
                "\(pyenvVersionsBase)/\($0)/bin/python3"
            }
        }

        let allCandidates = candidates + [
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3",
        ]

        let pythonPath = allCandidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "python3"

        let modelDirectory = URL(fileURLWithPath: modelsRootDirectory, isDirectory: true)
            .appending(path: "gemma4-mlx", directoryHint: .isDirectory)
            .path(percentEncoded: false)

        return MLXSummarizerConfiguration(
            pythonExecutablePath: pythonPath,
            modelDirectory: modelDirectory
        )
    }
}

struct MLXSummarizer: Summarizer, Sendable {
    let configuration: MLXSummarizerConfiguration

    var modelIdentifier: String { "gemma-4-e4b-it-4bit" }

    private static let preferredExecutableDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    func summarize(transcripts: [String]) async throws -> String {
        guard configuration.modelReady else {
            throw MLXSummarizerError.modelMissing(expectedPath: configuration.modelDirectory)
        }

        let prompt = buildPrompt(transcripts: transcripts)
        let result = try await runProcess(prompt: prompt)

        guard result.exitCode == 0 else {
            throw MLXSummarizerError.processFailed(
                exitCode: result.exitCode,
                stderr: result.standardError ?? "(no stderr)"
            )
        }

        let raw = (result.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw MLXSummarizerError.emptyOutput
        }

        return parseOutput(raw)
    }

    private func buildPrompt(transcripts: [String]) -> String {
        let numbered = transcripts.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        return """
        以下の会議の発話記録を日本語で簡潔に要約してください。

        ## 発話記録
        \(numbered)

        ## 出力形式（以下の構造で回答してください）
        **テーマ**: このトピックの主な議題を1文で
        **要点**:
        - 重要なポイントを箇条書きで3〜5点
        **アクション**: 決定事項や次のステップ（なければ「なし」）

        要約のみ出力し、前置きや説明は不要です。
        """
    }

    // mlx_vlm generate output format:
    // ==========
    // Files: []
    //
    // Prompt: <bos><|turn>user\n...<turn|>\n<|turn>model\n\n<generated text>
    // ==========
    // Prompt: X tokens, ...
    // Generation: X tokens, ...
    // Peak memory: X.XX GB
    //
    // Extract the generated text by finding the last <|turn>model marker and taking
    // everything after it up to the closing separator.
    private func parseOutput(_ raw: String) -> String {
        let separatorPrefix = "=========="
        let modelTurnMarker = "<|turn>model"
        let lines = raw.components(separatedBy: "\n")

        var separatorIndices: [Int] = []
        for (i, line) in lines.enumerated() {
            if line.hasPrefix(separatorPrefix) {
                separatorIndices.append(i)
            }
        }

        if separatorIndices.count >= 2 {
            let blockLines = Array(lines[(separatorIndices[0] + 1)..<separatorIndices[1]])
            let block = blockLines.joined(separator: "\n")
            if let markerRange = block.range(of: modelTurnMarker, options: .backwards) {
                let afterMarker = String(block[markerRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterMarker.isEmpty {
                    return afterMarker
                }
            }
            // No model turn marker found — return the whole block stripped of noise
            return blockLines
                .filter { !$0.hasPrefix("Files:") && !$0.hasPrefix("Prompt:") }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // No separators — strip known stats lines as fallback
        let filtered = lines.filter { line in
            guard !line.hasPrefix(separatorPrefix) else { return false }
            let prefixes = ["Prompt:", "Generation:", "Peak memory:", "Fetching", "Files:"]
            return !prefixes.contains(where: { line.hasPrefix($0) })
        }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runProcess(prompt: String) async throws -> SummaryProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.pythonExecutablePath)
        process.arguments = [
            "-m", "mlx_vlm", "generate",
            "--model", configuration.modelDirectory,
            "--prompt", prompt,
            "--max-tokens", String(configuration.maxTokens),
        ]
        process.environment = buildProcessEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: SummaryProcessResult(
                    exitCode: process.terminationStatus,
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

private struct SummaryProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: String?
    let standardError: String?
}

enum MLXSummarizerError: LocalizedError {
    case modelMissing(expectedPath: String)
    case processFailed(exitCode: Int32, stderr: String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case let .modelMissing(path):
            return "Gemma 4 MLX model missing. Place gemma4-mlx/ at: \(path)"
        case let .processFailed(exitCode, stderr):
            return "mlx_lm.generate exited with code \(exitCode). stderr: \(stderr)"
        case .emptyOutput:
            return "mlx_lm.generate produced no output."
        }
    }
}
