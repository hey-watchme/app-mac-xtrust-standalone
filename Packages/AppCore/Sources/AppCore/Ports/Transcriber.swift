import Foundation

public struct TranscriptionInvocation: Equatable, Sendable {
    public let command: String
    public let arguments: [String]

    public init(command: String, arguments: [String]) {
        self.command = command
        self.arguments = arguments
    }
}

public struct TranscriptionProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String?
    public let standardError: String?

    public init(
        exitCode: Int32,
        standardOutput: String?,
        standardError: String?
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol Transcriber: Sendable {
    var modelIdentifier: String { get }
    var language: String { get }

    func makeInvocation(
        audioFilePath: String,
        outputDirectory: String
    ) -> TranscriptionInvocation

    func run(invocation: TranscriptionInvocation) async throws -> TranscriptionProcessResult
}
