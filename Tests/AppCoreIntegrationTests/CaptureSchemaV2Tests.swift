import Foundation
import SQLite3
import Testing
@testable import AppCore

struct CaptureSchemaV2Tests {
    @Test
    func migratesLegacyDatabaseToSchemaV2PreservingSharedDeviceRows() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .notDirectory)
            .appendingPathExtension("sqlite")
        let organizationID = UUID(uuidString: "00000000-0000-0000-0000-000000002001")!

        try withDatabase(at: databaseURL) { db in
            try executeRaw(sql: """
            CREATE TABLE organizations (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """, in: db)
            try executeRaw(sql: """
            INSERT INTO organizations (id, name, status, created_at)
            VALUES ('\(organizationID.uuidString)', 'Legacy Org', 'active', 1700000000.0);
            """, in: db)
            try executeRaw(sql: """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL,
                status TEXT NOT NULL
            );
            """, in: db)
            try executeRaw(sql: """
            INSERT INTO sessions (id, started_at, status)
            VALUES ('00000000-0000-0000-0000-000000002002', 1700000000.0, 'draft');
            """, in: db)
        }

        let store = SQLiteSessionStore(databaseURL: databaseURL)
        try store.initialize()

        try withDatabase(at: databaseURL) { db in
            let tables = try tableNames(in: db)
            #expect(!tables.contains("sessions"))
            #expect(!tables.contains("topics"))
            #expect(!tables.contains("recording_artifacts"))
            #expect(!tables.contains("transcription_jobs"))
            #expect(!tables.contains("transcript_artifacts"))
            #expect(tables.contains("capture_sessions"))
            #expect(tables.contains("utterances"))
            #expect(tables.contains("meeting_minutes"))
            #expect(try scalarInt(sql: "PRAGMA user_version;", in: db) == 2)
        }

        let organizations = try store.listOrganizations()
        #expect(organizations.count == 1)
        #expect(organizations.first?.id == organizationID)
        #expect(organizations.first?.name == "Legacy Org")

        #expect(try store.listCaptureSessions().isEmpty)
    }

    @Test
    func reinitializingV2DatabaseKeepsData() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .notDirectory)
            .appendingPathExtension("sqlite")

        let store = SQLiteSessionStore(databaseURL: databaseURL)
        try store.initialize()
        let fixture = try insertSharedDeviceFixture(store: store)
        let session = makeCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002011")!,
            fixture: fixture,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.insertCaptureSession(session)

        try store.initialize()

        #expect(try store.listCaptureSessions() == [session])
    }
}

private func withDatabase(at url: URL, _ body: (OpaquePointer?) throws -> Void) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path(percentEncoded: false), &db) == SQLITE_OK else {
        sqlite3_close(db)
        throw CaptureSchemaV2TestError.openFailed
    }
    defer { sqlite3_close(db) }
    try body(db)
}

private func executeRaw(sql: String, in db: OpaquePointer?) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
        throw CaptureSchemaV2TestError.executeFailed(String(cString: sqlite3_errmsg(db)))
    }
}

private func tableNames(in db: OpaquePointer?) throws -> Set<String> {
    let sql = "SELECT name FROM sqlite_master WHERE type = 'table';"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw CaptureSchemaV2TestError.executeFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }

    var names: Set<String> = []
    while sqlite3_step(statement) == SQLITE_ROW {
        guard let cString = sqlite3_column_text(statement, 0) else { continue }
        names.insert(String(cString: cString))
    }
    return names
}

private func scalarInt(sql: String, in db: OpaquePointer?) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw CaptureSchemaV2TestError.executeFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw CaptureSchemaV2TestError.executeFailed(String(cString: sqlite3_errmsg(db)))
    }
    return Int(sqlite3_column_int64(statement, 0))
}

private enum CaptureSchemaV2TestError: Error {
    case openFailed
    case executeFailed(String)
}
