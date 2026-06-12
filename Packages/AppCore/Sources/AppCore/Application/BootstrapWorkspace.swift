import Foundation

public struct BootstrapWorkspace: Sendable {
    private let fileManager: FileManaging

    public init(fileManager: FileManaging) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func run(paths: WorkspacePaths) throws -> WorkspacePaths {
        try fileManager.createDirectory(at: paths.root)
        try fileManager.createDirectory(at: paths.audio)
        try fileManager.createDirectory(at: paths.transcripts)
        try fileManager.createDirectory(at: paths.summaries)
        try fileManager.createDirectory(at: paths.models)
        return paths
    }
}
