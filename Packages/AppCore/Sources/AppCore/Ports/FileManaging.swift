import Foundation

public protocol FileManaging: Sendable {
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
}

public struct LocalFileManager: FileManaging {
    public init() {}

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
