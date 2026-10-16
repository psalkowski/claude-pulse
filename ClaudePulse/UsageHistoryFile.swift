import Foundation

struct TranscriptSeed: Codable, Equatable {
    var computedAt: Date
    var configDirs: [String]
    var weights: [Double]?
}

struct UsageHistory: Codable, Equatable {
    var samples: [String: [UsageWindowKind: [UsageSample]]] = [:]
    var seeds: [String: TranscriptSeed] = [:]

    func merged(into disk: UsageHistory) -> UsageHistory {
        var result = disk
        for (accountID, windows) in samples {
            for (kind, recent) in windows {
                let combined = ((disk.samples[accountID]?[kind] ?? []) + recent).sorted { $0.at < $1.at }
                result.samples[accountID, default: [:]][kind] = combined.reduce(into: []) { kept, sample in
                    kept = UsageForecaster.record(sample, into: kept)
                }
            }
        }
        result.seeds.merge(seeds) { _, recent in recent }
        return result
    }
}

final class UsageHistoryFile {
    let url: URL
    private(set) var isBlocked = false
    private(set) var hasUnsavedChanges = false

    init(url: URL) {
        self.url = url
    }

    func load() -> UsageHistory? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            isBlocked = false
            return UsageHistory()
        } catch {
            isBlocked = true
            return nil
        }
        isBlocked = false
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let decoded = try? decoder.decode(UsageHistory.self, from: data) { return decoded }
        return setAsideUnreadable() ? UsageHistory() : nil
    }

    func reconcile(_ history: UsageHistory) -> UsageHistory {
        var current = history
        if isBlocked, let disk = load() {
            current = history.merged(into: disk)
        }
        return hasUnsavedChanges ? save(current) : current
    }

    func save(_ history: UsageHistory) -> UsageHistory {
        var current = history
        if isBlocked {
            guard let disk = load() else {
                hasUnsavedChanges = true
                return current
            }
            current = history.merged(into: disk)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            let data = try encoder.encode(current)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            hasUnsavedChanges = false
        } catch {
            hasUnsavedChanges = true
        }
        return current
    }

    private func setAsideUnreadable() -> Bool {
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
        try? FileManager.default.removeItem(at: aside)
        do {
            try FileManager.default.moveItem(at: url, to: aside)
            return true
        } catch {
            isBlocked = true
            return false
        }
    }
}
