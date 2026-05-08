import Foundation
import SQLite3

public final class SQLiteSessionStore: SessionStore, @unchecked Sendable {
    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func initialize() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY NOT NULL,
            started_at REAL NOT NULL,
            ended_at REAL,
            status TEXT NOT NULL,
            audio_path TEXT,
            duration_seconds REAL,
            transcript_text TEXT,
            transcript_file_path TEXT,
            transcription_status TEXT NOT NULL DEFAULT 'idle',
            transcription_error TEXT,
            transcription_duration_seconds REAL
        );
        """

        try execute(sql: sql, in: db)
        try addColumnIfNeeded(
            table: "sessions",
            column: "audio_path",
            definition: "TEXT",
            in: db
        )
        try addColumnIfNeeded(
            table: "sessions",
            column: "duration_seconds",
            definition: "REAL",
            in: db
        )
        try addColumnIfNeeded(
            table: "sessions",
            column: "transcript_text",
            definition: "TEXT",
            in: db
        )
        try addColumnIfNeeded(
            table: "sessions",
            column: "transcript_file_path",
            definition: "TEXT",
            in: db
        )
        try addColumnIfNeeded(
            table: "sessions",
            column: "transcription_status",
            definition: "TEXT NOT NULL DEFAULT 'idle'",
            in: db
        )
        try addColumnIfNeeded(
            table: "sessions",
            column: "transcription_error",
            definition: "TEXT",
            in: db
        )
        try addColumnIfNeeded(
            table: "sessions",
            column: "transcription_duration_seconds",
            definition: "REAL",
            in: db
        )
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
            transcription_status,
            transcription_error,
            transcription_duration_seconds
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
            guard
                let idCString = sqlite3_column_text(statement, 0),
                let statusCString = sqlite3_column_text(statement, 3),
                let transcriptionStatusCString = sqlite3_column_text(statement, 8)
            else {
                continue
            }

            let idString = String(cString: idCString)
            let statusString = String(cString: statusCString)
            let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let endedAt: Date? = sqlite3_column_type(statement, 2) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let audioFilePath = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil
                : String(cString: sqlite3_column_text(statement, 4))
            let durationSeconds: Double? = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(statement, 5)
            let transcriptText = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : String(cString: sqlite3_column_text(statement, 6))
            let transcriptFilePath = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil
                : String(cString: sqlite3_column_text(statement, 7))
            let transcriptionStatusString = String(cString: transcriptionStatusCString)
            let transcriptionError = sqlite3_column_type(statement, 9) == SQLITE_NULL
                ? nil
                : String(cString: sqlite3_column_text(statement, 9))
            let transcriptionDurationSeconds: Double? = sqlite3_column_type(statement, 10) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(statement, 10)

            guard
                let id = UUID(uuidString: idString),
                let status = Session.Status(rawValue: statusString),
                let transcriptionStatus = Session.TranscriptionStatus(rawValue: transcriptionStatusString)
            else {
                continue
            }

            sessions.append(
                Session(
                    id: id,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    status: status,
                    audioFilePath: audioFilePath,
                    durationSeconds: durationSeconds,
                    transcriptText: transcriptText,
                    transcriptFilePath: transcriptFilePath,
                    transcriptionStatus: transcriptionStatus,
                    transcriptionError: transcriptionError,
                    transcriptionDurationSeconds: transcriptionDurationSeconds
                )
            )
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
            transcription_status,
            transcription_error,
            transcription_duration_seconds
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, session.id.uuidString, -1, transientDestructor)
        sqlite3_bind_double(statement, 2, session.startedAt.timeIntervalSince1970)
        if let endedAt = session.endedAt {
            sqlite3_bind_double(statement, 3, endedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_text(statement, 4, session.status.rawValue, -1, transientDestructor)
        if let audioFilePath = session.audioFilePath {
            sqlite3_bind_text(statement, 5, audioFilePath, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        if let durationSeconds = session.durationSeconds {
            sqlite3_bind_double(statement, 6, durationSeconds)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        if let transcriptText = session.transcriptText {
            sqlite3_bind_text(statement, 7, transcriptText, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        if let transcriptFilePath = session.transcriptFilePath {
            sqlite3_bind_text(statement, 8, transcriptFilePath, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 8)
        }
        sqlite3_bind_text(statement, 9, session.transcriptionStatus.rawValue, -1, transientDestructor)
        if let transcriptionError = session.transcriptionError {
            sqlite3_bind_text(statement, 10, transcriptionError, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        if let transcriptionDurationSeconds = session.transcriptionDurationSeconds {
            sqlite3_bind_double(statement, 11, transcriptionDurationSeconds)
        } else {
            sqlite3_bind_null(statement, 11)
        }

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

        sqlite3_bind_double(statement, 1, session.startedAt.timeIntervalSince1970)
        if let endedAt = session.endedAt {
            sqlite3_bind_double(statement, 2, endedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        sqlite3_bind_text(statement, 3, session.status.rawValue, -1, transientDestructor)
        if let audioFilePath = session.audioFilePath {
            sqlite3_bind_text(statement, 4, audioFilePath, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        if let durationSeconds = session.durationSeconds {
            sqlite3_bind_double(statement, 5, durationSeconds)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        if let transcriptText = session.transcriptText {
            sqlite3_bind_text(statement, 6, transcriptText, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        if let transcriptFilePath = session.transcriptFilePath {
            sqlite3_bind_text(statement, 7, transcriptFilePath, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        sqlite3_bind_text(statement, 8, session.transcriptionStatus.rawValue, -1, transientDestructor)
        if let transcriptionError = session.transcriptionError {
            sqlite3_bind_text(statement, 9, transcriptionError, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 9)
        }
        if let transcriptionDurationSeconds = session.transcriptionDurationSeconds {
            sqlite3_bind_double(statement, 10, transcriptionDurationSeconds)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        sqlite3_bind_text(statement, 11, session.id.uuidString, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
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
            try execute(
                sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);",
                in: database
            )
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

    public var errorDescription: String? {
        switch self {
        case let .open(message),
             let .prepare(message),
             let .step(message),
             let .execute(message):
            return message
        }
    }
}
