import Foundation
import Testing
@testable import AppCore

struct BootstrapWorkspaceTests {
    @Test
    func createsExpectedDirectories() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let paths = WorkspacePaths(root: tempRoot)
        let bootstrap = BootstrapWorkspace(fileManager: LocalFileManager())

        _ = try bootstrap.run(paths: paths)

        #expect(FileManager.default.fileExists(atPath: paths.root.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: paths.audio.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: paths.transcripts.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: paths.summaries.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: paths.models.path(percentEncoded: false)))
    }
}
