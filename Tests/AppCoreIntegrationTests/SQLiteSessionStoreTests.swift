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

    @Test
    func insertsAndListsTopicsForSession() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tempRoot)
        let store = SQLiteSessionStore(databaseURL: paths.database)
        try store.initialize()

        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        try store.insertSession(
            Session(
                id: sessionID,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                status: .draft
            )
        )

        let topic = Topic(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )
        try store.insertTopic(topic)

        let topics = try store.listTopics(sessionID: sessionID)

        #expect(topics == [topic])
    }

    @Test
    func insertsAndListsUtterancesForSession() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tempRoot)
        let store = SQLiteSessionStore(databaseURL: paths.database)
        try store.initialize()

        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let topicID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        try store.insertSession(
            Session(
                id: sessionID,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                status: .draft
            )
        )
        try store.insertTopic(
            Topic(
                id: topicID,
                sessionID: sessionID,
                startedAt: Date(timeIntervalSince1970: 1_700_000_020)
            )
        )

        let utterance = Utterance(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
            sessionID: sessionID,
            topicID: topicID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_021),
            endedAt: Date(timeIntervalSince1970: 1_700_000_028),
            durationSeconds: 7,
            audioFilePath: "/tmp/utt.wav"
        )
        try store.insertUtterance(utterance)

        let utterances = try store.listUtterances(sessionID: sessionID)

        #expect(utterances == [utterance])
    }

    @Test
    func insertsAndListsRecordingArtifactsForUtterance() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tempRoot)
        let store = SQLiteSessionStore(databaseURL: paths.database)
        try store.initialize()

        let utteranceID = try insertSessionAndUtterance(store: store)
        let artifact = RecordingArtifactMetadata(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
            utteranceID: utteranceID,
            filePath: "/tmp/utt.wav",
            byteSize: 4_096,
            durationSeconds: 3.2,
            sampleRate: 16_000,
            channelCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try store.insertRecordingArtifact(artifact)

        let artifacts = try store.listRecordingArtifacts(utteranceID: utteranceID)

        #expect(artifacts == [artifact])
    }

    @Test
    func insertsAndListsTranscriptionJobsForUtterance() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tempRoot)
        let store = SQLiteSessionStore(databaseURL: paths.database)
        try store.initialize()

        let utteranceID = try insertSessionAndUtterance(store: store)
        let recordingArtifactID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        try store.insertRecordingArtifact(
            RecordingArtifactMetadata(
                id: recordingArtifactID,
                utteranceID: utteranceID,
                filePath: "/tmp/input.wav",
                byteSize: 8_192,
                durationSeconds: 6.4,
                sampleRate: 16_000,
                channelCount: 1,
                createdAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )
        let job = TranscriptionJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
            utteranceID: utteranceID,
            recordingArtifactID: recordingArtifactID,
            workingDirectoryPath: "/tmp/jobs/702",
            command: "whisper",
            arguments: ["input.wav", "--output_format", "txt"],
            modelIdentifier: "small",
            language: "ja",
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_700_000_110),
            startedAt: Date(timeIntervalSince1970: 1_700_000_111),
            endedAt: Date(timeIntervalSince1970: 1_700_000_120),
            stdoutFilePath: "/tmp/jobs/702/stdout.txt",
            stderrFilePath: "/tmp/jobs/702/stderr.txt",
            exitCode: 0,
            outputFileNames: ["input.txt"],
            failureMessage: nil
        )
        try store.insertTranscriptionJob(job)

        let jobs = try store.listTranscriptionJobs(utteranceID: utteranceID)

        #expect(jobs == [job])
    }

    @Test
    func insertsAndListsTranscriptArtifactsForUtterance() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tempRoot)
        let store = SQLiteSessionStore(databaseURL: paths.database)
        try store.initialize()

        let utteranceID = try insertSessionAndUtterance(store: store)
        let recordingArtifactID = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!
        let transcriptionJobID = UUID(uuidString: "00000000-0000-0000-0000-000000000802")!
        try store.insertRecordingArtifact(
            RecordingArtifactMetadata(
                id: recordingArtifactID,
                utteranceID: utteranceID,
                filePath: "/tmp/input.wav",
                byteSize: 1_024,
                durationSeconds: 1.1,
                sampleRate: 16_000,
                channelCount: 1,
                createdAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )
        try store.insertTranscriptionJob(
            TranscriptionJob(
                id: transcriptionJobID,
                utteranceID: utteranceID,
                recordingArtifactID: recordingArtifactID,
                workingDirectoryPath: "/tmp/jobs/802",
                command: "whisper",
                arguments: ["input.wav"],
                modelIdentifier: "small",
                language: "ja",
                status: .completed,
                createdAt: Date(timeIntervalSince1970: 1_700_000_110),
                startedAt: Date(timeIntervalSince1970: 1_700_000_111),
                endedAt: Date(timeIntervalSince1970: 1_700_000_120),
                stdoutFilePath: "/tmp/jobs/802/stdout.txt",
                stderrFilePath: "/tmp/jobs/802/stderr.txt",
                exitCode: 0,
                outputFileNames: ["input.txt"],
                failureMessage: nil
            )
        )
        let artifact = TranscriptArtifactMetadata(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000803")!,
            utteranceID: utteranceID,
            transcriptionJobID: transcriptionJobID,
            filePath: "/tmp/input.txt",
            text: "hello",
            modelIdentifier: "small",
            language: "ja",
            createdAt: Date(timeIntervalSince1970: 1_700_000_121)
        )
        try store.insertTranscriptArtifact(artifact)

        let artifacts = try store.listTranscriptArtifacts(utteranceID: utteranceID)

        #expect(artifacts == [artifact])
    }
}

private func insertSessionAndUtterance(store: SQLiteSessionStore) throws -> UUID {
    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000900")!
    let utteranceID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
    try store.insertSession(
        Session(
            id: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .draft
        )
    )
    try store.insertUtterance(
        Utterance(
            id: utteranceID,
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_001),
            endedAt: Date(timeIntervalSince1970: 1_700_000_004),
            durationSeconds: 3,
            audioFilePath: "/tmp/utt.wav"
        )
    )
    return utteranceID
}
