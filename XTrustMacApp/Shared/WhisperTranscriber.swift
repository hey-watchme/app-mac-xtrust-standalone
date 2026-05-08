import Foundation

struct TranscriptionArtifact: Sendable {
    let transcriptText: String
    let transcriptFilePath: String
    let durationSeconds: Double
}

struct WhisperTranscriberConfiguration: Sendable {
    let executablePath: String
    let modelName: String
    let language: String
    let modelDirectory: String

    var expectedModelFilePath: String {
        URL(fileURLWithPath: modelDirectory, isDirectory: true)
            .appending(path: "\(modelName).pt")
            .path(percentEncoded: false)
    }

    static func developmentDefault(modelsRootDirectory: String) -> WhisperTranscriberConfiguration {
        let preferredPath = "/Library/Frameworks/Python.framework/Versions/3.12/bin/whisper"
        let executablePath: String
        if FileManager.default.isExecutableFile(atPath: preferredPath) {
            executablePath = preferredPath
        } else {
            executablePath = "whisper"
        }

        return WhisperTranscriberConfiguration(
            executablePath: executablePath,
            modelName: "small",
            language: "ja",
            modelDirectory: URL(fileURLWithPath: modelsRootDirectory, isDirectory: true)
                .appending(path: "whisper", directoryHint: .isDirectory)
                .path(percentEncoded: false)
        )
    }
}

struct WhisperTranscriber: Sendable {
    let configuration: WhisperTranscriberConfiguration

    private static let preferredExecutableDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    func transcribe(audioFilePath: String, outputDirectory: String) async throws -> TranscriptionArtifact {
        let startedAt = Date()
        let audioURL = URL(fileURLWithPath: audioFilePath)
        let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        let transcriptURL = outputURL.appending(path: audioURL.deletingPathExtension().lastPathComponent + ".txt")
        let modelDirectoryURL = URL(fileURLWithPath: configuration.modelDirectory, isDirectory: true)

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: configuration.expectedModelFilePath) else {
            throw WhisperTranscriberError.modelMissing(
                expectedPath: configuration.expectedModelFilePath
            )
        }

        let processEnvironment = buildProcessEnvironment()
        guard containsExecutable(named: "ffmpeg", in: processEnvironment) else {
            throw WhisperTranscriberError.ffmpegMissing(
                searchedPath: processEnvironment["PATH"] ?? ""
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.executablePath)
        process.environment = processEnvironment
        process.arguments = [
            audioFilePath,
            "--model", configuration.modelName,
            "--model_dir", configuration.modelDirectory,
            "--device", "cpu",
            "--task", "transcribe",
            "--language", configuration.language,
            "--output_dir", outputDirectory,
            "--output_format", "txt",
            "--verbose", "False"
        ]

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        try process.run()
        let processOutput = try await waitForProcessToFinish(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        guard processOutput.status == 0 else {
            throw WhisperTranscriberError.processFailed(
                code: processOutput.status,
                message: processOutput.errorText ?? processOutput.outputText ?? "Unknown Whisper process error."
            )
        }

        let resolvedTranscriptURL = try await waitForTranscriptFile(
            expectedURL: transcriptURL,
            outputDirectoryURL: outputURL,
            processOutput: processOutput
        )
        let transcriptText = try String(contentsOf: resolvedTranscriptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let durationSeconds = Date().timeIntervalSince(startedAt)
        return TranscriptionArtifact(
            transcriptText: transcriptText,
            transcriptFilePath: resolvedTranscriptURL.path(percentEncoded: false),
            durationSeconds: durationSeconds
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

    private func containsExecutable(named executableName: String, in environment: [String: String]) -> Bool {
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
    ) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let outputText = String(data: stdoutData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let errorText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                continuation.resume(returning: ProcessOutput(
                    status: process.terminationStatus,
                    outputText: outputText,
                    errorText: errorText
                ))
            }
        }
    }

    private func waitForTranscriptFile(
        expectedURL: URL,
        outputDirectoryURL: URL,
        processOutput: ProcessOutput
    ) async throws -> URL {
        for attempt in 0..<60 {
            if FileManager.default.fileExists(atPath: expectedURL.path(percentEncoded: false)) {
                return expectedURL
            }

            if attempt < 59 {
                try await Task.sleep(for: .milliseconds(250))
            }
        }

        let availableTextFiles = try FileManager.default.contentsOfDirectory(
            at: outputDirectoryURL,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "txt" }
            .map(\.lastPathComponent)
            .sorted()

        throw WhisperTranscriberError.transcriptMissing(
            expectedPath: expectedURL.path(percentEncoded: false),
            outputDirectory: outputDirectoryURL.path(percentEncoded: false),
            availableFiles: availableTextFiles,
            processOutput: processOutput.outputText,
            processError: processOutput.errorText
        )
    }
}

enum WhisperTranscriberError: LocalizedError {
    case modelMissing(expectedPath: String)
    case ffmpegMissing(searchedPath: String)
    case processFailed(code: Int32, message: String)
    case transcriptMissing(
        expectedPath: String,
        outputDirectory: String,
        availableFiles: [String],
        processOutput: String?,
        processError: String?
    )

    var errorDescription: String? {
        switch self {
        case let .modelMissing(expectedPath):
            return "Whisper model is missing. Place `small.pt` at: \(expectedPath)"
        case let .ffmpegMissing(searchedPath):
            return "ffmpeg is required for Whisper audio loading, but it was not found in PATH. PATH: \(searchedPath)"
        case let .processFailed(code, message):
            return "Whisper failed (\(code)): \(message)"
        case let .transcriptMissing(expectedPath, outputDirectory, availableFiles, processOutput, processError):
            let fileList = availableFiles.isEmpty ? "(none)" : availableFiles.joined(separator: ", ")
            let stdoutSection = processOutput?.isEmpty == false ? " Stdout: \(processOutput!)." : ""
            let stderrSection = processError?.isEmpty == false ? " Stderr: \(processError!)." : ""
            return "Whisper finished but transcript file was not found. Expected: \(expectedPath). Output directory: \(outputDirectory). Available files: \(fileList).\(stdoutSection)\(stderrSection)"
        }
    }
}

private struct ProcessOutput {
    let status: Int32
    let outputText: String?
    let errorText: String?
}
