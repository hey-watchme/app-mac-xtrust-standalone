import AppCore
import Foundation

struct AppDiagnostics {
    let workspaceRoot: URL
    let databaseURL: URL
    let whisperModelPath: String
    let audioReady: Bool
    let transcriptsReady: Bool
    let summariesReady: Bool
    let modelsReady: Bool
    let whisperModelReady: Bool
    let databaseReady: Bool
    let recordingActive: Bool

    init(
        paths: WorkspacePaths,
        fileManager: FileManager = .default,
        recordingActive: Bool = false,
        whisperConfiguration: WhisperTranscriberConfiguration
    ) {
        self.workspaceRoot = paths.root
        self.databaseURL = paths.database
        self.whisperModelPath = whisperConfiguration.expectedModelFilePath
        self.audioReady = fileManager.fileExists(atPath: paths.audio.path(percentEncoded: false))
        self.transcriptsReady = fileManager.fileExists(atPath: paths.transcripts.path(percentEncoded: false))
        self.summariesReady = fileManager.fileExists(atPath: paths.summaries.path(percentEncoded: false))
        self.modelsReady = fileManager.fileExists(atPath: paths.models.path(percentEncoded: false))
        self.whisperModelReady = fileManager.fileExists(atPath: whisperConfiguration.expectedModelFilePath)
        self.databaseReady = fileManager.fileExists(atPath: paths.database.path(percentEncoded: false))
        self.recordingActive = recordingActive
    }
}
