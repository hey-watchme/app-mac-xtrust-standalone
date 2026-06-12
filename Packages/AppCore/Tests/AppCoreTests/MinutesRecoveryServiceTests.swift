import Foundation
import Testing
@testable import AppCore

struct MinutesRecoveryServiceTests {
    @Test
    func flipsRunningMinutesToPendingAndReturnsAllPending() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_800_000)
        let running = MeetingMinutes(
            captureSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
            status: .running,
            createdAt: createdAt,
            startedAt: createdAt.addingTimeInterval(1)
        )
        let alreadyPending = MeetingMinutes(
            captureSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000802")!,
            status: .pending,
            createdAt: createdAt.addingTimeInterval(2)
        )
        let completed = MeetingMinutes(
            captureSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000803")!,
            status: .completed,
            markdownText: "# Done",
            modelIdentifier: "model",
            createdAt: createdAt.addingTimeInterval(3),
            startedAt: createdAt.addingTimeInterval(4),
            completedAt: createdAt.addingTimeInterval(5)
        )
        let store = InMemoryRecoveryMinutesStore(
            initialMinutes: [running, alreadyPending, completed]
        )
        let service = MinutesRecoveryService(minutesStore: store)

        let recovered = try service.recover()

        #expect(recovered.count == 2)
        #expect(Set(recovered.map(\.id)) == Set([running.id, alreadyPending.id]))
        #expect(recovered.allSatisfy { $0.status == .pending })

        let persisted = try store.listMeetingMinutes(statuses: [.pending])
        #expect(persisted.count == 2)
        let recoveredRunning = persisted.first { $0.id == running.id }
        #expect(recoveredRunning?.status == .pending)
        #expect(recoveredRunning?.startedAt == nil)
        #expect(try store.listMeetingMinutes(statuses: [.running]).isEmpty)
        #expect(try store.listMeetingMinutes(statuses: [.completed]) == [completed])
    }

    @Test
    func returnsEmptyListWhenNothingToRecover() throws {
        let store = InMemoryRecoveryMinutesStore(initialMinutes: [])
        let service = MinutesRecoveryService(minutesStore: store)

        let recovered = try service.recover()

        #expect(recovered.isEmpty)
    }
}

private final class InMemoryRecoveryMinutesStore: MeetingMinutesStore, @unchecked Sendable {
    private var minutes: [MeetingMinutes]

    init(initialMinutes: [MeetingMinutes]) {
        self.minutes = initialMinutes
    }

    func insertMeetingMinutes(_ newMinutes: MeetingMinutes) throws {
        minutes.append(newMinutes)
    }

    func updateMeetingMinutes(_ updatedMinutes: MeetingMinutes) throws {
        guard let index = minutes.firstIndex(where: { $0.id == updatedMinutes.id }) else { return }
        minutes[index] = updatedMinutes
    }

    func getMeetingMinutes(captureSessionID: UUID) throws -> MeetingMinutes? {
        minutes.first { $0.captureSessionID == captureSessionID }
    }

    func listMeetingMinutes(statuses: [MeetingMinutes.Status]) throws -> [MeetingMinutes] {
        minutes
            .filter { statuses.contains($0.status) }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
