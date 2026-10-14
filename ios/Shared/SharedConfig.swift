import Foundation

enum SharedConfig {
    static let maxDuration: TimeInterval = 60 * 60
    static let minFreeBytesToStart: Int64 = 500 * 1024 * 1024
    static let minFreeBytesWhileRecording: Int64 = 150 * 1024 * 1024
    static let pendingFileMinAge: TimeInterval = 60

    enum Keys {
        static let startedAt = "recordingStartedAt"
        static let lastResult = "lastRecordingResult"
    }

    enum Result: String {
        case savedToPhotos
        case pending
        case failed
    }

    /// Read from Info.plist so the identifier stays in sync with the build setting `APP_GROUP_ID`.
    static let appGroupID: String? = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String

    static var sharedDefaults: UserDefaults? {
        guard let appGroupID, groupContainer != nil else { return nil }
        return UserDefaults(suiteName: appGroupID)
    }

    static var groupContainer: URL? {
        guard let appGroupID else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Recordings that could not be saved to Photos by the extension wait here until the app picks them up.
    static var pendingDirectory: URL? {
        guard let container = groupContainer else { return nil }
        let directory = container.appendingPathComponent("PendingRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func freeDiskSpace() -> Int64 {
        let url = FileManager.default.temporaryDirectory
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }
}
