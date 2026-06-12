import AppCore
@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech

// On-device streaming capture engine backed by SpeechAnalyzer / SpeechTranscriber.
// One session wav is written per capture; utterance positions are reported as
// offsets into that file.
@MainActor
final class SpeechAnalyzerCaptureEngine: MeetingCaptureEngine {
    private(set) var state: CaptureEngineState = .idle

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var tapContext: CaptureTapContext?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var eventContinuation: AsyncStream<CaptureEngineEvent>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var audioFileURL: URL?

    func start(_ request: CaptureStartRequest) -> AsyncStream<CaptureEngineEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEngineEvent.self)

        switch state {
        case .idle, .stopped, .failed:
            break
        case .preparing, .listening, .stopping:
            continuation.yield(.stateChanged(.failed(.audioEngineFailed("Capture is already in progress."))))
            continuation.finish()
            return stream
        }

        eventContinuation = continuation
        startTask = Task { [weak self] in
            await self?.performStart(request)
        }
        return stream
    }

    func stop() async throws -> CaptureStopResult {
        guard case .listening = state,
              let audioEngine,
              let analyzer,
              let tapContext,
              let audioFileURL else {
            throw SpeechAnalyzerCaptureEngineError.notListening
        }

        emitState(.stopping)

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()

        // Finalize pending volatile results; remaining finals arrive on the
        // results stream, which ends afterwards.
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            // Drain whatever was produced; the wav and recorded utterances stay valid.
        }
        await resultsTask?.value

        let durationSeconds = tapContext.framesWrittenSeconds
        tapContext.closeFile()

        emitState(.stopped)
        eventContinuation?.finish()
        reset(to: .stopped)

        return CaptureStopResult(audioFileURL: audioFileURL, durationSeconds: durationSeconds)
    }

    // MARK: - Start sequence

    private func performStart(_ request: CaptureStartRequest) async {
        emitState(.preparing(.checkingPermission))
        guard await Self.requestMicrophonePermission() else {
            fail(.microphonePermissionDenied)
            return
        }

        emitState(.preparing(.checkingAssets))
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: request.localeIdentifier)
        ) else {
            fail(.localeNotSupported(request.localeIdentifier))
            return
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        do {
            try await ensureAssetsInstalled(for: transcriber)
        } catch {
            fail(.assetInstallationFailed(error.localizedDescription))
            return
        }

        emitState(.preparing(.startingAudio))
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            fail(.transcriberFailed("No compatible analyzer audio format is available."))
            return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        do {
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
        } catch {
            fail(.transcriberFailed(error.localizedDescription))
            return
        }

        // The results consumer must be running before analysis starts.
        startResultsTask(transcriber: transcriber)

        let (inputStream, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputContinuation = inputContinuation

        do {
            try await analyzer.start(inputSequence: inputStream)
        } catch {
            fail(.transcriberFailed(error.localizedDescription))
            return
        }

        guard let eventContinuation else {
            fail(.audioEngineFailed("Capture event stream was torn down during startup."))
            return
        }

        do {
            try startAudioEngine(
                audioFileURL: request.audioFileURL,
                analyzerFormat: analyzerFormat,
                inputContinuation: inputContinuation,
                eventContinuation: eventContinuation
            )
        } catch {
            fail(.audioEngineFailed(error.localizedDescription))
            return
        }

        audioFileURL = request.audioFileURL
        emitState(.listening)
    }

    private func ensureAssetsInstalled(for transcriber: SpeechTranscriber) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            return
        case .unsupported:
            throw SpeechAnalyzerCaptureEngineError.assetsUnsupported
        case .supported, .downloading:
            break
        @unknown default:
            break
        }

        guard let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) else {
            return
        }

        emitState(.preparing(.downloadingAssets(progress: nil)))
        let progress = installationRequest.progress
        let progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.emitState(.preparing(.downloadingAssets(progress: progress.fractionCompleted)))
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { progressTask.cancel() }
        try await installationRequest.downloadAndInstall()
    }

    private func startAudioEngine(
        audioFileURL: URL,
        analyzerFormat: AVAudioFormat,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        eventContinuation: AsyncStream<CaptureEngineEvent>.Continuation
    ) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: hardwareFormat, to: analyzerFormat) else {
            throw SpeechAnalyzerCaptureEngineError.converterCreationFailed
        }

        let audioFile = try AVAudioFile(
            forWriting: audioFileURL,
            settings: analyzerFormat.settings,
            commonFormat: analyzerFormat.commonFormat,
            interleaved: analyzerFormat.isInterleaved
        )

        let context = CaptureTapContext(
            converter: converter,
            audioFile: audioFile,
            sampleRate: analyzerFormat.sampleRate,
            inputContinuation: inputContinuation,
            eventContinuation: eventContinuation
        )
        tapContext = context

        // @Sendable opts this closure out of inherited MainActor isolation:
        // the SDK tap block is not Sendable-annotated and fires on an audio
        // queue, so an isolated closure would trap with
        // _dispatch_assert_queue_fail at runtime.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { @Sendable buffer, _ in
            context.process(buffer)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
        audioEngine = engine
    }

    private func startResultsTask(transcriber: SpeechTranscriber) {
        resultsTask = Task { [weak self] in
            var lastEndSeconds: Double = 0
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        var start = result.range.start.seconds
                        var end = result.range.end.seconds
                        if !start.isFinite || !end.isFinite || end <= 0 {
                            // Fall back to the frames-written counter.
                            start = lastEndSeconds
                            end = self.tapContext?.framesWrittenSeconds ?? lastEndSeconds
                        }
                        lastEndSeconds = max(lastEndSeconds, end)

                        self.eventContinuation?.yield(.finalizedUtterance(FinalizedUtteranceEvent(
                            text: trimmed,
                            startOffsetSeconds: max(0, start),
                            endOffsetSeconds: max(0, end)
                        )))
                    } else {
                        self.eventContinuation?.yield(.volatileTranscript(text))
                    }
                }
            } catch {
                guard let self else { return }
                if case .listening = self.state {
                    self.fail(.transcriberFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - State helpers

    private func emitState(_ newState: CaptureEngineState) {
        state = newState
        eventContinuation?.yield(.stateChanged(newState))
    }

    private func fail(_ failure: CaptureEngineFailure) {
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        inputContinuation?.finish()
        tapContext?.closeFile()
        emitState(.failed(failure))
        eventContinuation?.finish()
        reset(to: .failed(failure))
    }

    private func reset(to finalState: CaptureEngineState) {
        audioEngine = nil
        analyzer = nil
        transcriber = nil
        tapContext = nil
        inputContinuation = nil
        eventContinuation = nil
        resultsTask = nil
        startTask = nil
        audioFileURL = nil
        state = finalState
    }

    // MARK: - Microphone permission

    static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                // @Sendable: the SDK handler is not Sendable-annotated and may
                // run on an arbitrary queue; see the tap block note above.
                AVCaptureDevice.requestAccess(for: .audio) { @Sendable granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

// MARK: - Tap context (audio-thread state)

// Owns everything the AVAudioEngine tap callback touches. The tap callback is
// serial per engine; the lock only guards framesWritten reads from other threads.
private final class CaptureTapContext: @unchecked Sendable {
    private let converter: AVAudioConverter
    private var audioFile: AVAudioFile?
    private let sampleRate: Double
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let eventContinuation: AsyncStream<CaptureEngineEvent>.Continuation

    private let lock = NSLock()
    private var framesWritten: Int64 = 0
    private var lastLevelEmittedAt: TimeInterval = 0
    private let levelEmitInterval: TimeInterval = 0.04

    init(
        converter: AVAudioConverter,
        audioFile: AVAudioFile,
        sampleRate: Double,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        eventContinuation: AsyncStream<CaptureEngineEvent>.Continuation
    ) {
        self.converter = converter
        self.audioFile = audioFile
        self.sampleRate = sampleRate
        self.inputContinuation = inputContinuation
        self.eventContinuation = eventContinuation
    }

    var framesWrittenSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(framesWritten) / sampleRate
    }

    func closeFile() {
        lock.lock()
        defer { lock.unlock() }
        // Releasing the AVAudioFile flushes and closes the wav.
        audioFile = nil
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        emitLevelIfDue(rms: Self.computeRMS(buffer))

        guard let converted = convert(buffer) else { return }

        lock.lock()
        if let audioFile {
            try? audioFile.write(from: converted)
        }
        framesWritten += Int64(converted.frameLength)
        lock.unlock()

        inputContinuation.yield(AnalyzerInput(buffer: converted))
    }

    private func emitLevelIfDue(rms: Float) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelEmittedAt >= levelEmitInterval else { return }
        lastLevelEmittedAt = now
        eventContinuation.yield(.audioLevel(rms))
    }

    // Single-shot convert: feed the source buffer exactly once per call.
    private func convert(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio))
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)
        else { return nil }

        let consumed = SingleShotFlag()
        var error: NSError?
        converter.convert(to: output, error: &error) { _, outStatus in
            if consumed.takeOnce() {
                outStatus.pointee = .haveData
                return source
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    private static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let data = buffer.floatChannelData else { return 0 }
            var sum: Float = 0
            for i in 0..<frameLength { sum += data[0][i] * data[0][i] }
            return sqrt(sum / Float(frameLength))
        case .pcmFormatInt16:
            guard let data = buffer.int16ChannelData else { return 0 }
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = Float(data[0][i]) / Float(Int16.max)
                sum += sample * sample
            }
            return sqrt(sum / Float(frameLength))
        default:
            return 0
        }
    }
}

// Marks one-shot consumption inside the synchronous converter input block.
private final class SingleShotFlag: @unchecked Sendable {
    private var fired = false

    func takeOnce() -> Bool {
        if fired { return false }
        fired = true
        return true
    }
}

enum SpeechAnalyzerCaptureEngineError: LocalizedError {
    case notListening
    case assetsUnsupported
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .notListening:
            return "Capture cannot be stopped because the engine is not listening."
        case .assetsUnsupported:
            return "Speech recognition assets are not supported on this device."
        case .converterCreationFailed:
            return "Failed to create the audio format converter for the analyzer."
        }
    }
}
