import AppCore
import Foundation

struct AppDiagnostics {
    let workspaceRoot: URL
    let databaseURL: URL
    let sharedDeviceContext: SharedDeviceContext
    let accessActive: Bool
    let activeAccessAccountDisplayName: String?
    let mlxModelDirectory: String
    let currentAvailableMemoryBytes: UInt64?
    let recoveredMinutesCount: Int
    let audioReady: Bool
    let modelsReady: Bool
    let gemmaModelReady: Bool
    let databaseReady: Bool
    let recordingActive: Bool
    let mlxServerStatus: MLXModelServerStatus?
    let speechAssetStatus: SpeechAssetStatus?

    init(
        paths: WorkspacePaths,
        sharedDeviceContext: SharedDeviceContext,
        accessActive: Bool = false,
        activeAccessAccountDisplayName: String? = nil,
        recoveredMinutesCount: Int = 0,
        fileManager: FileManager = .default,
        recordingActive: Bool = false,
        mlxConfiguration: MLXSummarizerConfiguration,
        mlxServerStatus: MLXModelServerStatus? = nil,
        speechAssetStatus: SpeechAssetStatus? = nil
    ) {
        self.workspaceRoot = paths.root
        self.databaseURL = paths.database
        self.sharedDeviceContext = sharedDeviceContext
        self.accessActive = accessActive
        self.activeAccessAccountDisplayName = activeAccessAccountDisplayName
        self.mlxModelDirectory = mlxConfiguration.modelDirectory
        self.currentAvailableMemoryBytes = try? SystemMemorySnapshot.capture().availableBytes
        self.recoveredMinutesCount = recoveredMinutesCount
        self.audioReady = fileManager.fileExists(atPath: paths.audio.path(percentEncoded: false))
        self.modelsReady = fileManager.fileExists(atPath: paths.models.path(percentEncoded: false))
        self.gemmaModelReady = mlxConfiguration.modelReady
        self.databaseReady = fileManager.fileExists(atPath: paths.database.path(percentEncoded: false))
        self.recordingActive = recordingActive
        self.mlxServerStatus = mlxServerStatus
        self.speechAssetStatus = speechAssetStatus
    }
}
