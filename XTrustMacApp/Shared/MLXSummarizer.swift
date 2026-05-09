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

    func summarize(request: SummarizationRequest) async throws -> String {
        guard configuration.modelReady else {
            throw MLXSummarizerError.modelMissing(expectedPath: configuration.modelDirectory)
        }

        let prompt = buildPrompt(for: request)
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

    private func buildPrompt(for request: SummarizationRequest) -> String {
        let numbered = request.transcripts.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        let sourceLabel: String
        let taskInstruction: String
        let outputFormat: String

        switch request.scope {
        case .topic:
            sourceLabel = "発話記録"
            taskInstruction = """
            以下は会議中の1トピックに属する発話記録です。会話の言い換えではなく、業務で再利用できる実務メモとして整理してください。
            """
            outputFormat = """
            **トピック**: この話題が何についての議論かを1文で
            **決定事項**:
            - 決まったことを箇条書き
            **未決事項**:
            - 保留・確認待ち・論点だけ出て未決の項目
            **アクション**:
            - 次のステップ、担当、期限。聞き取れない場合は「要確認」と書く
            **リスク・懸念**:
            - ブロッカー、依存関係、懸念点。なければ「なし」
            """
        case .meeting:
            sourceLabel = "トピック要約"
            taskInstruction = """
            以下は会議内の各トピック要約です。重複をまとめ、会議全体の流れと実務上の結論が分かる wrap-up を作ってください。
            """
            outputFormat = """
            **会議サマリー**: 会議全体の要旨を2〜3文で
            **決定事項**:
            - 会議全体として確定した事項
            **未決事項**:
            - 持ち越し、追加確認、判断保留
            **アクション**:
            - 担当・期限付きで書けるものを優先。曖昧なら「要確認」
            **フォローアップ観点**:
            - 次回までに見落とすと危ない点や確認したい論点
            """
        }

        return """
        あなたは日本語の業務会議メモ作成アシスタントです。

        以下のルールを守ってください。
        - 事実ベースで要約する
        - 発言に根拠がない推測は書かない
        - 決定事項と未決事項を分ける
        - 担当者名や期限が不明な場合は断定せず「要確認」と書く
        - 冗長な前置きや感想は書かない
        - 日本語の社内メモとしてそのまま読める形にする

        会議コンテキスト:
        \(contextDescription(for: request.contextProfile))

        優先して抽出する観点:
        \(extractionPriorities(for: request.contextProfile))

        \(taskInstruction)

        ## 入力 (\(sourceLabel))
        \(numbered)

        ## 出力形式
        \(outputFormat)
        """
    }

    private func contextDescription(for profile: Session.MeetingContextProfile) -> String {
        switch profile {
        case .general:
            return "一般的な仕事の会議。論点整理、決定事項、未決事項、次のアクションを重視する。"
        case .engineering:
            return "ソフトウェア開発や技術議論。仕様、実装方針、技術的制約、依存関係、リスクを重視する。"
        case .product:
            return "商品企画・プロダクト設計・事業検討。ユーザー課題、仮説、優先順位、意思決定理由を重視する。"
        case .recruitingHR:
            return "採用・人事・組織運営に関する会話。観察事実、確認事項、次対応、配慮が必要な論点を重視する。"
        }
    }

    private func extractionPriorities(for profile: Session.MeetingContextProfile) -> String {
        switch profile {
        case .general:
            return """
            - 何が決まり、何が未決か
            - 次に誰が何をするか
            - リスクや確認待ち事項
            """
        case .engineering:
            return """
            - 仕様変更、実装方針、設計判断
            - バグ、技術的制約、依存関係、リスク
            - 担当、優先度、リリースや対応時期
            """
        case .product:
            return """
            - 対象ユーザー、課題、価値仮説
            - 企画案の比較、判断理由、優先順位
            - 次の検証、意思決定者、保留論点
            """
        case .recruitingHR:
            return """
            - 観察できた事実と確認事項
            - 候補者対応、人員計画、組織運営上の次対応
            - センシティブな内容は断定を避け、要確認を明示
            """
        }
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
