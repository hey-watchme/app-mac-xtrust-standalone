import AppCore
import Foundation

@MainActor
struct AppRuntime {
    let paths: WorkspacePaths
    let sessionStore: SQLiteSessionStore
    let sharedDeviceContext: SharedDeviceContext
    let accessSessionService: AccessSessionService
    let staleSummaryRecoveryService: StaleSummaryRecoveryService
    let initialRecoveredStaleSummaryCount: Int
    let initialAccessSession: AccessSession?
    let sessionService: SessionService
    let microphoneRecorder: MicrophoneRecorder
    let audioPlaybackController: AudioPlaybackController
    let moonshineTranscriber: MoonshineSherpaTranscriber
    let pressureMonitor: MemoryPressureMonitor
    let mlxModelServer: MLXModelServer
    let gemmaSummarizer: MLXSummarizer
    let summarySummarizer: any Summarizer
    let mlxChatRunner: MLXChatRunner
    let transcriptionJobRunner: TranscriptionJobRunner
    let topicSummaryRunner: TopicSummaryRunner
    let captureRuntime: CaptureRuntime
    let initialSessions: [Session]
    let diagnostics: AppDiagnostics

    static func bootstrap() throws -> AppRuntime {
        let microphoneRecorder = MicrophoneRecorder()
        let audioPlaybackController = AudioPlaybackController()
        let root = try WorkspaceLocator.defaultRoot()
        let paths = WorkspacePaths(root: root)
        let bootstrap = BootstrapWorkspace(fileManager: LocalFileManager())
        _ = try bootstrap.run(paths: paths)
        let modelsRoot = paths.models.path(percentEncoded: false)
        let moonshineTranscriber = MoonshineSherpaTranscriber(
            configuration: .developmentDefault(modelsRootDirectory: modelsRoot)
        )
        let gemmaConfiguration = MLXSummarizerConfiguration.developmentDefault(
            modelsRootDirectory: modelsRoot
        )
        let pressureMonitor = MemoryPressureMonitor()
        pressureMonitor.start()
        let serverConfiguration = MLXModelServerConfiguration(
            pythonExecutablePath: gemmaConfiguration.pythonExecutablePath,
            modelDirectory: gemmaConfiguration.modelDirectory
        )
        let mlxModelServer = MLXModelServer(
            configuration: serverConfiguration,
            pressureMonitor: pressureMonitor
        )
        let gemmaSummarizer = MLXSummarizer(configuration: gemmaConfiguration, server: mlxModelServer)
        let summarySummarizer = SerializedSummarizer(base: gemmaSummarizer)
        let mlxChatRunner = MLXChatRunner(configuration: gemmaConfiguration, server: mlxModelServer)
        let sessionStore = SQLiteSessionStore(databaseURL: paths.database)
        try sessionStore.initialize()
        let staleSummaryRecoveryService = StaleSummaryRecoveryService(
            sessionStore: sessionStore,
            topicStore: sessionStore
        )
        let recoveredStaleSummaryCount = try staleSummaryRecoveryService.recover()
        let sharedDeviceBootstrap = SharedDeviceBootstrapService(
            organizationStore: sessionStore,
            workspaceStore: sessionStore,
            deviceStore: sessionStore,
            accountStore: sessionStore,
            organizationMembershipStore: sessionStore,
            clock: SystemClock()
        )
        let sharedDeviceContext = try sharedDeviceBootstrap.run(
            configuration: .developmentDefault(
                deviceName: Host.current().localizedName ?? "This Mac"
            )
        )
        let accessSessionService = AccessSessionService(
            accessSessionStore: sessionStore,
            clock: SystemClock()
        )
        let initialAccessSession = try accessSessionService.activeAccessSession(
            deviceID: sharedDeviceContext.device.id
        )
        let sessionService = SessionService(
            sessionStore: sessionStore,
            clock: SystemClock()
        )
        let transcriptionJobRunner = TranscriptionJobRunner(
            paths: paths,
            jobStore: sessionStore,
            transcriptArtifactStore: sessionStore,
            transcriber: moonshineTranscriber,
            clock: SystemClock()
        )
        let topicAssignmentService = TopicAssignmentService(
            topicStore: sessionStore,
            utteranceStore: sessionStore
        )
        let topicSummaryRunner = TopicSummaryRunner(
            topicStore: sessionStore,
            utteranceStore: sessionStore,
            transcriptArtifactStore: sessionStore,
            summarizer: summarySummarizer
        )
        let captureRuntime = CaptureRuntime(
            captureController: AVAudioCaptureController(),
            utteranceStore: sessionStore,
            recordingArtifactStore: sessionStore,
            clock: SystemClock(),
            topicAssignmentService: topicAssignmentService
        )

        let sessions = if initialAccessSession == nil {
            [Session]()
        } else {
            try sessionService.loadSessions()
        }

        return AppRuntime(
            paths: paths,
            sessionStore: sessionStore,
            sharedDeviceContext: sharedDeviceContext,
            accessSessionService: accessSessionService,
            staleSummaryRecoveryService: staleSummaryRecoveryService,
            initialRecoveredStaleSummaryCount: recoveredStaleSummaryCount,
            initialAccessSession: initialAccessSession,
            sessionService: sessionService,
            microphoneRecorder: microphoneRecorder,
            audioPlaybackController: audioPlaybackController,
            moonshineTranscriber: moonshineTranscriber,
            pressureMonitor: pressureMonitor,
            mlxModelServer: mlxModelServer,
            gemmaSummarizer: gemmaSummarizer,
            summarySummarizer: summarySummarizer,
            mlxChatRunner: mlxChatRunner,
            transcriptionJobRunner: transcriptionJobRunner,
            topicSummaryRunner: topicSummaryRunner,
            captureRuntime: captureRuntime,
            initialSessions: sessions,
            diagnostics: AppDiagnostics(
                paths: paths,
                sharedDeviceContext: sharedDeviceContext,
                accessActive: initialAccessSession != nil,
                activeAccessAccountDisplayName: initialAccessSession?.accountID == sharedDeviceContext.bootstrapAccount.id
                    ? sharedDeviceContext.bootstrapAccount.displayName
                    : nil,
                recoveredStaleSummaryCount: recoveredStaleSummaryCount,
                recordingActive: microphoneRecorder.isRecording,
                moonshineConfiguration: moonshineTranscriber.configuration,
                mlxConfiguration: gemmaConfiguration
            )
        )
    }
}
