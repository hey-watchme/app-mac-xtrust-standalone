import Foundation
import SQLite3

public final class SQLiteSessionStore: SessionStore, TopicStore, UtteranceStore, RecordingArtifactStore, TranscriptArtifactStore, TranscriptionJobStore, @unchecked Sendable {
    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func initialize() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY NOT NULL,
            started_at REAL NOT NULL,
            ended_at REAL,
            status TEXT NOT NULL,
            audio_path TEXT,
            duration_seconds REAL,
            transcript_text TEXT,
            transcript_file_path TEXT,
            meeting_context_profile TEXT NOT NULL DEFAULT 'general',
            transcription_status TEXT NOT NULL DEFAULT 'idle',
            transcription_error TEXT,
            transcription_duration_seconds REAL,
            utterance_count INTEGER NOT NULL DEFAULT 0,
            topic_count INTEGER NOT NULL DEFAULT 0
        );
        """, in: db)
        try addColumnIfNeeded(table: "sessions", column: "audio_path", definition: "TEXT", in: db)
        try addColumnIfNeeded(table: "sessions", column: "duration_seconds", definition: "REAL", in: db)
        try addColumnIfNeeded(table: "sessions", column: "transcript_text", definition: "TEXT", in: db)
        try addColumnIfNeeded(table: "sessions", column: "transcript_file_path", definition: "TEXT", in: db)
        try addColumnIfNeeded(table: "sessions", column: "meeting_context_profile", definition: "TEXT NOT NULL DEFAULT 'general'", in: db)
        try addColumnIfNeeded(table: "sessions", column: "transcription_status", definition: "TEXT NOT NULL DEFAULT 'idle'", in: db)
        try addColumnIfNeeded(table: "sessions", column: "transcription_error", definition: "TEXT", in: db)
        try addColumnIfNeeded(table: "sessions", column: "transcription_duration_seconds", definition: "REAL", in: db)
        try addColumnIfNeeded(table: "sessions", column: "utterance_count", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded(table: "sessions", column: "topic_count", definition: "INTEGER NOT NULL DEFAULT 0", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS topics (
            id TEXT PRIMARY KEY NOT NULL,
            session_id TEXT NOT NULL,
            started_at REAL NOT NULL,
            ended_at REAL,
            status TEXT NOT NULL,
            summary_text TEXT,
            summary_status TEXT NOT NULL DEFAULT 'idle',
            summary_error TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_topics_session_started_at ON topics(session_id, started_at);", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS utterances (
            id TEXT PRIMARY KEY NOT NULL,
            session_id TEXT NOT NULL,
            topic_id TEXT,
            started_at REAL NOT NULL,
            ended_at REAL,
            duration_seconds REAL,
            audio_path TEXT,
            transcript_text TEXT,
            transcript_file_path TEXT,
            transcription_status TEXT NOT NULL DEFAULT 'idle',
            transcription_error TEXT,
            transcription_duration_seconds REAL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
            FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE SET NULL
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_utterances_session_started_at ON utterances(session_id, started_at);", in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_utterances_topic_started_at ON utterances(topic_id, started_at);", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS recording_artifacts (
            id TEXT PRIMARY KEY NOT NULL,
            utterance_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            byte_size INTEGER NOT NULL,
            duration_seconds REAL NOT NULL,
            sample_rate INTEGER NOT NULL,
            channel_count INTEGER NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY (utterance_id) REFERENCES utterances(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_recording_artifacts_utterance_created_at ON recording_artifacts(utterance_id, created_at);", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS transcription_jobs (
            id TEXT PRIMARY KEY NOT NULL,
            utterance_id TEXT NOT NULL,
            recording_artifact_id TEXT NOT NULL,
            working_directory_path TEXT NOT NULL,
            command TEXT NOT NULL,
            arguments_json TEXT NOT NULL,
            model_identifier TEXT NOT NULL,
            language TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            started_at REAL,
            ended_at REAL,
            stdout_file_path TEXT,
            stderr_file_path TEXT,
            exit_code INTEGER,
            output_file_names_json TEXT NOT NULL DEFAULT '[]',
            failure_message TEXT,
            FOREIGN KEY (utterance_id) REFERENCES utterances(id) ON DELETE CASCADE,
            FOREIGN KEY (recording_artifact_id) REFERENCES recording_artifacts(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_transcription_jobs_utterance_created_at ON transcription_jobs(utterance_id, created_at);", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS transcript_artifacts (
            id TEXT PRIMARY KEY NOT NULL,
            utterance_id TEXT NOT NULL,
            transcription_job_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            text TEXT NOT NULL,
            model_identifier TEXT NOT NULL,
            language TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY (utterance_id) REFERENCES utterances(id) ON DELETE CASCADE,
            FOREIGN KEY (transcription_job_id) REFERENCES transcription_jobs(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_transcript_artifacts_utterance_created_at ON transcript_artifacts(utterance_id, created_at);", in: db)
    }

    public func listSessions() throws -> [Session] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id,
            started_at,
            ended_at,
            status,
            audio_path,
            duration_seconds,
            transcript_text,
            transcript_file_path,
            meeting_context_profile,
            transcription_status,
            transcription_error,
            transcription_duration_seconds,
            utterance_count,
            topic_count
        FROM sessions
        ORDER BY started_at DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        var sessions: [Session] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let session = decodeSession(from: statement) else {
                continue
            }
            sessions.append(session)
        }

        return sessions
    }

    public func insertSession(_ session: Session) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO sessions (
            id,
            started_at,
            ended_at,
            status,
            audio_path,
            duration_seconds,
            transcript_text,
            transcript_file_path,
            meeting_context_profile,
            transcription_status,
            transcription_error,
            transcription_duration_seconds,
            utterance_count,
            topic_count
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(session: session, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateSession(_ session: Session) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE sessions
        SET
            started_at = ?,
            ended_at = ?,
            status = ?,
            audio_path = ?,
            duration_seconds = ?,
            transcript_text = ?,
            transcript_file_path = ?,
            meeting_context_profile = ?,
            transcription_status = ?,
            transcription_error = ?,
            transcription_duration_seconds = ?,
            utterance_count = ?,
            topic_count = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(session: session, to: statement, includeIDAt: 14)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listTopics(sessionID: UUID) throws -> [Topic] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id,
            session_id,
            started_at,
            ended_at,
            status,
            summary_text,
            summary_status,
            summary_error
        FROM topics
        WHERE session_id = ?
        ORDER BY started_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID.uuidString, -1, transientDestructor)

        var topics: [Topic] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let topic = decodeTopic(from: statement) else {
                continue
            }
            topics.append(topic)
        }

        return topics
    }

    public func insertTopic(_ topic: Topic) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO topics (
            id,
            session_id,
            started_at,
            ended_at,
            status,
            summary_text,
            summary_status,
            summary_error
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(topic: topic, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateTopic(_ topic: Topic) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE topics
        SET
            session_id = ?,
            started_at = ?,
            ended_at = ?,
            status = ?,
            summary_text = ?,
            summary_status = ?,
            summary_error = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(topic: topic, to: statement, includeIDAt: 8)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listUtterances(sessionID: UUID) throws -> [Utterance] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id,
            session_id,
            topic_id,
            started_at,
            ended_at,
            duration_seconds,
            audio_path,
            transcript_text,
            transcript_file_path,
            transcription_status,
            transcription_error,
            transcription_duration_seconds
        FROM utterances
        WHERE session_id = ?
        ORDER BY started_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID.uuidString, -1, transientDestructor)

        var utterances: [Utterance] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let utterance = decodeUtterance(from: statement) else {
                continue
            }
            utterances.append(utterance)
        }

        return utterances
    }

    public func listUtterances(topicID: UUID) throws -> [Utterance] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id, session_id, topic_id, started_at, ended_at, duration_seconds,
            audio_path, transcript_text, transcript_file_path, transcription_status,
            transcription_error, transcription_duration_seconds
        FROM utterances
        WHERE topic_id = ?
        ORDER BY started_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, topicID.uuidString, -1, transientDestructor)

        var utterances: [Utterance] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let utterance = decodeUtterance(from: statement) else { continue }
            utterances.append(utterance)
        }

        return utterances
    }

    public func insertUtterance(_ utterance: Utterance) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO utterances (
            id,
            session_id,
            topic_id,
            started_at,
            ended_at,
            duration_seconds,
            audio_path,
            transcript_text,
            transcript_file_path,
            transcription_status,
            transcription_error,
            transcription_duration_seconds
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(utterance: utterance, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateUtterance(_ utterance: Utterance) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE utterances
        SET
            session_id = ?,
            topic_id = ?,
            started_at = ?,
            ended_at = ?,
            duration_seconds = ?,
            audio_path = ?,
            transcript_text = ?,
            transcript_file_path = ?,
            transcription_status = ?,
            transcription_error = ?,
            transcription_duration_seconds = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(utterance: utterance, to: statement, includeIDAt: 12)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listRecordingArtifacts(utteranceID: UUID) throws -> [RecordingArtifactMetadata] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id,
            utterance_id,
            file_path,
            byte_size,
            duration_seconds,
            sample_rate,
            channel_count,
            created_at
        FROM recording_artifacts
        WHERE utterance_id = ?
        ORDER BY created_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, utteranceID.uuidString, -1, transientDestructor)

        var artifacts: [RecordingArtifactMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let artifact = decodeRecordingArtifact(from: statement) else {
                continue
            }
            artifacts.append(artifact)
        }

        return artifacts
    }

    public func insertRecordingArtifact(_ artifact: RecordingArtifactMetadata) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO recording_artifacts (
            id,
            utterance_id,
            file_path,
            byte_size,
            duration_seconds,
            sample_rate,
            channel_count,
            created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(recordingArtifact: artifact, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateRecordingArtifact(_ artifact: RecordingArtifactMetadata) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE recording_artifacts
        SET
            utterance_id = ?,
            file_path = ?,
            byte_size = ?,
            duration_seconds = ?,
            sample_rate = ?,
            channel_count = ?,
            created_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(recordingArtifact: artifact, to: statement, includeIDAt: 8)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listTranscriptionJobs(utteranceID: UUID) throws -> [TranscriptionJob] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id,
            utterance_id,
            recording_artifact_id,
            working_directory_path,
            command,
            arguments_json,
            model_identifier,
            language,
            status,
            created_at,
            started_at,
            ended_at,
            stdout_file_path,
            stderr_file_path,
            exit_code,
            output_file_names_json,
            failure_message
        FROM transcription_jobs
        WHERE utterance_id = ?
        ORDER BY created_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, utteranceID.uuidString, -1, transientDestructor)

        var jobs: [TranscriptionJob] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let job = try decodeTranscriptionJob(from: statement) else {
                continue
            }
            jobs.append(job)
        }

        return jobs
    }

    public func insertTranscriptionJob(_ job: TranscriptionJob) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO transcription_jobs (
            id,
            utterance_id,
            recording_artifact_id,
            working_directory_path,
            command,
            arguments_json,
            model_identifier,
            language,
            status,
            created_at,
            started_at,
            ended_at,
            stdout_file_path,
            stderr_file_path,
            exit_code,
            output_file_names_json,
            failure_message
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        try bind(transcriptionJob: job, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateTranscriptionJob(_ job: TranscriptionJob) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE transcription_jobs
        SET
            utterance_id = ?,
            recording_artifact_id = ?,
            working_directory_path = ?,
            command = ?,
            arguments_json = ?,
            model_identifier = ?,
            language = ?,
            status = ?,
            created_at = ?,
            started_at = ?,
            ended_at = ?,
            stdout_file_path = ?,
            stderr_file_path = ?,
            exit_code = ?,
            output_file_names_json = ?,
            failure_message = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        try bind(transcriptionJob: job, to: statement, includeIDAt: 17)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listTranscriptArtifacts(utteranceID: UUID) throws -> [TranscriptArtifactMetadata] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id,
            utterance_id,
            transcription_job_id,
            file_path,
            text,
            model_identifier,
            language,
            created_at
        FROM transcript_artifacts
        WHERE utterance_id = ?
        ORDER BY created_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, utteranceID.uuidString, -1, transientDestructor)

        var artifacts: [TranscriptArtifactMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let artifact = decodeTranscriptArtifact(from: statement) else {
                continue
            }
            artifacts.append(artifact)
        }

        return artifacts
    }

    public func insertTranscriptArtifact(_ artifact: TranscriptArtifactMetadata) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO transcript_artifacts (
            id,
            utterance_id,
            transcription_job_id,
            file_path,
            text,
            model_identifier,
            language,
            created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(transcriptArtifact: artifact, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateTranscriptArtifact(_ artifact: TranscriptArtifactMetadata) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE transcript_artifacts
        SET
            utterance_id = ?,
            transcription_job_id = ?,
            file_path = ?,
            text = ?,
            model_identifier = ?,
            language = ?,
            created_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(transcriptArtifact: artifact, to: statement, includeIDAt: 8)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    private func bind(session: Session, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, session.id.uuidString, -1, transientDestructor)
            sqlite3_bind_double(statement, 2, session.startedAt.timeIntervalSince1970)
            bind(date: session.endedAt, to: statement, index: 3)
            sqlite3_bind_text(statement, 4, session.status.rawValue, -1, transientDestructor)
            bind(text: session.audioFilePath, to: statement, index: 5)
            bind(double: session.durationSeconds, to: statement, index: 6)
            bind(text: session.transcriptText, to: statement, index: 7)
            bind(text: session.transcriptFilePath, to: statement, index: 8)
            sqlite3_bind_text(statement, 9, session.meetingContextProfile.rawValue, -1, transientDestructor)
            sqlite3_bind_text(statement, 10, session.transcriptionStatus.rawValue, -1, transientDestructor)
            bind(text: session.transcriptionError, to: statement, index: 11)
            bind(double: session.transcriptionDurationSeconds, to: statement, index: 12)
            sqlite3_bind_int64(statement, 13, sqlite3_int64(session.utteranceCount))
            sqlite3_bind_int64(statement, 14, sqlite3_int64(session.topicCount))
            return
        }

        let baseIndex: Int32 = 1
        sqlite3_bind_double(statement, baseIndex, session.startedAt.timeIntervalSince1970)
        bind(date: session.endedAt, to: statement, index: baseIndex + 1)
        sqlite3_bind_text(statement, baseIndex + 2, session.status.rawValue, -1, transientDestructor)
        bind(text: session.audioFilePath, to: statement, index: baseIndex + 3)
        bind(double: session.durationSeconds, to: statement, index: baseIndex + 4)
        bind(text: session.transcriptText, to: statement, index: baseIndex + 5)
        bind(text: session.transcriptFilePath, to: statement, index: baseIndex + 6)
        sqlite3_bind_text(statement, baseIndex + 7, session.meetingContextProfile.rawValue, -1, transientDestructor)
        sqlite3_bind_text(statement, baseIndex + 8, session.transcriptionStatus.rawValue, -1, transientDestructor)
        bind(text: session.transcriptionError, to: statement, index: baseIndex + 9)
        bind(double: session.transcriptionDurationSeconds, to: statement, index: baseIndex + 10)
        sqlite3_bind_int64(statement, baseIndex + 11, sqlite3_int64(session.utteranceCount))
        sqlite3_bind_int64(statement, baseIndex + 12, sqlite3_int64(session.topicCount))
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), session.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(topic: Topic, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, topic.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, topic.sessionID.uuidString, -1, transientDestructor)
            sqlite3_bind_double(statement, 3, topic.startedAt.timeIntervalSince1970)
            bind(date: topic.endedAt, to: statement, index: 4)
            sqlite3_bind_text(statement, 5, topic.status.rawValue, -1, transientDestructor)
            bind(text: topic.summaryText, to: statement, index: 6)
            sqlite3_bind_text(statement, 7, topic.summaryStatus.rawValue, -1, transientDestructor)
            bind(text: topic.summaryError, to: statement, index: 8)
            return
        }

        sqlite3_bind_text(statement, 1, topic.sessionID.uuidString, -1, transientDestructor)
        sqlite3_bind_double(statement, 2, topic.startedAt.timeIntervalSince1970)
        bind(date: topic.endedAt, to: statement, index: 3)
        sqlite3_bind_text(statement, 4, topic.status.rawValue, -1, transientDestructor)
        bind(text: topic.summaryText, to: statement, index: 5)
        sqlite3_bind_text(statement, 6, topic.summaryStatus.rawValue, -1, transientDestructor)
        bind(text: topic.summaryError, to: statement, index: 7)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), topic.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(utterance: Utterance, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, utterance.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, utterance.sessionID.uuidString, -1, transientDestructor)
            bind(uuid: utterance.topicID, to: statement, index: 3)
            sqlite3_bind_double(statement, 4, utterance.startedAt.timeIntervalSince1970)
            bind(date: utterance.endedAt, to: statement, index: 5)
            bind(double: utterance.durationSeconds, to: statement, index: 6)
            bind(text: utterance.audioFilePath, to: statement, index: 7)
            bind(text: utterance.transcriptText, to: statement, index: 8)
            bind(text: utterance.transcriptFilePath, to: statement, index: 9)
            sqlite3_bind_text(statement, 10, utterance.transcriptionStatus.rawValue, -1, transientDestructor)
            bind(text: utterance.transcriptionError, to: statement, index: 11)
            bind(double: utterance.transcriptionDurationSeconds, to: statement, index: 12)
            return
        }

        sqlite3_bind_text(statement, 1, utterance.sessionID.uuidString, -1, transientDestructor)
        bind(uuid: utterance.topicID, to: statement, index: 2)
        sqlite3_bind_double(statement, 3, utterance.startedAt.timeIntervalSince1970)
        bind(date: utterance.endedAt, to: statement, index: 4)
        bind(double: utterance.durationSeconds, to: statement, index: 5)
        bind(text: utterance.audioFilePath, to: statement, index: 6)
        bind(text: utterance.transcriptText, to: statement, index: 7)
        bind(text: utterance.transcriptFilePath, to: statement, index: 8)
        sqlite3_bind_text(statement, 9, utterance.transcriptionStatus.rawValue, -1, transientDestructor)
        bind(text: utterance.transcriptionError, to: statement, index: 10)
        bind(double: utterance.transcriptionDurationSeconds, to: statement, index: 11)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), utterance.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(recordingArtifact: RecordingArtifactMetadata, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, recordingArtifact.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, recordingArtifact.utteranceID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, recordingArtifact.filePath, -1, transientDestructor)
            sqlite3_bind_int64(statement, 4, recordingArtifact.byteSize)
            sqlite3_bind_double(statement, 5, recordingArtifact.durationSeconds)
            sqlite3_bind_int64(statement, 6, sqlite3_int64(recordingArtifact.sampleRate))
            sqlite3_bind_int64(statement, 7, sqlite3_int64(recordingArtifact.channelCount))
            sqlite3_bind_double(statement, 8, recordingArtifact.createdAt.timeIntervalSince1970)
            return
        }

        sqlite3_bind_text(statement, 1, recordingArtifact.utteranceID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, recordingArtifact.filePath, -1, transientDestructor)
        sqlite3_bind_int64(statement, 3, recordingArtifact.byteSize)
        sqlite3_bind_double(statement, 4, recordingArtifact.durationSeconds)
        sqlite3_bind_int64(statement, 5, sqlite3_int64(recordingArtifact.sampleRate))
        sqlite3_bind_int64(statement, 6, sqlite3_int64(recordingArtifact.channelCount))
        sqlite3_bind_double(statement, 7, recordingArtifact.createdAt.timeIntervalSince1970)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), recordingArtifact.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(transcriptArtifact: TranscriptArtifactMetadata, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, transcriptArtifact.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, transcriptArtifact.utteranceID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, transcriptArtifact.transcriptionJobID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 4, transcriptArtifact.filePath, -1, transientDestructor)
            sqlite3_bind_text(statement, 5, transcriptArtifact.text, -1, transientDestructor)
            sqlite3_bind_text(statement, 6, transcriptArtifact.modelIdentifier, -1, transientDestructor)
            sqlite3_bind_text(statement, 7, transcriptArtifact.language, -1, transientDestructor)
            sqlite3_bind_double(statement, 8, transcriptArtifact.createdAt.timeIntervalSince1970)
            return
        }

        sqlite3_bind_text(statement, 1, transcriptArtifact.utteranceID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, transcriptArtifact.transcriptionJobID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, transcriptArtifact.filePath, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, transcriptArtifact.text, -1, transientDestructor)
        sqlite3_bind_text(statement, 5, transcriptArtifact.modelIdentifier, -1, transientDestructor)
        sqlite3_bind_text(statement, 6, transcriptArtifact.language, -1, transientDestructor)
        sqlite3_bind_double(statement, 7, transcriptArtifact.createdAt.timeIntervalSince1970)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), transcriptArtifact.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(transcriptionJob: TranscriptionJob, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) throws {
        let argumentsJSON = try encodeStringArray(transcriptionJob.arguments)
        let outputFileNamesJSON = try encodeStringArray(transcriptionJob.outputFileNames)

        if idIndex == nil {
            sqlite3_bind_text(statement, 1, transcriptionJob.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, transcriptionJob.utteranceID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, transcriptionJob.recordingArtifactID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 4, transcriptionJob.workingDirectoryPath, -1, transientDestructor)
            sqlite3_bind_text(statement, 5, transcriptionJob.command, -1, transientDestructor)
            sqlite3_bind_text(statement, 6, argumentsJSON, -1, transientDestructor)
            sqlite3_bind_text(statement, 7, transcriptionJob.modelIdentifier, -1, transientDestructor)
            sqlite3_bind_text(statement, 8, transcriptionJob.language, -1, transientDestructor)
            sqlite3_bind_text(statement, 9, transcriptionJob.status.rawValue, -1, transientDestructor)
            sqlite3_bind_double(statement, 10, transcriptionJob.createdAt.timeIntervalSince1970)
            bind(date: transcriptionJob.startedAt, to: statement, index: 11)
            bind(date: transcriptionJob.endedAt, to: statement, index: 12)
            bind(text: transcriptionJob.stdoutFilePath, to: statement, index: 13)
            bind(text: transcriptionJob.stderrFilePath, to: statement, index: 14)
            bind(int32: transcriptionJob.exitCode, to: statement, index: 15)
            sqlite3_bind_text(statement, 16, outputFileNamesJSON, -1, transientDestructor)
            bind(text: transcriptionJob.failureMessage, to: statement, index: 17)
            return
        }

        sqlite3_bind_text(statement, 1, transcriptionJob.utteranceID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, transcriptionJob.recordingArtifactID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, transcriptionJob.workingDirectoryPath, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, transcriptionJob.command, -1, transientDestructor)
        sqlite3_bind_text(statement, 5, argumentsJSON, -1, transientDestructor)
        sqlite3_bind_text(statement, 6, transcriptionJob.modelIdentifier, -1, transientDestructor)
        sqlite3_bind_text(statement, 7, transcriptionJob.language, -1, transientDestructor)
        sqlite3_bind_text(statement, 8, transcriptionJob.status.rawValue, -1, transientDestructor)
        sqlite3_bind_double(statement, 9, transcriptionJob.createdAt.timeIntervalSince1970)
        bind(date: transcriptionJob.startedAt, to: statement, index: 10)
        bind(date: transcriptionJob.endedAt, to: statement, index: 11)
        bind(text: transcriptionJob.stdoutFilePath, to: statement, index: 12)
        bind(text: transcriptionJob.stderrFilePath, to: statement, index: 13)
        bind(int32: transcriptionJob.exitCode, to: statement, index: 14)
        sqlite3_bind_text(statement, 15, outputFileNamesJSON, -1, transientDestructor)
        bind(text: transcriptionJob.failureMessage, to: statement, index: 16)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), transcriptionJob.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(text: String?, to statement: OpaquePointer?, index: Int32) {
        if let text {
            sqlite3_bind_text(statement, index, text, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(double: Double?, to statement: OpaquePointer?, index: Int32) {
        if let double {
            sqlite3_bind_double(statement, index, double)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(date: Date?, to statement: OpaquePointer?, index: Int32) {
        if let date {
            sqlite3_bind_double(statement, index, date.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(uuid: UUID?, to statement: OpaquePointer?, index: Int32) {
        if let uuid {
            sqlite3_bind_text(statement, index, uuid.uuidString, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(int32 value: Int32?, to statement: OpaquePointer?, index: Int32) {
        if let value {
            sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func decodeSession(from statement: OpaquePointer?) -> Session? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let statusCString = sqlite3_column_text(statement, 3),
            let transcriptionStatusCString = sqlite3_column_text(statement, 9)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let status = Session.Status(rawValue: String(cString: statusCString)),
            let transcriptionStatus = Session.TranscriptionStatus(rawValue: String(cString: transcriptionStatusCString))
        else {
            return nil
        }

        let contextProfile = textValue(from: statement, index: 8)
            .flatMap(Session.MeetingContextProfile.init(rawValue:))
            ?? .general

        return Session(
            id: id,
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            endedAt: dateValue(from: statement, index: 2),
            status: status,
            audioFilePath: textValue(from: statement, index: 4),
            durationSeconds: doubleValue(from: statement, index: 5),
            transcriptText: textValue(from: statement, index: 6),
            transcriptFilePath: textValue(from: statement, index: 7),
            meetingContextProfile: contextProfile,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: textValue(from: statement, index: 10),
            transcriptionDurationSeconds: doubleValue(from: statement, index: 11),
            utteranceCount: intValue(from: statement, index: 12) ?? 0,
            topicCount: intValue(from: statement, index: 13) ?? 0
        )
    }

    private func decodeTopic(from statement: OpaquePointer?) -> Topic? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let sessionIDCString = sqlite3_column_text(statement, 1),
            let statusCString = sqlite3_column_text(statement, 4),
            let summaryStatusCString = sqlite3_column_text(statement, 6)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let sessionID = UUID(uuidString: String(cString: sessionIDCString)),
            let status = Topic.Status(rawValue: String(cString: statusCString)),
            let summaryStatus = Topic.SummaryStatus(rawValue: String(cString: summaryStatusCString))
        else {
            return nil
        }

        return Topic(
            id: id,
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            endedAt: dateValue(from: statement, index: 3),
            status: status,
            summaryText: textValue(from: statement, index: 5),
            summaryStatus: summaryStatus,
            summaryError: textValue(from: statement, index: 7)
        )
    }

    private func decodeUtterance(from statement: OpaquePointer?) -> Utterance? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let sessionIDCString = sqlite3_column_text(statement, 1),
            let transcriptionStatusCString = sqlite3_column_text(statement, 9)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let sessionID = UUID(uuidString: String(cString: sessionIDCString)),
            let transcriptionStatus = Utterance.TranscriptionStatus(rawValue: String(cString: transcriptionStatusCString))
        else {
            return nil
        }

        return Utterance(
            id: id,
            sessionID: sessionID,
            topicID: uuidValue(from: statement, index: 2),
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            endedAt: dateValue(from: statement, index: 4),
            durationSeconds: doubleValue(from: statement, index: 5),
            audioFilePath: textValue(from: statement, index: 6),
            transcriptText: textValue(from: statement, index: 7),
            transcriptFilePath: textValue(from: statement, index: 8),
            transcriptionStatus: transcriptionStatus,
            transcriptionError: textValue(from: statement, index: 10),
            transcriptionDurationSeconds: doubleValue(from: statement, index: 11)
        )
    }

    private func decodeRecordingArtifact(from statement: OpaquePointer?) -> RecordingArtifactMetadata? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let utteranceIDCString = sqlite3_column_text(statement, 1),
            let filePathCString = sqlite3_column_text(statement, 2)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let utteranceID = UUID(uuidString: String(cString: utteranceIDCString))
        else {
            return nil
        }

        return RecordingArtifactMetadata(
            id: id,
            utteranceID: utteranceID,
            filePath: String(cString: filePathCString),
            byteSize: sqlite3_column_int64(statement, 3),
            durationSeconds: sqlite3_column_double(statement, 4),
            sampleRate: Int(sqlite3_column_int64(statement, 5)),
            channelCount: Int(sqlite3_column_int64(statement, 6)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
        )
    }

    private func decodeTranscriptArtifact(from statement: OpaquePointer?) -> TranscriptArtifactMetadata? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let utteranceIDCString = sqlite3_column_text(statement, 1),
            let transcriptionJobIDCString = sqlite3_column_text(statement, 2),
            let filePathCString = sqlite3_column_text(statement, 3),
            let textCString = sqlite3_column_text(statement, 4),
            let modelIdentifierCString = sqlite3_column_text(statement, 5),
            let languageCString = sqlite3_column_text(statement, 6)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let utteranceID = UUID(uuidString: String(cString: utteranceIDCString)),
            let transcriptionJobID = UUID(uuidString: String(cString: transcriptionJobIDCString))
        else {
            return nil
        }

        return TranscriptArtifactMetadata(
            id: id,
            utteranceID: utteranceID,
            transcriptionJobID: transcriptionJobID,
            filePath: String(cString: filePathCString),
            text: String(cString: textCString),
            modelIdentifier: String(cString: modelIdentifierCString),
            language: String(cString: languageCString),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
        )
    }

    private func decodeTranscriptionJob(from statement: OpaquePointer?) throws -> TranscriptionJob? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let utteranceIDCString = sqlite3_column_text(statement, 1),
            let recordingArtifactIDCString = sqlite3_column_text(statement, 2),
            let workingDirectoryCString = sqlite3_column_text(statement, 3),
            let commandCString = sqlite3_column_text(statement, 4),
            let argumentsJSONCString = sqlite3_column_text(statement, 5),
            let modelIdentifierCString = sqlite3_column_text(statement, 6),
            let languageCString = sqlite3_column_text(statement, 7),
            let statusCString = sqlite3_column_text(statement, 8),
            let outputFileNamesJSONCString = sqlite3_column_text(statement, 15)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let utteranceID = UUID(uuidString: String(cString: utteranceIDCString)),
            let recordingArtifactID = UUID(uuidString: String(cString: recordingArtifactIDCString)),
            let status = TranscriptionJob.Status(rawValue: String(cString: statusCString))
        else {
            return nil
        }

        return TranscriptionJob(
            id: id,
            utteranceID: utteranceID,
            recordingArtifactID: recordingArtifactID,
            workingDirectoryPath: String(cString: workingDirectoryCString),
            command: String(cString: commandCString),
            arguments: try decodeStringArray(String(cString: argumentsJSONCString)),
            modelIdentifier: String(cString: modelIdentifierCString),
            language: String(cString: languageCString),
            status: status,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            startedAt: dateValue(from: statement, index: 10),
            endedAt: dateValue(from: statement, index: 11),
            stdoutFilePath: textValue(from: statement, index: 12),
            stderrFilePath: textValue(from: statement, index: 13),
            exitCode: int32Value(from: statement, index: 14),
            outputFileNames: try decodeStringArray(String(cString: outputFileNamesJSONCString)),
            failureMessage: textValue(from: statement, index: 16)
        )
    }

    private func textValue(from statement: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func doubleValue(from statement: OpaquePointer?, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }

    private func dateValue(from statement: OpaquePointer?, index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private func intValue(from statement: OpaquePointer?, index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int64(statement, index))
    }

    private func int32Value(from statement: OpaquePointer?, index: Int32) -> Int32? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int32(sqlite3_column_int64(statement, index))
    }

    private func uuidValue(from statement: OpaquePointer?, index: Int32) -> UUID? {
        guard let string = textValue(from: statement, index: index) else {
            return nil
        }
        return UUID(uuidString: string)
    }

    private func encodeStringArray(_ values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SQLiteSessionStoreError.encoding(message: "JSON encoding failed.")
        }
        return string
    }

    private func decodeStringArray(_ string: String) throws -> [String] {
        let data = Data(string.utf8)
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw SQLiteSessionStoreError.decoding(message: "JSON decoding failed: \(error.localizedDescription)")
        }
    }

    private func openDatabase() throws -> OpaquePointer? {
        var database: OpaquePointer?
        let result = sqlite3_open(databaseURL.path(percentEncoded: false), &database)
        guard result == SQLITE_OK else {
            let message = errorMessage(from: database)
            sqlite3_close(database)
            throw SQLiteSessionStoreError.open(message: message)
        }
        sqlite3_busy_timeout(database, 5_000)
        sqlite3_extended_result_codes(database, 1)
        try configureDatabase(database)
        return database
    }

    private func configureDatabase(_ database: OpaquePointer?) throws {
        try execute(sql: "PRAGMA journal_mode=WAL;", in: database)
        try execute(sql: "PRAGMA synchronous=NORMAL;", in: database)
        try execute(sql: "PRAGMA foreign_keys=ON;", in: database)
    }

    private func execute(sql: String, in database: OpaquePointer?) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.execute(message: errorMessage(from: database))
        }
    }

    private func addColumnIfNeeded(
        table: String,
        column: String,
        definition: String,
        in database: OpaquePointer?
    ) throws {
        let pragmaSQL = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, pragmaSQL, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: database))
        }
        defer { sqlite3_finalize(statement) }

        var hasColumn = false
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let columnCString = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: columnCString) == column {
                hasColumn = true
                break
            }
        }

        if !hasColumn {
            try execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);", in: database)
        }
    }

    private func errorMessage(from database: OpaquePointer?) -> String {
        guard let database else {
            return "Unknown SQLite error."
        }
        return String(cString: sqlite3_errmsg(database))
    }
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteSessionStoreError: Error, LocalizedError {
    case open(message: String)
    case prepare(message: String)
    case step(message: String)
    case execute(message: String)
    case encoding(message: String)
    case decoding(message: String)

    public var errorDescription: String? {
        switch self {
        case let .open(message),
             let .prepare(message),
             let .step(message),
             let .execute(message),
             let .encoding(message),
             let .decoding(message):
            return message
        }
    }
}
