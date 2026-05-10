import Foundation

public protocol DeviceStore: Sendable {
    func listDevices() throws -> [Device]
    func listDevices(workspaceID: UUID) throws -> [Device]
    func insertDevice(_ device: Device) throws
    func updateDevice(_ device: Device) throws
}
