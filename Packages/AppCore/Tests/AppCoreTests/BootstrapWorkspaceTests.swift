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
        #expect(FileManager.default.fileExists(atPath: paths.jobs.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: paths.transcriptionJobs.path(percentEncoded: false)))
    }

    @Test
    func createsStableTranscriptionJobDirectoryPath() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let paths = WorkspacePaths(root: tempRoot)
        let jobID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!

        let directory = paths.transcriptionJobDirectory(jobID: jobID)

        #expect(directory.lastPathComponent == jobID.uuidString)
        #expect(directory.deletingLastPathComponent() == paths.transcriptionJobs)
    }
}
