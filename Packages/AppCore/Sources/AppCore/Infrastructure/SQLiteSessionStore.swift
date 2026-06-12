import Foundation
import SQLite3

public final class SQLiteSessionStore: OrganizationStore, WorkspaceStore, DeviceStore, AccountStore, OrganizationMembershipStore, AccessSessionStore, CaptureSessionStore, UtteranceStore, MeetingMinutesStore, @unchecked Sendable {
    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func initialize() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS organizations (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """, in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS workspaces (
            id TEXT PRIMARY KEY NOT NULL,
            organization_id TEXT NOT NULL,
            name TEXT NOT NULL,
            code TEXT,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_workspaces_organization_name ON workspaces(organization_id, name);", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS devices (
            id TEXT PRIMARY KEY NOT NULL,
            organization_id TEXT NOT NULL,
            workspace_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            location_label TEXT,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_devices_workspace_display_name ON devices(workspace_id, display_name);", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY NOT NULL,
            display_name TEXT NOT NULL,
            employee_code TEXT,
            status TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """, in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS organization_memberships (
            id TEXT PRIMARY KEY NOT NULL,
            organization_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            role TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS idx_organization_memberships_org_account_unique ON organization_memberships(organization_id, account_id);", in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_organization_memberships_account_org ON organization_memberships(account_id, organization_id);", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS access_sessions (
            id TEXT PRIMARY KEY NOT NULL,
            device_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            started_at REAL NOT NULL,
            ended_at REAL,
            status TEXT NOT NULL,
            authentication_method TEXT NOT NULL,
            FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE,
            FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_access_sessions_device_started_at ON access_sessions(device_id, started_at DESC);", in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_access_sessions_account_started_at ON access_sessions(account_id, started_at DESC);", in: db)

        if try userVersion(in: db) < 2 {
            try execute(sql: "DROP TABLE IF EXISTS transcript_artifacts;", in: db)
            try execute(sql: "DROP TABLE IF EXISTS transcription_jobs;", in: db)
            try execute(sql: "DROP TABLE IF EXISTS recording_artifacts;", in: db)
            try execute(sql: "DROP TABLE IF EXISTS utterances;", in: db)
            try execute(sql: "DROP TABLE IF EXISTS topics;", in: db)
            try execute(sql: "DROP TABLE IF EXISTS sessions;", in: db)
            try execute(sql: "PRAGMA user_version = 2;", in: db)
        }

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS capture_sessions (
            id TEXT PRIMARY KEY NOT NULL,
            organization_id TEXT NOT NULL,
            workspace_id TEXT NOT NULL,
            device_id TEXT NOT NULL,
            started_by_account_id TEXT NOT NULL,
            access_session_id TEXT,
            started_at REAL NOT NULL,
            ended_at REAL,
            status TEXT NOT NULL,
            meeting_context_profile TEXT NOT NULL DEFAULT 'general',
            audio_file_path TEXT,
            audio_duration_seconds REAL,
            utterance_count INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE,
            FOREIGN KEY (started_by_account_id) REFERENCES accounts(id) ON DELETE CASCADE,
            FOREIGN KEY (access_session_id) REFERENCES access_sessions(id) ON DELETE SET NULL
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_capture_sessions_started_at ON capture_sessions(started_at DESC);", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS utterances (
            id TEXT PRIMARY KEY NOT NULL,
            capture_session_id TEXT NOT NULL,
            started_at REAL NOT NULL,
            ended_at REAL NOT NULL,
            start_offset_seconds REAL NOT NULL,
            end_offset_seconds REAL NOT NULL,
            text TEXT NOT NULL,
            locale TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY (capture_session_id) REFERENCES capture_sessions(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_utterances_capture_session_started_at ON utterances(capture_session_id, started_at);", in: db)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS meeting_minutes (
            id TEXT PRIMARY KEY NOT NULL,
            capture_session_id TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL,
            markdown_text TEXT,
            error_message TEXT,
            model_identifier TEXT,
            created_at REAL NOT NULL,
            started_at REAL,
            completed_at REAL,
            FOREIGN KEY (capture_session_id) REFERENCES capture_sessions(id) ON DELETE CASCADE
        );
        """, in: db)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_meeting_minutes_status ON meeting_minutes(status);", in: db)
    }

    public func listOrganizations() throws -> [Organization] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, name, status, created_at
        FROM organizations
        ORDER BY created_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        var organizations: [Organization] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let organization = decodeOrganization(from: statement) else { continue }
            organizations.append(organization)
        }

        return organizations
    }

    public func insertOrganization(_ organization: Organization) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO organizations (id, name, status, created_at)
        VALUES (?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(organization: organization, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateOrganization(_ organization: Organization) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE organizations
        SET
            name = ?,
            status = ?,
            created_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(organization: organization, to: statement, includeIDAt: 4)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listWorkspaces() throws -> [Workspace] {
        try listWorkspaces(filteredBy: nil)
    }

    public func listWorkspaces(organizationID: UUID) throws -> [Workspace] {
        try listWorkspaces(filteredBy: organizationID)
    }

    public func insertWorkspace(_ workspace: Workspace) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO workspaces (id, organization_id, name, code, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(workspace: workspace, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateWorkspace(_ workspace: Workspace) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE workspaces
        SET
            organization_id = ?,
            name = ?,
            code = ?,
            status = ?,
            created_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(workspace: workspace, to: statement, includeIDAt: 6)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listDevices() throws -> [Device] {
        try listDevices(filteredBy: nil)
    }

    public func listDevices(workspaceID: UUID) throws -> [Device] {
        try listDevices(filteredBy: workspaceID)
    }

    public func insertDevice(_ device: Device) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO devices (
            id,
            organization_id,
            workspace_id,
            display_name,
            location_label,
            status,
            created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(device: device, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateDevice(_ device: Device) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE devices
        SET
            organization_id = ?,
            workspace_id = ?,
            display_name = ?,
            location_label = ?,
            status = ?,
            created_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(device: device, to: statement, includeIDAt: 7)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listAccounts() throws -> [Account] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, display_name, employee_code, status, created_at
        FROM accounts
        ORDER BY created_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        var accounts: [Account] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let account = decodeAccount(from: statement) else { continue }
            accounts.append(account)
        }

        return accounts
    }

    public func insertAccount(_ account: Account) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO accounts (id, display_name, employee_code, status, created_at)
        VALUES (?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(account: account, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateAccount(_ account: Account) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE accounts
        SET
            display_name = ?,
            employee_code = ?,
            status = ?,
            created_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(account: account, to: statement, includeIDAt: 5)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listOrganizationMemberships() throws -> [OrganizationMembership] {
        try listOrganizationMemberships(filteredByOrganizationID: nil, accountID: nil)
    }

    public func listOrganizationMemberships(organizationID: UUID) throws -> [OrganizationMembership] {
        try listOrganizationMemberships(filteredByOrganizationID: organizationID, accountID: nil)
    }

    public func listOrganizationMemberships(accountID: UUID) throws -> [OrganizationMembership] {
        try listOrganizationMemberships(filteredByOrganizationID: nil, accountID: accountID)
    }

    public func insertOrganizationMembership(_ membership: OrganizationMembership) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO organization_memberships (
            id,
            organization_id,
            account_id,
            role,
            status,
            created_at
        )
        VALUES (?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(organizationMembership: membership, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listAccessSessions() throws -> [AccessSession] {
        try listAccessSessions(filteredBy: nil)
    }

    public func listAccessSessions(deviceID: UUID) throws -> [AccessSession] {
        try listAccessSessions(filteredBy: deviceID)
    }

    public func insertAccessSession(_ session: AccessSession) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO access_sessions (
            id,
            device_id,
            account_id,
            started_at,
            ended_at,
            status,
            authentication_method
        )
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(accessSession: session, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateAccessSession(_ session: AccessSession) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE access_sessions
        SET
            device_id = ?,
            account_id = ?,
            started_at = ?,
            ended_at = ?,
            status = ?,
            authentication_method = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(accessSession: session, to: statement, includeIDAt: 7)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateOrganizationMembership(_ membership: OrganizationMembership) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE organization_memberships
        SET
            organization_id = ?,
            account_id = ?,
            role = ?,
            status = ?,
            created_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(organizationMembership: membership, to: statement, includeIDAt: 6)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func listCaptureSessions() throws -> [CaptureSession] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id,
            organization_id,
            workspace_id,
            device_id,
            started_by_account_id,
            access_session_id,
            started_at,
            ended_at,
            status,
            meeting_context_profile,
            audio_file_path,
            audio_duration_seconds,
            utterance_count
        FROM capture_sessions
        ORDER BY started_at DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        var sessions: [CaptureSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let session = decodeCaptureSession(from: statement) else { continue }
            sessions.append(session)
        }

        return sessions
    }

    public func insertCaptureSession(_ session: CaptureSession) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO capture_sessions (
            id,
            organization_id,
            workspace_id,
            device_id,
            started_by_account_id,
            access_session_id,
            started_at,
            ended_at,
            status,
            meeting_context_profile,
            audio_file_path,
            audio_duration_seconds,
            utterance_count
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(captureSession: session, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateCaptureSession(_ session: CaptureSession) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE capture_sessions
        SET
            organization_id = ?,
            workspace_id = ?,
            device_id = ?,
            started_by_account_id = ?,
            access_session_id = ?,
            started_at = ?,
            ended_at = ?,
            status = ?,
            meeting_context_profile = ?,
            audio_file_path = ?,
            audio_duration_seconds = ?,
            utterance_count = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(captureSession: session, to: statement, includeIDAt: 13)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func insertUtterance(_ utterance: Utterance) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO utterances (
            id,
            capture_session_id,
            started_at,
            ended_at,
            start_offset_seconds,
            end_offset_seconds,
            text,
            locale,
            created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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

    public func listUtterances(captureSessionID: UUID) throws -> [Utterance] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id,
            capture_session_id,
            started_at,
            ended_at,
            start_offset_seconds,
            end_offset_seconds,
            text,
            locale,
            created_at
        FROM utterances
        WHERE capture_session_id = ?
        ORDER BY started_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, captureSessionID.uuidString, -1, transientDestructor)

        var utterances: [Utterance] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let utterance = decodeUtterance(from: statement) else { continue }
            utterances.append(utterance)
        }

        return utterances
    }

    public func insertMeetingMinutes(_ minutes: MeetingMinutes) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO meeting_minutes (
            id,
            capture_session_id,
            status,
            markdown_text,
            error_message,
            model_identifier,
            created_at,
            started_at,
            completed_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(meetingMinutes: minutes, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func updateMeetingMinutes(_ minutes: MeetingMinutes) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE meeting_minutes
        SET
            capture_session_id = ?,
            status = ?,
            markdown_text = ?,
            error_message = ?,
            model_identifier = ?,
            created_at = ?,
            started_at = ?,
            completed_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        bind(meetingMinutes: minutes, to: statement, includeIDAt: 9)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: db))
        }
    }

    public func getMeetingMinutes(captureSessionID: UUID) throws -> MeetingMinutes? {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            id,
            capture_session_id,
            status,
            markdown_text,
            error_message,
            model_identifier,
            created_at,
            started_at,
            completed_at
        FROM meeting_minutes
        WHERE capture_session_id = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, captureSessionID.uuidString, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return decodeMeetingMinutes(from: statement)
    }

    public func listMeetingMinutes(statuses: [MeetingMinutes.Status]) throws -> [MeetingMinutes] {
        guard !statuses.isEmpty else {
            return []
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let placeholders = Array(repeating: "?", count: statuses.count).joined(separator: ", ")
        let sql = """
        SELECT
            id,
            capture_session_id,
            status,
            markdown_text,
            error_message,
            model_identifier,
            created_at,
            started_at,
            completed_at
        FROM meeting_minutes
        WHERE status IN (\(placeholders))
        ORDER BY created_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        for (offset, status) in statuses.enumerated() {
            sqlite3_bind_text(statement, Int32(offset + 1), status.rawValue, -1, transientDestructor)
        }

        var allMinutes: [MeetingMinutes] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let minutes = decodeMeetingMinutes(from: statement) else { continue }
            allMinutes.append(minutes)
        }

        return allMinutes
    }

    private func listWorkspaces(filteredBy organizationID: UUID?) throws -> [Workspace] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql: String
        if organizationID == nil {
            sql = """
            SELECT id, organization_id, name, code, status, created_at
            FROM workspaces
            ORDER BY created_at ASC;
            """
        } else {
            sql = """
            SELECT id, organization_id, name, code, status, created_at
            FROM workspaces
            WHERE organization_id = ?
            ORDER BY created_at ASC;
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        if let organizationID {
            sqlite3_bind_text(statement, 1, organizationID.uuidString, -1, transientDestructor)
        }

        var workspaces: [Workspace] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let workspace = decodeWorkspace(from: statement) else { continue }
            workspaces.append(workspace)
        }

        return workspaces
    }

    private func listDevices(filteredBy workspaceID: UUID?) throws -> [Device] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql: String
        if workspaceID == nil {
            sql = """
            SELECT id, organization_id, workspace_id, display_name, location_label, status, created_at
            FROM devices
            ORDER BY created_at ASC;
            """
        } else {
            sql = """
            SELECT id, organization_id, workspace_id, display_name, location_label, status, created_at
            FROM devices
            WHERE workspace_id = ?
            ORDER BY created_at ASC;
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        if let workspaceID {
            sqlite3_bind_text(statement, 1, workspaceID.uuidString, -1, transientDestructor)
        }

        var devices: [Device] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let device = decodeDevice(from: statement) else { continue }
            devices.append(device)
        }

        return devices
    }

    private func listOrganizationMemberships(
        filteredByOrganizationID organizationID: UUID?,
        accountID: UUID?
    ) throws -> [OrganizationMembership] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql: String
        if organizationID != nil {
            sql = """
            SELECT id, organization_id, account_id, role, status, created_at
            FROM organization_memberships
            WHERE organization_id = ?
            ORDER BY created_at ASC;
            """
        } else if accountID != nil {
            sql = """
            SELECT id, organization_id, account_id, role, status, created_at
            FROM organization_memberships
            WHERE account_id = ?
            ORDER BY created_at ASC;
            """
        } else {
            sql = """
            SELECT id, organization_id, account_id, role, status, created_at
            FROM organization_memberships
            ORDER BY created_at ASC;
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        if let organizationID {
            sqlite3_bind_text(statement, 1, organizationID.uuidString, -1, transientDestructor)
        } else if let accountID {
            sqlite3_bind_text(statement, 1, accountID.uuidString, -1, transientDestructor)
        }

        var memberships: [OrganizationMembership] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let membership = decodeOrganizationMembership(from: statement) else { continue }
            memberships.append(membership)
        }

        return memberships
    }

    private func listAccessSessions(filteredBy deviceID: UUID?) throws -> [AccessSession] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql: String
        if deviceID == nil {
            sql = """
            SELECT id, device_id, account_id, started_at, ended_at, status, authentication_method
            FROM access_sessions
            ORDER BY started_at DESC;
            """
        } else {
            sql = """
            SELECT id, device_id, account_id, started_at, ended_at, status, authentication_method
            FROM access_sessions
            WHERE device_id = ?
            ORDER BY started_at DESC;
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: db))
        }
        defer { sqlite3_finalize(statement) }

        if let deviceID {
            sqlite3_bind_text(statement, 1, deviceID.uuidString, -1, transientDestructor)
        }

        var sessions: [AccessSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let session = decodeAccessSession(from: statement) else { continue }
            sessions.append(session)
        }

        return sessions
    }

    private func bind(organization: Organization, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, organization.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, organization.name, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, organization.status.rawValue, -1, transientDestructor)
            sqlite3_bind_double(statement, 4, organization.createdAt.timeIntervalSince1970)
            return
        }

        sqlite3_bind_text(statement, 1, organization.name, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, organization.status.rawValue, -1, transientDestructor)
        sqlite3_bind_double(statement, 3, organization.createdAt.timeIntervalSince1970)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), organization.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(workspace: Workspace, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, workspace.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, workspace.organizationID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, workspace.name, -1, transientDestructor)
            bind(text: workspace.code, to: statement, index: 4)
            sqlite3_bind_text(statement, 5, workspace.status.rawValue, -1, transientDestructor)
            sqlite3_bind_double(statement, 6, workspace.createdAt.timeIntervalSince1970)
            return
        }

        sqlite3_bind_text(statement, 1, workspace.organizationID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, workspace.name, -1, transientDestructor)
        bind(text: workspace.code, to: statement, index: 3)
        sqlite3_bind_text(statement, 4, workspace.status.rawValue, -1, transientDestructor)
        sqlite3_bind_double(statement, 5, workspace.createdAt.timeIntervalSince1970)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), workspace.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(device: Device, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, device.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, device.organizationID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, device.workspaceID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 4, device.displayName, -1, transientDestructor)
            bind(text: device.locationLabel, to: statement, index: 5)
            sqlite3_bind_text(statement, 6, device.status.rawValue, -1, transientDestructor)
            sqlite3_bind_double(statement, 7, device.createdAt.timeIntervalSince1970)
            return
        }

        sqlite3_bind_text(statement, 1, device.organizationID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, device.workspaceID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, device.displayName, -1, transientDestructor)
        bind(text: device.locationLabel, to: statement, index: 4)
        sqlite3_bind_text(statement, 5, device.status.rawValue, -1, transientDestructor)
        sqlite3_bind_double(statement, 6, device.createdAt.timeIntervalSince1970)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), device.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(account: Account, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, account.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, account.displayName, -1, transientDestructor)
            bind(text: account.employeeCode, to: statement, index: 3)
            sqlite3_bind_text(statement, 4, account.status.rawValue, -1, transientDestructor)
            sqlite3_bind_double(statement, 5, account.createdAt.timeIntervalSince1970)
            return
        }

        sqlite3_bind_text(statement, 1, account.displayName, -1, transientDestructor)
        bind(text: account.employeeCode, to: statement, index: 2)
        sqlite3_bind_text(statement, 3, account.status.rawValue, -1, transientDestructor)
        sqlite3_bind_double(statement, 4, account.createdAt.timeIntervalSince1970)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), account.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(
        organizationMembership membership: OrganizationMembership,
        to statement: OpaquePointer?,
        includeIDAt idIndex: Int? = nil
    ) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, membership.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, membership.organizationID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, membership.accountID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 4, membership.role.rawValue, -1, transientDestructor)
            sqlite3_bind_text(statement, 5, membership.status.rawValue, -1, transientDestructor)
            sqlite3_bind_double(statement, 6, membership.createdAt.timeIntervalSince1970)
            return
        }

        sqlite3_bind_text(statement, 1, membership.organizationID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, membership.accountID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, membership.role.rawValue, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, membership.status.rawValue, -1, transientDestructor)
        sqlite3_bind_double(statement, 5, membership.createdAt.timeIntervalSince1970)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), membership.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(accessSession: AccessSession, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, accessSession.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, accessSession.deviceID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, accessSession.accountID.uuidString, -1, transientDestructor)
            sqlite3_bind_double(statement, 4, accessSession.startedAt.timeIntervalSince1970)
            bind(date: accessSession.endedAt, to: statement, index: 5)
            sqlite3_bind_text(statement, 6, accessSession.status.rawValue, -1, transientDestructor)
            sqlite3_bind_text(statement, 7, accessSession.authenticationMethod.rawValue, -1, transientDestructor)
            return
        }

        sqlite3_bind_text(statement, 1, accessSession.deviceID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, accessSession.accountID.uuidString, -1, transientDestructor)
        sqlite3_bind_double(statement, 3, accessSession.startedAt.timeIntervalSince1970)
        bind(date: accessSession.endedAt, to: statement, index: 4)
        sqlite3_bind_text(statement, 5, accessSession.status.rawValue, -1, transientDestructor)
        sqlite3_bind_text(statement, 6, accessSession.authenticationMethod.rawValue, -1, transientDestructor)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), accessSession.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(captureSession session: CaptureSession, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, session.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, session.organizationID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, session.workspaceID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 4, session.deviceID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 5, session.startedByAccountID.uuidString, -1, transientDestructor)
            bind(uuid: session.accessSessionID, to: statement, index: 6)
            sqlite3_bind_double(statement, 7, session.startedAt.timeIntervalSince1970)
            bind(date: session.endedAt, to: statement, index: 8)
            sqlite3_bind_text(statement, 9, session.status.rawValue, -1, transientDestructor)
            sqlite3_bind_text(statement, 10, session.meetingContextProfile.rawValue, -1, transientDestructor)
            bind(text: session.audioFilePath, to: statement, index: 11)
            bind(double: session.audioDurationSeconds, to: statement, index: 12)
            sqlite3_bind_int64(statement, 13, sqlite3_int64(session.utteranceCount))
            return
        }

        sqlite3_bind_text(statement, 1, session.organizationID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, session.workspaceID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, session.deviceID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, session.startedByAccountID.uuidString, -1, transientDestructor)
        bind(uuid: session.accessSessionID, to: statement, index: 5)
        sqlite3_bind_double(statement, 6, session.startedAt.timeIntervalSince1970)
        bind(date: session.endedAt, to: statement, index: 7)
        sqlite3_bind_text(statement, 8, session.status.rawValue, -1, transientDestructor)
        sqlite3_bind_text(statement, 9, session.meetingContextProfile.rawValue, -1, transientDestructor)
        bind(text: session.audioFilePath, to: statement, index: 10)
        bind(double: session.audioDurationSeconds, to: statement, index: 11)
        sqlite3_bind_int64(statement, 12, sqlite3_int64(session.utteranceCount))
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), session.id.uuidString, -1, transientDestructor)
        }
    }

    private func bind(utterance: Utterance, to statement: OpaquePointer?) {
        sqlite3_bind_text(statement, 1, utterance.id.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, utterance.captureSessionID.uuidString, -1, transientDestructor)
        sqlite3_bind_double(statement, 3, utterance.startedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, utterance.endedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, utterance.startOffsetSeconds)
        sqlite3_bind_double(statement, 6, utterance.endOffsetSeconds)
        sqlite3_bind_text(statement, 7, utterance.text, -1, transientDestructor)
        sqlite3_bind_text(statement, 8, utterance.locale, -1, transientDestructor)
        sqlite3_bind_double(statement, 9, utterance.createdAt.timeIntervalSince1970)
    }

    private func bind(meetingMinutes minutes: MeetingMinutes, to statement: OpaquePointer?, includeIDAt idIndex: Int? = nil) {
        if idIndex == nil {
            sqlite3_bind_text(statement, 1, minutes.id.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, minutes.captureSessionID.uuidString, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, minutes.status.rawValue, -1, transientDestructor)
            bind(text: minutes.markdownText, to: statement, index: 4)
            bind(text: minutes.errorMessage, to: statement, index: 5)
            bind(text: minutes.modelIdentifier, to: statement, index: 6)
            sqlite3_bind_double(statement, 7, minutes.createdAt.timeIntervalSince1970)
            bind(date: minutes.startedAt, to: statement, index: 8)
            bind(date: minutes.completedAt, to: statement, index: 9)
            return
        }

        sqlite3_bind_text(statement, 1, minutes.captureSessionID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, minutes.status.rawValue, -1, transientDestructor)
        bind(text: minutes.markdownText, to: statement, index: 3)
        bind(text: minutes.errorMessage, to: statement, index: 4)
        bind(text: minutes.modelIdentifier, to: statement, index: 5)
        sqlite3_bind_double(statement, 6, minutes.createdAt.timeIntervalSince1970)
        bind(date: minutes.startedAt, to: statement, index: 7)
        bind(date: minutes.completedAt, to: statement, index: 8)
        if let idIndex {
            sqlite3_bind_text(statement, Int32(idIndex), minutes.id.uuidString, -1, transientDestructor)
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

    private func decodeOrganization(from statement: OpaquePointer?) -> Organization? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let nameCString = sqlite3_column_text(statement, 1),
            let statusCString = sqlite3_column_text(statement, 2)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let status = Organization.Status(rawValue: String(cString: statusCString))
        else {
            return nil
        }

        return Organization(
            id: id,
            name: String(cString: nameCString),
            status: status,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        )
    }

    private func decodeWorkspace(from statement: OpaquePointer?) -> Workspace? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let organizationIDCString = sqlite3_column_text(statement, 1),
            let nameCString = sqlite3_column_text(statement, 2),
            let statusCString = sqlite3_column_text(statement, 4)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let organizationID = UUID(uuidString: String(cString: organizationIDCString)),
            let status = Workspace.Status(rawValue: String(cString: statusCString))
        else {
            return nil
        }

        return Workspace(
            id: id,
            organizationID: organizationID,
            name: String(cString: nameCString),
            code: textValue(from: statement, index: 3),
            status: status,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        )
    }

    private func decodeDevice(from statement: OpaquePointer?) -> Device? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let organizationIDCString = sqlite3_column_text(statement, 1),
            let workspaceIDCString = sqlite3_column_text(statement, 2),
            let displayNameCString = sqlite3_column_text(statement, 3),
            let statusCString = sqlite3_column_text(statement, 5)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let organizationID = UUID(uuidString: String(cString: organizationIDCString)),
            let workspaceID = UUID(uuidString: String(cString: workspaceIDCString)),
            let status = Device.Status(rawValue: String(cString: statusCString))
        else {
            return nil
        }

        return Device(
            id: id,
            organizationID: organizationID,
            workspaceID: workspaceID,
            displayName: String(cString: displayNameCString),
            locationLabel: textValue(from: statement, index: 4),
            status: status,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        )
    }

    private func decodeAccount(from statement: OpaquePointer?) -> Account? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let displayNameCString = sqlite3_column_text(statement, 1),
            let statusCString = sqlite3_column_text(statement, 3)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let status = Account.Status(rawValue: String(cString: statusCString))
        else {
            return nil
        }

        return Account(
            id: id,
            displayName: String(cString: displayNameCString),
            employeeCode: textValue(from: statement, index: 2),
            status: status,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        )
    }

    private func decodeOrganizationMembership(from statement: OpaquePointer?) -> OrganizationMembership? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let organizationIDCString = sqlite3_column_text(statement, 1),
            let accountIDCString = sqlite3_column_text(statement, 2),
            let roleCString = sqlite3_column_text(statement, 3),
            let statusCString = sqlite3_column_text(statement, 4)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let organizationID = UUID(uuidString: String(cString: organizationIDCString)),
            let accountID = UUID(uuidString: String(cString: accountIDCString)),
            let role = OrganizationMembership.Role(rawValue: String(cString: roleCString)),
            let status = OrganizationMembership.Status(rawValue: String(cString: statusCString))
        else {
            return nil
        }

        return OrganizationMembership(
            id: id,
            organizationID: organizationID,
            accountID: accountID,
            role: role,
            status: status,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        )
    }

    private func decodeAccessSession(from statement: OpaquePointer?) -> AccessSession? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let deviceIDCString = sqlite3_column_text(statement, 1),
            let accountIDCString = sqlite3_column_text(statement, 2),
            let statusCString = sqlite3_column_text(statement, 5),
            let methodCString = sqlite3_column_text(statement, 6)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let deviceID = UUID(uuidString: String(cString: deviceIDCString)),
            let accountID = UUID(uuidString: String(cString: accountIDCString)),
            let status = AccessSession.Status(rawValue: String(cString: statusCString)),
            let authenticationMethod = AccessSession.AuthenticationMethod(rawValue: String(cString: methodCString))
        else {
            return nil
        }

        return AccessSession(
            id: id,
            deviceID: deviceID,
            accountID: accountID,
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            endedAt: dateValue(from: statement, index: 4),
            status: status,
            authenticationMethod: authenticationMethod
        )
    }

    private func decodeCaptureSession(from statement: OpaquePointer?) -> CaptureSession? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let organizationIDCString = sqlite3_column_text(statement, 1),
            let workspaceIDCString = sqlite3_column_text(statement, 2),
            let deviceIDCString = sqlite3_column_text(statement, 3),
            let startedByAccountIDCString = sqlite3_column_text(statement, 4),
            let statusCString = sqlite3_column_text(statement, 8)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let organizationID = UUID(uuidString: String(cString: organizationIDCString)),
            let workspaceID = UUID(uuidString: String(cString: workspaceIDCString)),
            let deviceID = UUID(uuidString: String(cString: deviceIDCString)),
            let startedByAccountID = UUID(uuidString: String(cString: startedByAccountIDCString)),
            let status = CaptureSession.Status(rawValue: String(cString: statusCString))
        else {
            return nil
        }

        let contextProfile = textValue(from: statement, index: 9)
            .flatMap(MeetingContextProfile.init(rawValue:))
            ?? .general

        return CaptureSession(
            id: id,
            organizationID: organizationID,
            workspaceID: workspaceID,
            deviceID: deviceID,
            startedByAccountID: startedByAccountID,
            accessSessionID: uuidValue(from: statement, index: 5),
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            endedAt: dateValue(from: statement, index: 7),
            status: status,
            meetingContextProfile: contextProfile,
            audioFilePath: textValue(from: statement, index: 10),
            audioDurationSeconds: doubleValue(from: statement, index: 11),
            utteranceCount: intValue(from: statement, index: 12) ?? 0
        )
    }

    private func decodeUtterance(from statement: OpaquePointer?) -> Utterance? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let captureSessionIDCString = sqlite3_column_text(statement, 1),
            let textCString = sqlite3_column_text(statement, 6),
            let localeCString = sqlite3_column_text(statement, 7)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let captureSessionID = UUID(uuidString: String(cString: captureSessionIDCString))
        else {
            return nil
        }

        return Utterance(
            id: id,
            captureSessionID: captureSessionID,
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            endedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            startOffsetSeconds: sqlite3_column_double(statement, 4),
            endOffsetSeconds: sqlite3_column_double(statement, 5),
            text: String(cString: textCString),
            locale: String(cString: localeCString),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
        )
    }

    private func decodeMeetingMinutes(from statement: OpaquePointer?) -> MeetingMinutes? {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let captureSessionIDCString = sqlite3_column_text(statement, 1),
            let statusCString = sqlite3_column_text(statement, 2)
        else {
            return nil
        }

        guard
            let id = UUID(uuidString: String(cString: idCString)),
            let captureSessionID = UUID(uuidString: String(cString: captureSessionIDCString)),
            let status = MeetingMinutes.Status(rawValue: String(cString: statusCString))
        else {
            return nil
        }

        return MeetingMinutes(
            id: id,
            captureSessionID: captureSessionID,
            status: status,
            markdownText: textValue(from: statement, index: 3),
            errorMessage: textValue(from: statement, index: 4),
            modelIdentifier: textValue(from: statement, index: 5),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            startedAt: dateValue(from: statement, index: 7),
            completedAt: dateValue(from: statement, index: 8)
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

    private func uuidValue(from statement: OpaquePointer?, index: Int32) -> UUID? {
        guard let string = textValue(from: statement, index: index) else {
            return nil
        }
        return UUID(uuidString: string)
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

    private func userVersion(in database: OpaquePointer?) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteSessionStoreError.prepare(message: errorMessage(from: database))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteSessionStoreError.step(message: errorMessage(from: database))
        }

        return Int(sqlite3_column_int64(statement, 0))
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
