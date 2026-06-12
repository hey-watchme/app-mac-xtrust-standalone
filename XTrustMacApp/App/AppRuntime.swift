import AppCore
import Foundation

@MainActor
struct AppRuntime {
    let paths: WorkspacePaths
    let sessionStore: SQLiteSessionStore
    let sharedDeviceContext: SharedDeviceContext
    let accessSessionService: AccessSessionService
    let initialAccessSession: AccessSession?
    let audioPlaybackController: AudioPlaybackController
    let pressureMonitor: MemoryPressureMonitor
    let mlxModelServer: MLXModelServer
    let mlxConfiguration: MLXSummarizerConfiguration
    let mlxChatRunner: MLXChatRunner
    let minutesService: MeetingMinutesService
    let minutesRecoveryService: MinutesRecoveryService
    let meetingStore: MeetingStore
    let diagnostics: AppDiagnostics

    static func bootstrap() throws -> AppRuntime {
        let root = try WorkspaceLocator.defaultRoot()
        let paths = WorkspacePaths(root: root)
        let bootstrap = BootstrapWorkspace(fileManager: LocalFileManager())
        _ = try bootstrap.run(paths: paths)

        let modelsRoot = paths.models.path(percentEncoded: false)
        let mlxConfiguration = MLXSummarizerConfiguration.developmentDefault(
            modelsRootDirectory: modelsRoot
        )
        let pressureMonitor = MemoryPressureMonitor()
        pressureMonitor.start()
        let serverConfiguration = MLXModelServerConfiguration(
            pythonExecutablePath: mlxConfiguration.pythonExecutablePath,
            modelDirectory: mlxConfiguration.modelDirectory
        )
        let mlxModelServer = MLXModelServer(
            configuration: serverConfiguration,
            pressureMonitor: pressureMonitor
        )
        let gemmaSummarizer = MLXSummarizer(configuration: mlxConfiguration, server: mlxModelServer)
        let mlxChatRunner = MLXChatRunner(configuration: mlxConfiguration, server: mlxModelServer)

        let sessionStore = SQLiteSessionStore(databaseURL: paths.database)
        try sessionStore.initialize()

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

        let captureSessionService = CaptureSessionService(
            captureSessionStore: sessionStore,
            clock: SystemClock()
        )
        let liveMeetingRecorder = LiveMeetingRecorder(
            utteranceStore: sessionStore,
            clock: SystemClock()
        )
        let minutesService = MeetingMinutesService(
            minutesStore: sessionStore,
            utteranceStore: sessionStore,
            summarizer: SerializedSummarizer(base: gemmaSummarizer),
            clock: SystemClock()
        )
        let minutesRecoveryService = MinutesRecoveryService(minutesStore: sessionStore)

        let meetingStore = MeetingStore(
            engine: SpeechAnalyzerCaptureEngine(),
            captureSessionService: captureSessionService,
            liveMeetingRecorder: liveMeetingRecorder,
            minutesService: minutesService,
            utteranceStore: sessionStore,
            minutesStore: sessionStore,
            audioDirectory: paths.audio
        )

        return AppRuntime(
            paths: paths,
            sessionStore: sessionStore,
            sharedDeviceContext: sharedDeviceContext,
            accessSessionService: accessSessionService,
            initialAccessSession: initialAccessSession,
            audioPlaybackController: AudioPlaybackController(),
            pressureMonitor: pressureMonitor,
            mlxModelServer: mlxModelServer,
            mlxConfiguration: mlxConfiguration,
            mlxChatRunner: mlxChatRunner,
            minutesService: minutesService,
            minutesRecoveryService: minutesRecoveryService,
            meetingStore: meetingStore,
            diagnostics: AppDiagnostics(
                paths: paths,
                sharedDeviceContext: sharedDeviceContext,
                accessActive: initialAccessSession != nil,
                activeAccessAccountDisplayName: initialAccessSession?.accountID == sharedDeviceContext.bootstrapAccount.id
                    ? sharedDeviceContext.bootstrapAccount.displayName
                    : nil,
                mlxConfiguration: mlxConfiguration
            )
        )
    }
}
