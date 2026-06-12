import Foundation
import Testing
@testable import AppCore

struct CaptureSessionServiceTests {
    @Test
    func createsOpenCaptureSessionFromSharedDeviceContext() throws {
        let store = InMemoryCaptureSessionStore()
        let now = Date(timeIntervalSince1970: 1_700_500_000)
        let service = CaptureSessionService(
            captureSessionStore: store,
            clock: CaptureSessionFixedClock(now: now)
        )
        let context = makeSharedDeviceContext()
        let accessSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000510")!

        let session = try service.createCaptureSession(
            context: context,
            accessSessionID: accessSessionID
        )

        #expect(session.organizationID == context.organization.id)
        #expect(session.workspaceID == context.workspace.id)
        #expect(session.deviceID == context.device.id)
        #expect(session.startedByAccountID == context.bootstrapAccount.id)
        #expect(session.accessSessionID == accessSessionID)
        #expect(session.startedAt == now)
        #expect(session.status == .open)
        #expect(session.meetingContextProfile == .general)
        #expect(try store.listCaptureSessions() == [session])
    }

    @Test
    func marksRecordingStarted() throws {
        let store = InMemoryCaptureSessionStore()
        let service = CaptureSessionService(
            captureSessionStore: store,
            clock: CaptureSessionFixedClock(now: Date(timeIntervalSince1970: 1_700_500_100))
        )
        let session = try service.createCaptureSession(
            context: makeSharedDeviceContext(),
            accessSessionID: nil
        )

        let updated = try service.markRecordingStarted(
            session,
            audioFilePath: "/tmp/meeting.wav"
        )

        #expect(updated.status == .recording)
        #expect(updated.audioFilePath == "/tmp/meeting.wav")
        #expect(updated.endedAt == nil)
        #expect(try store.listCaptureSessions() == [updated])
    }

    @Test
    func closesCaptureSessionWithDurationAndUtteranceCount() throws {
        let store = InMemoryCaptureSessionStore()
        let service = CaptureSessionService(
            captureSessionStore: store,
            clock: CaptureSessionFixedClock(now: Date(timeIntervalSince1970: 1_700_500_200))
        )
        let session = try service.markRecordingStarted(
            try service.createCaptureSession(
                context: makeSharedDeviceContext(),
                accessSessionID: nil
            ),
            audioFilePath: "/tmp/meeting.wav"
        )
        let endedAt = Date(timeIntervalSince1970: 1_700_503_800)

        let closed = try service.close(
            session,
            endedAt: endedAt,
            audioDurationSeconds: 3_600,
            utteranceCount: 42
        )

        #expect(closed.status == .closed)
        #expect(closed.endedAt == endedAt)
        #expect(closed.audioDurationSeconds == 3_600)
        #expect(closed.utteranceCount == 42)
        #expect(closed.audioFilePath == "/tmp/meeting.wav")
        #expect(try store.listCaptureSessions() == [closed])
    }

    @Test
    func setsMeetingContextProfile() throws {
        let store = InMemoryCaptureSessionStore()
        let service = CaptureSessionService(
            captureSessionStore: store,
            clock: CaptureSessionFixedClock(now: Date(timeIntervalSince1970: 1_700_500_300))
        )
        let session = try service.createCaptureSession(
            context: makeSharedDeviceContext(),
            accessSessionID: nil
        )

        let updated = try service.setMeetingContextProfile(session, profile: .engineering)

        #expect(updated.meetingContextProfile == .engineering)
        #expect(updated.status == session.status)
        #expect(try store.listCaptureSessions() == [updated])
    }
}

private func makeSharedDeviceContext() -> SharedDeviceContext {
    let createdAt = Date(timeIntervalSince1970: 1_700_400_000)
    let organization = Organization(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
        name: "Org",
        createdAt: createdAt
    )
    let workspace = Workspace(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
        organizationID: organization.id,
        name: "Workspace",
        createdAt: createdAt
    )
    let device = Device(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000503")!,
        organizationID: organization.id,
        workspaceID: workspace.id,
        displayName: "Device",
        createdAt: createdAt
    )
    let account = Account(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000504")!,
        displayName: "Operator",
        createdAt: createdAt
    )
    let membership = OrganizationMembership(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000505")!,
        organizationID: organization.id,
        accountID: account.id,
        createdAt: createdAt
    )
    return SharedDeviceContext(
        organization: organization,
        workspace: workspace,
        device: device,
        bootstrapAccount: account,
        bootstrapMembership: membership
    )
}

private final class InMemoryCaptureSessionStore: CaptureSessionStore, @unchecked Sendable {
    private var sessions: [CaptureSession] = []

    func listCaptureSessions() throws -> [CaptureSession] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    func insertCaptureSession(_ session: CaptureSession) throws {
        sessions.append(session)
    }

    func updateCaptureSession(_ session: CaptureSession) throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
    }
}

private struct CaptureSessionFixedClock: Clock {
    let currentDate: Date

    init(now: Date) {
        self.currentDate = now
    }

    func now() -> Date {
        currentDate
    }
}
