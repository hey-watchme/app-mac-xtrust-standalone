import AppCore
import Foundation

struct AppDiagnostics {
    let workspaceRoot: URL
    let databaseURL: URL
    let sharedDeviceContext: SharedDeviceContext
    let accessActive: Bool
    let activeAccessAccountDisplayName: String?
    let whisperModelPath: String
    let mlxModelDirectory: String
    let mlxRequiredAvailableMemoryBytes: UInt64
    let currentAvailableMemoryBytes: UInt64?
    let recoveredStaleSummaryCount: Int
    let audioReady: Bool
    let transcriptsReady: Bool
    let summariesReady: Bool
    let modelsReady: Bool
    let whisperModelReady: Bool
    let gemmaModelReady: Bool
    let databaseReady: Bool
    let recordingActive: Bool

    init(
        paths: WorkspacePaths,
        sharedDeviceContext: SharedDeviceContext,
        accessActive: Bool = false,
        activeAccessAccountDisplayName: String? = nil,
        recoveredStaleSummaryCount: Int = 0,
        fileManager: FileManager = .default,
        recordingActive: Bool = false,
        whisperConfiguration: WhisperCLITranscriberConfiguration,
        mlxConfiguration: MLXSummarizerConfiguration
    ) {
        self.workspaceRoot = paths.root
        self.databaseURL = paths.database
        self.sharedDeviceContext = sharedDeviceContext
        self.accessActive = accessActive
        self.activeAccessAccountDisplayName = activeAccessAccountDisplayName
        self.whisperModelPath = whisperConfiguration.expectedModelFilePath
        self.mlxModelDirectory = mlxConfiguration.modelDirectory
        self.mlxRequiredAvailableMemoryBytes = mlxConfiguration.requiredAvailableMemoryBytes
        self.currentAvailableMemoryBytes = try? SystemMemorySnapshot.capture().availableBytes
        self.recoveredStaleSummaryCount = recoveredStaleSummaryCount
        self.audioReady = fileManager.fileExists(atPath: paths.audio.path(percentEncoded: false))
        self.transcriptsReady = fileManager.fileExists(atPath: paths.transcripts.path(percentEncoded: false))
        self.summariesReady = fileManager.fileExists(atPath: paths.summaries.path(percentEncoded: false))
        self.modelsReady = fileManager.fileExists(atPath: paths.models.path(percentEncoded: false))
        self.whisperModelReady = fileManager.fileExists(atPath: whisperConfiguration.expectedModelFilePath)
        self.gemmaModelReady = mlxConfiguration.modelReady
        self.databaseReady = fileManager.fileExists(atPath: paths.database.path(percentEncoded: false))
        self.recordingActive = recordingActive
    }
}
