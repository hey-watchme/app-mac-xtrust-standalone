import Foundation

public protocol MeetingMinutesStore: Sendable {
    func insertMeetingMinutes(_ minutes: MeetingMinutes) throws
    func updateMeetingMinutes(_ minutes: MeetingMinutes) throws
    func getMeetingMinutes(captureSessionID: UUID) throws -> MeetingMinutes?
    func listMeetingMinutes(statuses: [MeetingMinutes.Status]) throws -> [MeetingMinutes]
}
