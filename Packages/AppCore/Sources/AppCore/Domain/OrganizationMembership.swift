import Foundation

public struct OrganizationMembership: Identifiable, Equatable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case member
        case admin
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case active
        case inactive
    }

    public let id: UUID
    public let organizationID: UUID
    public let accountID: UUID
    public let role: Role
    public let status: Status
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        organizationID: UUID,
        accountID: UUID,
        role: Role = .member,
        status: Status = .active,
        createdAt: Date
    ) {
        self.id = id
        self.organizationID = organizationID
        self.accountID = accountID
        self.role = role
        self.status = status
        self.createdAt = createdAt
    }
}
