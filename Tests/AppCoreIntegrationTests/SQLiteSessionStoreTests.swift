import Foundation
import Testing
@testable import AppCore

struct SQLiteSessionStoreTests {
    @Test
    func insertsAndListsCaptureSessions() throws {
        let store = try makeInitializedStore()
        let fixture = try insertSharedDeviceFixture(store: store)

        let older = makeCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            fixture: fixture,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = makeCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001002")!,
            fixture: fixture,
            startedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try store.insertCaptureSession(older)
        try store.insertCaptureSession(newer)

        let sessions = try store.listCaptureSessions()

        #expect(sessions == [newer, older])
    }

    @Test
    func updatesCaptureSessionLifecycle() throws {
        let store = try makeInitializedStore()
        let fixture = try insertSharedDeviceFixture(store: store)
        let session = makeCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001011")!,
            fixture: fixture,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.insertCaptureSession(session)

        let recording = session.recordingStarted(audioFilePath: "/tmp/meeting.wav")
        try store.updateCaptureSession(recording)
        #expect(try store.listCaptureSessions() == [recording])

        let closed = recording
            .withMeetingContextProfile(.recruitingHR)
            .closed(
                endedAt: Date(timeIntervalSince1970: 1_700_003_600),
                audioDurationSeconds: 3_600,
                utteranceCount: 12
            )
        try store.updateCaptureSession(closed)

        let listed = try store.listCaptureSessions()
        #expect(listed == [closed])
        #expect(listed.first?.status == .closed)
        #expect(listed.first?.meetingContextProfile == .recruitingHR)
        #expect(listed.first?.audioDurationSeconds == 3_600)
        #expect(listed.first?.utteranceCount == 12)
    }

    @Test
    func insertsAndListsUtterancesOrderedByStartedAt() throws {
        let store = try makeInitializedStore()
        let fixture = try insertSharedDeviceFixture(store: store)
        let session = makeCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001021")!,
            fixture: fixture,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.insertCaptureSession(session)

        let later = Utterance(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001022")!,
            captureSessionID: session.id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_030),
            endedAt: Date(timeIntervalSince1970: 1_700_000_034),
            startOffsetSeconds: 30,
            endOffsetSeconds: 34,
            text: "次の議題です",
            locale: "ja-JP",
            createdAt: Date(timeIntervalSince1970: 1_700_000_034)
        )
        let earlier = Utterance(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001023")!,
            captureSessionID: session.id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_005),
            endedAt: Date(timeIntervalSince1970: 1_700_000_008),
            startOffsetSeconds: 5,
            endOffsetSeconds: 8,
            text: "こんにちは",
            locale: "ja-JP",
            createdAt: Date(timeIntervalSince1970: 1_700_000_008)
        )
        try store.insertUtterance(later)
        try store.insertUtterance(earlier)

        let utterances = try store.listUtterances(captureSessionID: session.id)

        #expect(utterances == [earlier, later])
    }

    @Test
    func insertsUpdatesAndGetsMeetingMinutes() throws {
        let store = try makeInitializedStore()
        let fixture = try insertSharedDeviceFixture(store: store)
        let session = makeCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001031")!,
            fixture: fixture,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.insertCaptureSession(session)

        let pending = MeetingMinutes(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001032")!,
            captureSessionID: session.id,
            createdAt: Date(timeIntervalSince1970: 1_700_003_700)
        )
        try store.insertMeetingMinutes(pending)
        #expect(try store.getMeetingMinutes(captureSessionID: session.id) == pending)
        #expect(try store.getMeetingMinutes(captureSessionID: UUID()) == nil)

        let completed = pending
            .running(at: Date(timeIntervalSince1970: 1_700_003_710))
            .completed(
                markdownText: "# 議事録",
                modelIdentifier: "gemma-4-e4b",
                at: Date(timeIntervalSince1970: 1_700_003_800)
            )
        try store.updateMeetingMinutes(completed)

        let fetched = try store.getMeetingMinutes(captureSessionID: session.id)
        #expect(fetched == completed)
        #expect(fetched?.markdownText == "# 議事録")
        #expect(fetched?.modelIdentifier == "gemma-4-e4b")
    }

    @Test
    func listsMeetingMinutesFilteredByStatuses() throws {
        let store = try makeInitializedStore()
        let fixture = try insertSharedDeviceFixture(store: store)

        var minutesByStatus: [MeetingMinutes.Status: MeetingMinutes] = [:]
        let statuses: [MeetingMinutes.Status] = [.pending, .running, .completed, .failed]
        for (offset, status) in statuses.enumerated() {
            let session = makeCaptureSession(
                id: UUID(),
                fixture: fixture,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset))
            )
            try store.insertCaptureSession(session)

            let minutes = MeetingMinutes(
                captureSessionID: session.id,
                status: status,
                markdownText: status == .completed ? "# Done" : nil,
                errorMessage: status == .failed ? "boom" : nil,
                createdAt: Date(timeIntervalSince1970: 1_700_004_000 + Double(offset)),
                startedAt: status == .pending ? nil : Date(timeIntervalSince1970: 1_700_004_100),
                completedAt: status == .completed || status == .failed
                    ? Date(timeIntervalSince1970: 1_700_004_200)
                    : nil
            )
            try store.insertMeetingMinutes(minutes)
            minutesByStatus[status] = minutes
        }

        #expect(try store.listMeetingMinutes(statuses: [.running]) == [minutesByStatus[.running]!])
        #expect(
            try store.listMeetingMinutes(statuses: [.pending, .running])
                == [minutesByStatus[.pending]!, minutesByStatus[.running]!]
        )
        #expect(try store.listMeetingMinutes(statuses: []).isEmpty)
        #expect(try store.listMeetingMinutes(statuses: statuses).count == 4)
    }
}

struct SharedDeviceFixture {
    let organization: Organization
    let workspace: Workspace
    let device: Device
    let account: Account
    let accessSession: AccessSession
}

func makeInitializedStore() throws -> SQLiteSessionStore {
    let tempRoot = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let paths = WorkspacePaths(root: tempRoot)
    let store = SQLiteSessionStore(databaseURL: paths.database)
    try store.initialize()
    return store
}

func insertSharedDeviceFixture(store: SQLiteSessionStore) throws -> SharedDeviceFixture {
    let createdAt = Date(timeIntervalSince1970: 1_699_999_000)
    let organization = Organization(name: "Org", createdAt: createdAt)
    let workspace = Workspace(
        organizationID: organization.id,
        name: "Workspace",
        createdAt: createdAt.addingTimeInterval(1)
    )
    let device = Device(
        organizationID: organization.id,
        workspaceID: workspace.id,
        displayName: "Device",
        createdAt: createdAt.addingTimeInterval(2)
    )
    let account = Account(
        displayName: "Operator",
        createdAt: createdAt.addingTimeInterval(3)
    )
    let accessSession = AccessSession(
        deviceID: device.id,
        accountID: account.id,
        startedAt: createdAt.addingTimeInterval(4),
        authenticationMethod: .localMock
    )

    try store.insertOrganization(organization)
    try store.insertWorkspace(workspace)
    try store.insertDevice(device)
    try store.insertAccount(account)
    try store.insertAccessSession(accessSession)

    return SharedDeviceFixture(
        organization: organization,
        workspace: workspace,
        device: device,
        account: account,
        accessSession: accessSession
    )
}

func makeCaptureSession(
    id: UUID,
    fixture: SharedDeviceFixture,
    startedAt: Date
) -> CaptureSession {
    CaptureSession(
        id: id,
        organizationID: fixture.organization.id,
        workspaceID: fixture.workspace.id,
        deviceID: fixture.device.id,
        startedByAccountID: fixture.account.id,
        accessSessionID: fixture.accessSession.id,
        startedAt: startedAt
    )
}
