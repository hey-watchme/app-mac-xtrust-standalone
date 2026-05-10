import Foundation

public struct Account: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case active
        case inactive
    }

    public let id: UUID
    public let displayName: String
    public let employeeCode: String?
    public let status: Status
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        employeeCode: String? = nil,
        status: Status = .active,
        createdAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.employeeCode = employeeCode
        self.status = status
        self.createdAt = createdAt
    }
}
