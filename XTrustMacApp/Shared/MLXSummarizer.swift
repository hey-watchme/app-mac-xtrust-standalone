import AppCore
import Darwin
import Foundation

struct MLXSummarizerConfiguration: Sendable {
    let pythonExecutablePath: String
    let modelDirectory: String
    let maxTokens: Int
    let maxPromptCharacters: Int

    var modelReady: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: modelDirectory, isDirectory: &isDir) && isDir.boolValue
    }

    init(
        pythonExecutablePath: String,
        modelDirectory: String,
        maxTokens: Int = 512,
        maxPromptCharacters: Int = 18_000
    ) {
        self.pythonExecutablePath = pythonExecutablePath
        self.modelDirectory = modelDirectory
        self.maxTokens = maxTokens
        self.maxPromptCharacters = maxPromptCharacters
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
    let server: MLXModelServer

    var modelIdentifier: String { "gemma-4-e4b-it-4bit" }

    func summarize(request: SummarizationRequest) async throws -> String {
        guard configuration.modelReady else {
            throw MLXSummarizerError.modelMissing(expectedPath: configuration.modelDirectory)
        }

        let prompt = buildPrompt(for: request)
        try validatePromptSize(prompt)

        let turns = [MLXChatTurn(role: .user, text: prompt)]
        let maxTokens = request.scope == .meetingMinutes
            ? max(configuration.maxTokens, 1_024)
            : configuration.maxTokens

        do {
            return try await server.chatCompletion(
                messages: turns,
                maxTokens: maxTokens
            )
        } catch let error as MLXModelServerError {
            throw map(error)
        }
    }

    private func map(_ error: MLXModelServerError) -> MLXSummarizerError {
        switch error {
        case let .modelMissing(path):
            return .modelMissing(expectedPath: path)
        case .killedByMemoryPressure:
            return .killedByMemoryPressure
        case .emptyOutput:
            return .emptyOutput
        case let .requestFailed(status, body):
            return .processFailed(exitCode: Int32(status), stderr: body)
        case let .responseDecodeFailed(reason):
            return .processFailed(exitCode: -1, stderr: reason)
        case let .serverDied(tail):
            return .processFailed(exitCode: -1, stderr: tail)
        case let .readinessTimedOut(seconds, tail):
            return .processFailed(exitCode: -1, stderr: "readiness timed out after \(Int(seconds))s. \(tail)")
        case let .spawnFailed(reason):
            return .processFailed(exitCode: -1, stderr: "spawn failed: \(reason)")
        case .portAllocationFailed:
            return .processFailed(exitCode: -1, stderr: "port allocation failed")
        }
    }

    private func buildPrompt(for request: SummarizationRequest) -> String {
        let numbered = request.transcripts.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        let sourceLabel: String
        let taskInstruction: String
        let outputFormat: String

        switch request.scope {
        case .transcriptChunk:
            sourceLabel = "文字起こしチャンク"
            taskInstruction = """
            以下は長い会議の文字起こしの一部です。後で会議全体の議事録に統合するための部分要約を作成してください。会話の言い換えではなく、業務で再利用できる実務メモとして整理してください。
            """
            outputFormat = """
            **この区間の論点**:
            - 議論された話題を箇条書き
            **決定事項**:
            - この区間で決まったこと。なければ「なし」
            **未決事項**:
            - 保留・確認待ち・論点だけ出て未決の項目。なければ「なし」
            **アクション**:
            - 次のステップ、担当、期限。聞き取れない場合は「要確認」と書く
            """
        case .meetingMinutes:
            sourceLabel = "会議の文字起こし（または部分要約）"
            taskInstruction = """
            以下は会議の文字起こし（または部分要約）です。重複をまとめ、会議全体の流れと実務上の結論が分かる議事録を Markdown で作成してください。
            """
            outputFormat = """
            ## 会議サマリー
            会議全体の要旨を2〜3文で

            ## 決定事項
            - 会議全体として確定した事項

            ## 未決事項
            - 持ち越し、追加確認、判断保留

            ## アクションアイテム
            - 担当・期限付きで書けるものを優先。曖昧なら「要確認」
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

    private func validatePromptSize(_ prompt: String) throws {
        guard prompt.count <= configuration.maxPromptCharacters else {
            throw MLXSummarizerError.promptTooLarge(
                limit: configuration.maxPromptCharacters,
                actual: prompt.count
            )
        }
    }

    private func contextDescription(for profile: MeetingContextProfile) -> String {
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

    private func extractionPriorities(for profile: MeetingContextProfile) -> String {
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
}

enum MLXSummarizerError: LocalizedError {
    case modelMissing(expectedPath: String)
    case processFailed(exitCode: Int32, stderr: String)
    case emptyOutput
    case promptTooLarge(limit: Int, actual: Int)
    case killedByMemoryPressure

    var errorDescription: String? {
        switch self {
        case let .modelMissing(path):
            return "Gemma 4 MLX model missing. Place gemma4-mlx/ at: \(path)"
        case let .processFailed(exitCode, stderr):
            return "mlx_vlm.server request failed (code \(exitCode)). detail: \(stderr)"
        case .emptyOutput:
            return "mlx_vlm.server returned no output."
        case let .promptTooLarge(limit, actual):
            return "要約入力が大きすぎるため実行を中止しました。Prompt size: \(actual) chars. Limit: \(limit) chars."
        case .killedByMemoryPressure:
            return "システムのメモリ圧迫が critical に達したため、要約プロセスを停止しました。しばらくしてから再試行してください。"
        }
    }
}

struct SystemMemorySnapshot: Sendable {
    let availableBytes: UInt64

    static func capture() throws -> SystemMemorySnapshot {
        let host = mach_host_self()

        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else {
            throw NSError(domain: "SystemMemorySnapshot", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "host_page_size failed"
            ])
        }

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &vmStats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(host, HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw NSError(domain: "SystemMemorySnapshot", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "host_statistics64 failed: \(result)"
            ])
        }

        let availablePageCount =
            UInt64(vmStats.free_count) +
            UInt64(vmStats.inactive_count) +
            UInt64(vmStats.speculative_count)

        return SystemMemorySnapshot(
            availableBytes: availablePageCount * UInt64(pageSize)
        )
    }
}
