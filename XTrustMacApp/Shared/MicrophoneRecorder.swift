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

    func stopRecording() throws -> RecordingArtifact {
        guard let recorder, let outputURL else {
            throw MicrophoneRecorderError.notRecording
        }

        let durationSeconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.outputURL = nil

        return RecordingArtifact(fileURL: outputURL, durationSeconds: durationSeconds)
    }

    var isRecording: Bool {
        recorder?.isRecording == true
    }
}

enum MicrophoneRecorderError: LocalizedError {
    case failedToStart
    case notRecording
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "Microphone recording could not be started."
        case .notRecording:
            return "No recording is currently in progress."
        case .permissionDenied:
            return "Microphone permission was denied."
        }
    }
}
