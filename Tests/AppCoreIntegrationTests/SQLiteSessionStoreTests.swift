import Foundation
import Testing
@testable import AppCore

struct SQLiteSessionStoreTests {
    @Test
    func insertsAndListsSessions() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tempRoot)
        let store = SQLiteSessionStore(databaseURL: paths.database)
        try store.initialize()

        let session = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .draft
        )
        try store.insertSession(session)

        let sessions = try store.listSessions()

        #expect(sessions.count == 1)
        #expect(sessions.first?.id == session.id)
        #expect(sessions.first?.status == .draft)
    }

    @Test
    func updatesSessionRecordingMetadata() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tempRoot)
        let store = SQLiteSessionStore(databaseURL: paths.database)
        try store.initialize()

        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        try store.insertSession(
            Session(
                id: sessionID,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                status: .draft
            )
        )

        try store.updateSession(
            Session(
                id: sessionID,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                endedAt: Date(timeIntervalSince1970: 1_700_000_120),
                status: .completed,
                audioFilePath: "/tmp/test.wav",
                durationSeconds: 12.0
            )
        )

        let sessions = try store.listSessions()

        #expect(sessions.first?.status == .completed)
        #expect(sessions.first?.audioFilePath == "/tmp/test.wav")
        #expect(sessions.first?.durationSeconds == 12.0)
    }

    @Test
    func updatesSessionTranscriptMetadata() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tempRoot)
        let store = SQLiteSessionStore(databaseURL: paths.database)
        try store.initialize()

        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        try store.insertSession(
            Session(
                id: sessionID,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                status: .completed,
                audioFilePath: "/tmp/test.wav",
                durationSeconds: 5.0
            )
        )

        try store.updateSession(
            Session(
                id: sessionID,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                endedAt: Date(timeIntervalSince1970: 1_700_000_005),
                status: .completed,
                audioFilePath: "/tmp/test.wav",
                durationSeconds: 5.0,
                transcriptText: "こんにちは",
                transcriptFilePath: "/tmp/test.txt",
                transcriptionStatus: .completed,
                transcriptionError: nil,
                transcriptionDurationSeconds: 2.3
            )
        )

        let sessions = try store.listSessions()

        #expect(sessions.first?.transcriptText == "こんにちは")
        #expect(sessions.first?.transcriptFilePath == "/tmp/test.txt")
        #expect(sessions.first?.transcriptionStatus == .completed)
        #expect(sessions.first?.transcriptionDurationSeconds == 2.3)
    }
}
