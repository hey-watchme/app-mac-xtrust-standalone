import AppCore
import Foundation

struct LiteRTLMSummarizerConfiguration: Sendable {
    let executablePath: String
    let modelPath: String
    let backend: String

    var modelReady: Bool {
        FileManager.default.fileExists(atPath: modelPath)
    }

    init(executablePath: String, modelPath: String, backend: String = "gpu") {
        self.executablePath = executablePath
        self.modelPath = modelPath
        self.backend = backend
    }

    static func developmentDefault(modelsRootDirectory: String) -> LiteRTLMSummarizerConfiguration {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let pyenvBin = "\(home)/.pyenv/shims/litert-lm"
        let pyenvVersionsBase = "\(home)/.pyenv/versions"
        var pyenvVersionCandidates: [String] = []
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: pyenvVersionsBase) {
            pyenvVersionCandidates = versions.sorted().reversed().map {
                "\(pyenvVersionsBase)/\($0)/bin/litert-lm"
            }
        }
        let candidatePaths = [
            pyenvBin,
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/litert-lm",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/litert-lm",
            "/opt/homebrew/bin/litert-lm",
            "/usr/local/bin/litert-lm",
        ] + pyenvVersionCandidates

        let executablePath = candidatePaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "litert-lm"

        let modelPath = URL(fileURLWithPath: modelsRootDirectory, isDirectory: true)
            .appending(path: "gemma4", directoryHint: .isDirectory)
            .appending(path: "gemma-4-E4B-it.litertlm")
            .path(percentEncoded: false)

        return LiteRTLMSummarizerConfiguration(
            executablePath: executablePath,
            modelPath: modelPath,
            backend: "gpu"
        )
    }
}

struct LiteRTLMSummarizer: Summarizer, Sendable {
    let configuration: LiteRTLMSummarizerConfiguration

    var modelIdentifier: String { "gemma-4-E4B-it" }

    private static let preferredExecutableDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    func summarize(transcripts: [String]) async throws -> String {
        guard FileManager.default.fileExists(atPath: configuration.modelPath) else {
            throw LiteRTLMSummarizerError.modelMissing(expectedPath: configuration.modelPath)
        }

        let prompt = buildPrompt(transcripts: transcripts)
        let result = try await runProcess(prompt: prompt)

        guard result.exitCode == 0 else {
            throw LiteRTLMSummarizerError.processFailed(
                exitCode: result.exitCode,
                stderr: result.standardError ?? "(no stderr)"
            )
        }

        let output = (result.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw LiteRTLMSummarizerError.emptyOutput
        }

        return output
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

    private func runProcess(prompt: String) async throws -> SummaryProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.executablePath)
        process.arguments = [
            "run",
            configuration.modelPath,
            "--prompt", prompt,
            "--backend", configuration.backend,
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

        let executableDirectory = URL(fileURLWithPath: configuration.executablePath)
            .deletingLastPathComponent()
            .path(percentEncoded: false)

        var mergedEntries: [String] = []
        for entry in currentPathEntries + [executableDirectory] + Self.preferredExecutableDirectories {
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

enum LiteRTLMSummarizerError: LocalizedError {
    case modelMissing(expectedPath: String)
    case processFailed(exitCode: Int32, stderr: String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case let .modelMissing(path):
            return "Gemma 4 model missing. Place gemma-4-E4B-it.litertlm at: \(path)"
        case let .processFailed(exitCode, stderr):
            return "litert-lm exited with code \(exitCode). stderr: \(stderr)"
        case .emptyOutput:
            return "litert-lm produced no output."
        }
    }
}
