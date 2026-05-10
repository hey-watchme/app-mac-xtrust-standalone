import Foundation

public struct Workspace: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case active
        case inactive
    }

    public let id: UUID
    public let organizationID: UUID
    public let name: String
    public let code: String?
    public let status: Status
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        organizationID: UUID,
        name: String,
        code: String? = nil,
        status: Status = .active,
        createdAt: Date
    ) {
        self.id = id
        self.organizationID = organizationID
        self.name = name
        self.code = code
        self.status = status
        self.createdAt = createdAt
    }
}
