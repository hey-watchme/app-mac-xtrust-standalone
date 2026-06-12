import Foundation

public protocol CaptureSessionStore: Sendable {
    func listCaptureSessions() throws -> [CaptureSession]
    func insertCaptureSession(_ session: CaptureSession) throws
    func updateCaptureSession(_ session: CaptureSession) throws
}
