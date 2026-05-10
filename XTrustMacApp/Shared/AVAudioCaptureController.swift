import AppCore
import AVFoundation
import Darwin
import Foundation

final class AVAudioCaptureController: CaptureController, @unchecked Sendable {
    // Set on main thread before engine starts; read from tap thread after start.
    // Safe because tap only runs between start() and stop().
    private var engine: AVAudioEngine?
    private var utteranceOutputDirectory: URL?
    private var onEventCallback: (@Sendable (CaptureEvent) -> Void)?

    // Tap-thread-only state. The tap callback is serial per AVAudioEngine.
    // Accessed only between startCapture() and stopCapture().
    private var targetFormat: AVAudioFormat?
    private var silenceThresholdFrames: Int = 0
    private var speechActive = false
    private var silenceFrameCount: Int = 0
    private var speechStartTime: Date?
    private var utteranceFile: AVAudioFile?
    private var utteranceFileURL: URL?
    private var pendingSilenceBuffers: [AVAudioPCMBuffer] = []
    private var pendingSilenceFrameCount: Int = 0

    private let speechRMSThreshold: Float = 0.01
    private let silenceThresholdSeconds: Double = 3.0

    var isCapturing: Bool { engine?.isRunning == true }

    func startCapture(
        utteranceOutputDirectory: URL,
        onEvent: @escaping @Sendable (CaptureEvent) -> Void
    ) throws {
        self.utteranceOutputDirectory = utteranceOutputDirectory
        self.onEventCallback = onEvent

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!
        self.targetFormat = targetFormat
        self.silenceThresholdFrames = Int(silenceThresholdSeconds * targetFormat.sampleRate)
        self.speechActive = false
        self.silenceFrameCount = 0
        self.pendingSilenceBuffers = []
        self.pendingSilenceFrameCount = 0

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw AVAudioCaptureError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer, hardwareFormat: hardwareFormat, converter: converter)
        }

        try engine.start()
        self.engine = engine
    }

    func stopCapture() {
        // Stop engine first so no further tap callbacks fire.
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil

        // Tap is guaranteed done at this point.
        if speechActive {
            finalizeCurrentUtterance()
        }

        utteranceFile = nil
        utteranceFileURL = nil
        speechStartTime = nil
        speechActive = false
        silenceFrameCount = 0
        pendingSilenceBuffers = []
        pendingSilenceFrameCount = 0
        onEventCallback = nil
        utteranceOutputDirectory = nil
    }

    // MARK: - Tap callback (tap thread, serial per engine)

    private func processTapBuffer(
        _ buffer: AVAudioPCMBuffer,
        hardwareFormat: AVAudioFormat,
        converter: AVAudioConverter
    ) {
        let rms = computeRMS(buffer, format: hardwareFormat)
        onEventCallback?(.levelUpdated(rmsLevel: rms))

        guard let convertedBuffer = convert(buffer, using: converter) else { return }

        if rms > speechRMSThreshold {
            silenceFrameCount = 0
            if !speechActive {
                speechActive = true
                speechStartTime = Date()
                beginNewUtteranceFile()
                onEventCallback?(.speechStarted)
            }
            flushPendingSilenceToCurrentFile()
            writeToCurrentFile(convertedBuffer)
        } else {
            if speechActive {
                bufferPendingSilence(convertedBuffer)
                silenceFrameCount += Int(convertedBuffer.frameLength)
                if silenceFrameCount >= silenceThresholdFrames {
                    finalizeCurrentUtterance()
                    speechActive = false
                    silenceFrameCount = 0
                    onEventCallback?(.speechStopped)
                }
            }
        }
    }

    private func convert(
        _ source: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio))
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)
        else { return nil }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return source
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    private func computeRMS(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let data = buffer.floatChannelData else { return 0 }
            var sum: Float = 0
            for i in 0..<frameLength { sum += data[0][i] * data[0][i] }
            return sqrt(sum / Float(frameLength))
        case .pcmFormatInt16:
            guard let data = buffer.int16ChannelData else { return 0 }
            var sum: Float = 0
            for i in 0..<frameLength {
                let s = Float(data[0][i]) / Float(Int16.max)
                sum += s * s
            }
            return sqrt(sum / Float(frameLength))
        default:
            return 0
        }
    }

    private func beginNewUtteranceFile() {
        guard let dir = utteranceOutputDirectory else { return }
        let fileURL = dir.appending(path: "\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            utteranceFile = try AVAudioFile(
                forWriting: fileURL,
                settings: settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
            utteranceFileURL = fileURL
        } catch {
            // Tap continues without writing; utterance will not be finalized.
        }
    }

    private func writeToCurrentFile(_ buffer: AVAudioPCMBuffer) {
        try? utteranceFile?.write(from: buffer)
    }

    private func bufferPendingSilence(_ buffer: AVAudioPCMBuffer) {
        guard let copiedBuffer = copyBuffer(buffer) else { return }
        pendingSilenceBuffers.append(copiedBuffer)
        pendingSilenceFrameCount += Int(copiedBuffer.frameLength)
    }

    private func flushPendingSilenceToCurrentFile() {
        guard !pendingSilenceBuffers.isEmpty else { return }
        for buffer in pendingSilenceBuffers {
            writeToCurrentFile(buffer)
        }
        pendingSilenceBuffers.removeAll(keepingCapacity: true)
        pendingSilenceFrameCount = 0
    }

    private func clearPendingSilence() {
        pendingSilenceBuffers.removeAll(keepingCapacity: true)
        pendingSilenceFrameCount = 0
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let format = targetFormat,
              let sourceChannelData = buffer.int16ChannelData,
              let copiedBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: buffer.frameLength
              ),
              let destinationChannelData = copiedBuffer.int16ChannelData else {
            return nil
        }

        copiedBuffer.frameLength = buffer.frameLength
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.stride
        memcpy(destinationChannelData[0], sourceChannelData[0], byteCount)
        return copiedBuffer
    }

    private func finalizeCurrentUtterance() {
        guard let startTime = speechStartTime, let fileURL = utteranceFileURL else { return }
        let trailingSilenceDuration = targetFormat.map {
            Double(pendingSilenceFrameCount) / $0.sampleRate
        } ?? 0
        let endedAt = Date().addingTimeInterval(-trailingSilenceDuration)
        let durationSeconds = endedAt.timeIntervalSince(startTime)

        // Release AVAudioFile to flush and close the file before firing the event.
        utteranceFile = nil
        utteranceFileURL = nil
        speechStartTime = nil
        clearPendingSilence()

        onEventCallback?(.utteranceFinalized(
            audioFileURL: fileURL,
            startedAt: startTime,
            endedAt: endedAt,
            durationSeconds: durationSeconds
        ))
    }
}

enum AVAudioCaptureError: LocalizedError {
    case converterCreationFailed

    var errorDescription: String? {
        "Failed to create audio format converter for capture pipeline."
    }
}
