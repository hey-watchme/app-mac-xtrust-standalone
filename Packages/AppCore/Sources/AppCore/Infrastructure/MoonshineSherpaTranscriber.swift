import Dispatch
import Foundation

public struct MoonshineSherpaTranscriberConfiguration: Sendable {
    public let pythonExecutablePath: String
    public let scriptPath: String
    public let modelDirectory: String
    public let language: String

    public var expectedEncoderPath: String {
        URL(fileURLWithPath: modelDirectory, isDirectory: true)
            .appending(path: "encoder_model.ort")
            .path(percentEncoded: false)
    }

    public init(
        pythonExecutablePath: String,
        scriptPath: String,
        modelDirectory: String,
        language: String = "ja"
    ) {
        self.pythonExecutablePath = pythonExecutablePath
        self.scriptPath = scriptPath
        self.modelDirectory = modelDirectory
        self.language = language
    }

    public static func developmentDefault(
        modelsRootDirectory: String
    ) -> MoonshineSherpaTranscriberConfiguration {
        let workspaceRoot = URL(fileURLWithPath: modelsRootDirectory, isDirectory: true)
            .deletingLastPathComponent()
        let scriptsDir = workspaceRoot.appending(path: "scripts", directoryHint: .isDirectory)
        let scriptPath = scriptsDir.appending(path: "moonshine_transcribe.py").path(percentEncoded: false)

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: scriptPath) {
            try? pythonScriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        }

        // Do NOT use pyenv shims — they hang in app subprocess environments
        // where PYENV_ROOT and shell init are not inherited.
        // Enumerate real versioned executables directly.
        let home = NSHomeDirectory()
        let pyenvVersionsRoot = "\(home)/.pyenv/versions"
        let pyenvVersioned: [String] = {
            let versions = (try? FileManager.default.contentsOfDirectory(atPath: pyenvVersionsRoot)) ?? []
            return versions.sorted(by: >).map { "\(pyenvVersionsRoot)/\($0)/bin/python3" }
        }()
        let pythonCandidates = pyenvVersioned + [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        let pythonPath = pythonCandidates.first { fileManager.isExecutableFile(atPath: $0) } ?? "python3"

        return MoonshineSherpaTranscriberConfiguration(
            pythonExecutablePath: pythonPath,
            scriptPath: scriptPath,
            modelDirectory: URL(fileURLWithPath: modelsRootDirectory, isDirectory: true)
                .appending(path: "moonshine-base-ja", directoryHint: .isDirectory)
                .path(percentEncoded: false),
            language: "ja"
        )
    }
}

public struct MoonshineSherpaTranscriber: Transcriber, Sendable {
    public let configuration: MoonshineSherpaTranscriberConfiguration

    public var modelIdentifier: String { "moonshine-base-ja" }
    public var language: String { configuration.language }

    public init(configuration: MoonshineSherpaTranscriberConfiguration) {
        self.configuration = configuration
    }

    public func makeInvocation(
        audioFilePath: String,
        outputDirectory: String
    ) -> TranscriptionInvocation {
        TranscriptionInvocation(
            command: configuration.pythonExecutablePath,
            arguments: [
                configuration.scriptPath,
                audioFilePath,
                outputDirectory,
                configuration.modelDirectory,
            ]
        )
    }

    public func run(invocation: TranscriptionInvocation) async throws -> TranscriptionProcessResult {
        guard FileManager.default.fileExists(atPath: configuration.expectedEncoderPath) else {
            throw MoonshineSherpaTranscriberError.modelMissing(
                expectedPath: configuration.expectedEncoderPath
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.command)
        process.arguments = invocation.arguments
        process.environment = buildProcessEnvironment()

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
        let pythonDirectory = URL(fileURLWithPath: configuration.pythonExecutablePath)
            .deletingLastPathComponent()
            .path(percentEncoded: false)
        let current = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var merged: [String] = []
        for entry in [pythonDirectory] + current {
            guard !entry.isEmpty, !merged.contains(entry) else { continue }
            merged.append(entry)
        }
        environment["PATH"] = merged.joined(separator: ":")
        return environment
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

public enum MoonshineSherpaTranscriberError: LocalizedError {
    case modelMissing(expectedPath: String)

    public var errorDescription: String? {
        switch self {
        case let .modelMissing(expectedPath):
            return "Moonshine model is missing. Place encoder_model.ort at: \(expectedPath)"
        }
    }
}

// MARK: - Embedded Python script

private let pythonScriptContent = #"""
#!/usr/bin/env python3
import sys
import os
import re
import wave
import numpy as np
import sherpa_onnx

SAMPLE_RATE = 16000
MAX_SAMPLES = int(8.5 * SAMPLE_RATE)

_CJK_SPACE_RE = re.compile(
    r'(?<=[　-鿿豈-﫿぀-ゟ゠-ヿ＀-￯])'
    r' '
    r'(?=[　-鿿豈-﫿぀-ゟ゠-ヿ＀-￯])'
)


def clean_text(text):
    return _CJK_SPACE_RE.sub('', text).strip()


def read_wav_float32(path):
    with wave.open(path, 'rb') as wf:
        assert wf.getnchannels() == 1
        assert wf.getsampwidth() == 2
        sample_rate = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    return samples, sample_rate


def make_recognizer(model_dir):
    return sherpa_onnx.OfflineRecognizer.from_moonshine_v2(
        encoder=os.path.join(model_dir, "encoder_model.ort"),
        decoder=os.path.join(model_dir, "decoder_model_merged.ort"),
        tokens=os.path.join(model_dir, "tokens.txt"),
        num_threads=4,
    )


def transcribe_chunk(recognizer, samples):
    if len(samples) == 0:
        return ""
    stream = recognizer.create_stream()
    stream.accept_waveform(SAMPLE_RATE, samples)
    recognizer.decode_stream(stream)
    return clean_text(stream.result.text)


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <audio_file> <output_dir> <model_dir>", file=sys.stderr)
        sys.exit(1)

    audio_path, output_dir, model_dir = sys.argv[1], sys.argv[2], sys.argv[3]

    for f in ["encoder_model.ort", "decoder_model_merged.ort", "tokens.txt"]:
        p = os.path.join(model_dir, f)
        if not os.path.exists(p):
            print(f"Missing model file: {p}", file=sys.stderr)
            sys.exit(2)

    samples, sample_rate = read_wav_float32(audio_path)
    if sample_rate != SAMPLE_RATE:
        print(f"Expected {SAMPLE_RATE}Hz, got {sample_rate}Hz", file=sys.stderr)
        sys.exit(3)

    recognizer = make_recognizer(model_dir)

    if len(samples) <= MAX_SAMPLES:
        result = transcribe_chunk(recognizer, samples)
    else:
        overlap = int(0.9 * SAMPLE_RATE)
        parts = []
        start = 0
        while start < len(samples):
            end = min(start + MAX_SAMPLES, len(samples))
            parts.append(transcribe_chunk(recognizer, samples[start:end]))
            if end >= len(samples):
                break
            start = end - overlap
        result = "".join(parts)

    audio_name = os.path.splitext(os.path.basename(audio_path))[0]
    output_path = os.path.join(output_dir, f"{audio_name}.txt")
    os.makedirs(output_dir, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(result)
    print(result)


if __name__ == "__main__":
    main()
"""#
