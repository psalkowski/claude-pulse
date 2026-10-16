import Foundation

typealias AccountForecasts = [UsageWindowKind: UsageForecast]

@MainActor
final class UsageHistoryStore {
    static let seedRefreshInterval: TimeInterval = 24 * 3600

    private(set) var history: UsageHistory
    private var isScanning = false
    private let file: UsageHistoryFile

    init(now: Date = Date()) {
        file = UsageHistoryFile(url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudePulse", isDirectory: true)
            .appendingPathComponent("usage-history.json"))
        history = Self.pruned(file.load() ?? UsageHistory(), now: now)
    }

    func record(_ report: UsageReport, accountID: String, at now: Date) {
        var windows = history.samples[accountID] ?? [:]
        for kind in UsageWindowKind.allCases {
            guard let window = report.window(kind), let resetsAt = window.resetsAt else { continue }
            let sample = UsageSample(at: now, percent: window.utilization, resetsAt: resetsAt)
            windows[kind] = UsageForecaster.record(sample, into: windows[kind] ?? [])
        }
        guard windows != history.samples[accountID] ?? [:] else { return }
        history.samples[accountID] = windows
        save()
    }

    func reconcileWithDisk(now: Date) {
        history = Self.pruned(file.reconcile(history), now: now)
    }

    func refreshSeeds(for accounts: [DiscoveredAccount], now: Date) {
        guard !isScanning else { return }
        let stale = accounts.filter { account in
            guard !account.configDirs.isEmpty else { return false }
            guard let seed = history.seeds[account.id] else { return true }
            return seed.configDirs != account.configDirs.map(\.path)
                || now.timeIntervalSince(seed.computedAt) >= Self.seedRefreshInterval
        }
        guard !stale.isEmpty else { return }
        isScanning = true
        Task {
            for account in stale {
                let dirs = account.configDirs
                let since = now.addingTimeInterval(-UsageForecaster.history)
                let weights = await Task.detached(priority: .background) {
                    UsageForecaster.seedWeights(TranscriptRhythm.activity(configDirs: dirs, since: since))
                }.value
                history.seeds[account.id] = TranscriptSeed(computedAt: now, configDirs: dirs.map(\.path), weights: weights)
                save()
            }
            isScanning = false
        }
    }

    static func forecasts(for snapshot: UsageSnapshot, history: UsageHistory, now: Date) -> [String: AccountForecasts] {
        let pairs = snapshot.accounts.map { account -> (String, AccountForecasts) in
            let samples = history.samples[account.id] ?? [:]
            let seed = history.seeds[account.id]?.weights
            let forecasts = UsageWindowKind.allCases.reduce(into: AccountForecasts()) { result, kind in
                guard let window = account.window(kind), let resetsAt = window.resetsAt, resetsAt > now else { return }
                result[kind] = UsageForecaster.forecast(
                    kind: kind, samples: samples[kind] ?? [], used: window.utilization,
                    resetsAt: resetsAt, now: now, seed: seed)
            }
            return (account.id, forecasts)
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private static func pruned(_ history: UsageHistory, now: Date) -> UsageHistory {
        var result = history
        result.samples = history.samples.compactMapValues { windows in
            let recent = windows.compactMapValues { samples -> [UsageSample]? in
                let kept = samples.filter { now.timeIntervalSince($0.at) <= UsageForecaster.history }
                return kept.isEmpty ? nil : kept
            }
            return recent.isEmpty ? nil : recent
        }
        return result
    }

    private func save() {
        history = file.save(history)
    }
}
