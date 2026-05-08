import Foundation

public struct WorkspacePaths: Equatable, Sendable {
    public let root: URL
    public let audio: URL
    public let transcripts: URL
    public let summaries: URL
    public let models: URL
    public let jobs: URL
    public let transcriptionJobs: URL
    public let database: URL

    public init(root: URL) {
        self.root = root
        self.audio = root.appending(path: "audio", directoryHint: .isDirectory)
        self.transcripts = root.appending(path: "transcripts", directoryHint: .isDirectory)
        self.summaries = root.appending(path: "summaries", directoryHint: .isDirectory)
        self.models = root.appending(path: "models", directoryHint: .isDirectory)
        self.jobs = root.appending(path: "jobs", directoryHint: .isDirectory)
        self.transcriptionJobs = jobs.appending(path: "transcription", directoryHint: .isDirectory)
        self.database = root.appendingPathComponent("xtrust-mac-local-first.sqlite")
    }

    public func transcriptionJobDirectory(jobID: UUID) -> URL {
        transcriptionJobs.appending(path: jobID.uuidString, directoryHint: .isDirectory)
    }
}

public enum WorkspaceLocator {
    public static func defaultRoot(
        fileManager: FileManager = .default,
        bundleIdentifier: String = "com.xtrust.mac-local-first"
    ) throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw WorkspaceError.applicationSupportNotFound
        }

        return appSupport
            .appending(path: "XTrust", directoryHint: .isDirectory)
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }
}

public enum WorkspaceError: Error, LocalizedError {
    case applicationSupportNotFound

    public var errorDescription: String? {
        switch self {
        case .applicationSupportNotFound:
            return "Application Support directory could not be resolved."
        }
    }
}
