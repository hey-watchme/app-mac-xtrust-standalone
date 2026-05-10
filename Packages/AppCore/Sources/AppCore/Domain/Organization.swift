import Foundation

public struct Organization: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case active
        case inactive
    }

    public let id: UUID
    public let name: String
    public let status: Status
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        status: Status = .active,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.createdAt = createdAt
    }
}
