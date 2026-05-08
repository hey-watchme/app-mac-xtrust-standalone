import Foundation

public protocol CaptureController: AnyObject, Sendable {
    func startCapture(
        utteranceOutputDirectory: URL,
        onEvent: @escaping @Sendable (CaptureEvent) -> Void
    ) throws
    func stopCapture()
    var isCapturing: Bool { get }
}
