import AVFoundation
import Foundation

struct RecordingArtifact: Sendable {
    let fileURL: URL
    let durationSeconds: Double
}

@MainActor
final class MicrophoneRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var stopContinuation: CheckedContinuation<RecordingArtifact, Error>?
    private var pendingRecordingDurationSeconds: Double?

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording(to fileURL: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw MicrophoneRecorderError.failedToStart
        }

        self.recorder = recorder
        self.outputURL = fileURL
    }

    func stopRecording() async throws -> RecordingArtifact {
        guard let recorder, outputURL != nil else {
            throw MicrophoneRecorderError.notRecording
        }

        pendingRecordingDurationSeconds = recorder.currentTime
        recorder.stop()

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
        }
    }

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            handleAudioRecorderDidFinishRecording(recorder, successfully: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        Task { @MainActor in
            handleAudioRecorderEncodeErrorDidOccur(recorder, error: error)
        }
    }

    private func handleAudioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recorder == self.recorder else { return }

        let outputURL = self.outputURL
        let durationSeconds = pendingRecordingDurationSeconds ?? recorder.currentTime
        let continuation = stopContinuation

        self.recorder = nil
        self.outputURL = nil
        self.stopContinuation = nil
        self.pendingRecordingDurationSeconds = nil

        guard let continuation else { return }
        guard flag, let outputURL else {
            continuation.resume(throwing: MicrophoneRecorderError.failedToFinalize)
            return
        }

        Task {
            do {
                try await waitForRecordedFileToStabilize(at: outputURL)
                continuation.resume(returning: RecordingArtifact(
                    fileURL: outputURL,
                    durationSeconds: durationSeconds
                ))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func handleAudioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        guard recorder == self.recorder, let continuation = stopContinuation else { return }

        self.recorder = nil
        self.outputURL = nil
        self.stopContinuation = nil
        self.pendingRecordingDurationSeconds = nil
        continuation.resume(throwing: error ?? MicrophoneRecorderError.failedToFinalize)
    }

    private func waitForRecordedFileToStabilize(at fileURL: URL) async throws {
        let fileManager = FileManager.default
        var previousSize: UInt64?

        for attempt in 0..<20 {
            guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                if attempt < 19 {
                    try await Task.sleep(for: .milliseconds(100))
                    continue
                }
                throw MicrophoneRecorderError.recordedFileMissing(path: fileURL.path(percentEncoded: false))
            }

            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
            let currentSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

            if let previousSize, previousSize == currentSize, currentSize > 0 {
                return
            }

            previousSize = currentSize

            if attempt < 19 {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

enum MicrophoneRecorderError: LocalizedError {
    case failedToStart
    case failedToFinalize
    case notRecording
    case permissionDenied
    case recordedFileMissing(path: String)

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "Microphone recording could not be started."
        case .failedToFinalize:
            return "Microphone recording finished unexpectedly before the file was finalized."
        case .notRecording:
            return "No recording is currently in progress."
        case .permissionDenied:
            return "Microphone permission was denied."
        case let .recordedFileMissing(path):
            return "Recorded audio file was not found after stopping. Expected: \(path)"
        }
    }
}
