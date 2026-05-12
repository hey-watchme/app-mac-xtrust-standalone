import Foundation

public struct AccessSession: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case active
        case loggedOut = "logged_out"
        case timedOut = "timed_out"
        case revoked
    }

    public enum AuthenticationMethod: String, Codable, Equatable, Sendable {
        case guest
        case badge
        case sso
        case pin
        case qr
        case localMock = "local_mock"
    }

    public let id: UUID
    public let deviceID: UUID
    public let accountID: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let status: Status
    public let authenticationMethod: AuthenticationMethod

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        accountID: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        status: Status = .active,
        authenticationMethod: AuthenticationMethod
    ) {
        self.id = id
        self.deviceID = deviceID
        self.accountID = accountID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.authenticationMethod = authenticationMethod
    }

    public func ended(at endedAt: Date, status: Status) -> AccessSession {
        AccessSession(
            id: id,
            deviceID: deviceID,
            accountID: accountID,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            authenticationMethod: authenticationMethod
        )
    }
}
