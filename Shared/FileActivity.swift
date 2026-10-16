import Foundation

enum FileActivity {
    static func latestModification(under directory: URL) -> Date? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var latest: Date?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                latest = max(latest ?? date, date)
            }
        }
        return latest
    }
}
