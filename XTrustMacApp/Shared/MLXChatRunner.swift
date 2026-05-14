import Foundation

struct MLXChatRunner: Sendable {
    let configuration: MLXSummarizerConfiguration
    let server: MLXModelServer

    func chat(messages: [ChatMessage]) async throws -> String {
        guard configuration.modelReady else {
            throw MLXChatError.modelMissing(expectedPath: configuration.modelDirectory)
        }

        let systemTurn = MLXChatTurn(
            role: .system,
            text: "あなたは親切で有能な日本語アシスタントです。ユーザーの質問や依頼に的確に回答してください。"
        )
        var turns: [MLXChatTurn] = [systemTurn]
        for message in messages {
            turns.append(try toTurn(message))
        }

        do {
            return try await server.chatCompletion(
                messages: turns,
                maxTokens: 1024
            )
        } catch let error as MLXModelServerError {
            throw map(error)
        }
    }

    private func toTurn(_ message: ChatMessage) throws -> MLXChatTurn {
        switch message.role {
        case .user:
            var text = ""
            if let content = message.attachedTextContent, let fileName = message.attachedFileName {
                text = "添付ファイル「\(fileName)」の内容:\n```\n\(content)\n```\n\n\(message.text)"
            } else {
                text = message.text
            }
            var images: [Data] = []
            if let path = message.imagePath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                images.append(data)
            }
            return MLXChatTurn(role: .user, text: text, imageData: images)
        case .assistant:
            return MLXChatTurn(role: .assistant, text: message.text)
        }
    }

    private func map(_ error: MLXModelServerError) -> MLXChatError {
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
            return "mlx_vlm.server request failed (code \(exitCode)). detail: \(stderr)"
        case .emptyOutput:
            return "mlx_vlm.server returned no output."
        case .killedByMemoryPressure:
            return "システムのメモリ圧迫が critical に達したため、チャット応答を停止しました。"
        }
    }
}
