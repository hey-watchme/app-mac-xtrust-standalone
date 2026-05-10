import Dispatch
import Foundation

public struct WhisperCLITranscriberConfiguration: Sendable {
    public let executablePath: String
    public let modelName: String
    public let language: String
    public let modelDirectory: String
    public let temperature: Double
    public let noSpeechThreshold: Double
    public let logprobThreshold: Double
    public let compressionRatioThreshold: Double
    public let conditionOnPreviousText: Bool

    public var expectedModelFilePath: String {
        URL(fileURLWithPath: modelDirectory, isDirectory: true)
            .appending(path: "\(modelName).pt")
            .path(percentEncoded: false)
    }

    public init(
        executablePath: String,
        modelName: String,
        language: String,
        modelDirectory: String,
        temperature: Double = 0,
        noSpeechThreshold: Double = 0.6,
        logprobThreshold: Double = -1.0,
        compressionRatioThreshold: Double = 2.4,
        conditionOnPreviousText: Bool = false
    ) {
        self.executablePath = executablePath
        self.modelName = modelName
        self.language = language
        self.modelDirectory = modelDirectory
        self.temperature = temperature
        self.noSpeechThreshold = noSpeechThreshold
        self.logprobThreshold = logprobThreshold
        self.compressionRatioThreshold = compressionRatioThreshold
        self.conditionOnPreviousText = conditionOnPreviousText
    }

    public static func developmentDefault(modelsRootDirectory: String) -> WhisperCLITranscriberConfiguration {
        let preferredPath = "/Library/Frameworks/Python.framework/Versions/3.12/bin/whisper"
        let executablePath: String
        if FileManager.default.isExecutableFile(atPath: preferredPath) {
            executablePath = preferredPath
        } else {
            executablePath = "whisper"
        }

        return WhisperCLITranscriberConfiguration(
            executablePath: executablePath,
            modelName: "small",
            language: "ja",
            modelDirectory: URL(fileURLWithPath: modelsRootDirectory, isDirectory: true)
                .appending(path: "whisper", directoryHint: .isDirectory)
                .path(percentEncoded: false),
            temperature: 0,
            noSpeechThreshold: 0.6,
            logprobThreshold: -1.0,
            compressionRatioThreshold: 2.4,
            conditionOnPreviousText: false
        )
    }
}

public struct WhisperCLITranscriber: Transcriber, Sendable {
    public let configuration: WhisperCLITranscriberConfiguration

    private static let preferredExecutableDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    public var modelIdentifier: String {
        configuration.modelName
    }

    public var language: String {
        configuration.language
    }

    public init(configuration: WhisperCLITranscriberConfiguration) {
        self.configuration = configuration
    }

    public func makeInvocation(
        audioFilePath: String,
        outputDirectory: String
    ) -> TranscriptionInvocation {
        TranscriptionInvocation(
            command: configuration.executablePath,
            arguments: [
                audioFilePath,
                "--model", configuration.modelName,
                "--model_dir", configuration.modelDirectory,
                "--device", "cpu",
                "--task", "transcribe",
                "--language", configuration.language,
                "--temperature", String(configuration.temperature),
                "--no_speech_threshold", String(configuration.noSpeechThreshold),
                "--logprob_threshold", String(configuration.logprobThreshold),
                "--compression_ratio_threshold", String(configuration.compressionRatioThreshold),
                "--condition_on_previous_text", configuration.conditionOnPreviousText ? "True" : "False",
                "--output_dir", outputDirectory,
                "--output_format", "txt",
                "--verbose", "False"
            ]
        )
    }

    public func run(invocation: TranscriptionInvocation) async throws -> TranscriptionProcessResult {
        guard FileManager.default.fileExists(atPath: configuration.expectedModelFilePath) else {
            throw WhisperCLITranscriberError.modelMissing(
                expectedPath: configuration.expectedModelFilePath
            )
        }

        let processEnvironment = buildProcessEnvironment()
        guard containsExecutable(named: "ffmpeg", in: processEnvironment) else {
            throw WhisperCLITranscriberError.ffmpegMissing(
                searchedPath: processEnvironment["PATH"] ?? ""
            )
        }

        let modelDirectoryURL = URL(fileURLWithPath: configuration.modelDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.command)
        process.arguments = invocation.arguments
        process.environment = processEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        return try await waitForProcessToFinish(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )
    }

    private func buildProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let currentPathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let whisperDirectory = URL(fileURLWithPath: configuration.executablePath)
            .deletingLastPathComponent()
            .path(percentEncoded: false)

        var mergedEntries: [String] = []
        for entry in currentPathEntries + [whisperDirectory] + Self.preferredExecutableDirectories {
            guard !entry.isEmpty, !mergedEntries.contains(entry) else { continue }
            mergedEntries.append(entry)
        }

        environment["PATH"] = mergedEntries.joined(separator: ":")
        return environment
    }

    private func containsExecutable(
        named executableName: String,
        in environment: [String: String]
    ) -> Bool {
        let fileManager = FileManager.default
        let directories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for directory in directories {
            let candidatePath = URL(fileURLWithPath: directory, isDirectory: true)
                .appending(path: executableName)
                .path(percentEncoded: false)
            if fileManager.isExecutableFile(atPath: candidatePath) {
                return true
            }
        }

        return false
    }

    private func waitForProcessToFinish(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) async throws -> TranscriptionProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let standardOutput = String(data: stdoutData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let standardError = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                continuation.resume(returning: TranscriptionProcessResult(
                    exitCode: process.terminationStatus,
                    standardOutput: standardOutput,
                    standardError: standardError
                ))
            }
        }
    }
}

public enum WhisperCLITranscriberError: LocalizedError {
    case modelMissing(expectedPath: String)
    case ffmpegMissing(searchedPath: String)

    public var errorDescription: String? {
        switch self {
        case let .modelMissing(expectedPath):
            return "Whisper model is missing. Place `small.pt` at: \(expectedPath)"
        case let .ffmpegMissing(searchedPath):
            return "ffmpeg is required for Whisper audio loading, but it was not found in PATH. PATH: \(searchedPath)"
        }
    }
}
