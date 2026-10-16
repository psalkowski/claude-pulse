import Foundation

enum SnapshotStore {
    static var directory: URL {
        realHomeDirectory().appendingPathComponent("Library/Application Support/ClaudePulse", isDirectory: true)
    }

    static var fileURL: URL {
        directory.appendingPathComponent("usage-snapshot.json")
    }

    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    static func update(_ change: (inout UsageSnapshot) -> Void) {
        guard var snapshot = load() else { return }
        change(&snapshot)
        save(snapshot)
    }

    static func save(_ snapshot: UsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // The widget runs sandboxed; NSHomeDirectory() there points at the sandbox
    // container, but its read-only file exception is relative to the real home.
    private static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
