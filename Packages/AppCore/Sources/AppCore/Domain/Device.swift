import Foundation

public struct Device: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case active
        case inactive
        case retired
    }

    public let id: UUID
    public let organizationID: UUID
    public let workspaceID: UUID
    public let displayName: String
    public let locationLabel: String?
    public let status: Status
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        organizationID: UUID,
        workspaceID: UUID,
        displayName: String,
        locationLabel: String? = nil,
        status: Status = .active,
        createdAt: Date
    ) {
        self.id = id
        self.organizationID = organizationID
        self.workspaceID = workspaceID
        self.displayName = displayName
        self.locationLabel = locationLabel
        self.status = status
        self.createdAt = createdAt
    }
}
