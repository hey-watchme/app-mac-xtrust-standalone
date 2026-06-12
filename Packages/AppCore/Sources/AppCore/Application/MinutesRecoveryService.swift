import Foundation

public struct MinutesRecoveryService: Sendable {
    private let minutesStore: any MeetingMinutesStore

    public init(minutesStore: any MeetingMinutesStore) {
        self.minutesStore = minutesStore
    }

    @discardableResult
    public func recover() throws -> [MeetingMinutes] {
        let running = try minutesStore.listMeetingMinutes(statuses: [.running])
        for minutes in running {
            try minutesStore.updateMeetingMinutes(minutes.reEnqueued())
        }
        return try minutesStore.listMeetingMinutes(statuses: [.pending])
    }
}
