import Foundation
import AppKit
import WidgetKit

@MainActor
final class UsagePoller: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var forecasts: [String: AccountForecasts] = [:]

    static let pollInterval: TimeInterval = 60
    static let activeWindow: TimeInterval = 10 * 60
    static let keepAliveKey = "keepSessionsActive"

    private var timer: Timer?
    private var started = false
    private let client = UsageClient()
    private let history: UsageHistoryStore?
    private var lastAttemptAt: [String: Date] = [:]

    init() {
        let history = UsageHistoryStore()
        let snapshot = SnapshotStore.load() ?? .empty
        self.history = history
        self.snapshot = snapshot
        forecasts = UsageHistoryStore.forecasts(for: snapshot, history: history.history, now: Date())
    }

    // For doc rendering only: a poller seeded with fixed data and no timers.
    init(previewing snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        self.started = true
        history = nil
        forecasts = UsageHistoryStore.forecasts(for: snapshot, history: UsageHistory(), now: Date())
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // `force` = user-initiated (Refresh button): fetch every token account even
    // if idle, knowingly starting a session. Automatic polling fetches accounts
    // that are active (or all when "keep sessions active" is on), and otherwise
    // only every few minutes while an account's 5-hour window is already open.
    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await performRefresh(force: force)
            isRefreshing = false
        }
    }

    private func performRefresh(force: Bool) async {
        let keepAlive = UserDefaults.standard.bool(forKey: Self.keepAliveKey)
        let onDisk = await Task.detached(priority: .utility) {
            AccountDiscovery.all().map { account -> (DiscoveredAccount, Date?) in
                (account, account.lastActivity())
            }
        }.value

        let previousByID = Dictionary(snapshot.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let signedOut = TokenStore.accountIDs()
            .subtracting(onDisk.map(\.0.id))
            .sorted()
            .map { id -> (DiscoveredAccount, Date?) in
                (DiscoveredAccount(signedOut: id, lastSeen: previousByID[id]), nil)
            }
        let discovered = onDisk + signedOut
        var results: [FetchOutcome] = []

        await withTaskGroup(of: FetchOutcome.self) { group in
            for (account, lastActivity) in discovered {
                let previous = previousByID[account.id]
                let token = TokenStore.token(for: account.id)
                let policy = FetchPolicy.Inputs(
                    hasToken: token != nil,
                    force: force,
                    keepAlive: keepAlive,
                    isActive: lastActivity.map { Date().timeIntervalSince($0) < Self.activeWindow } ?? false,
                    sessionResetsAt: previous?.fiveHour?.resetsAt,
                    lastAttemptAt: lastAttemptAt[account.id]
                )
                group.addTask { [client] in
                    await Self.buildUsage(
                        account: account,
                        token: token,
                        previous: previous,
                        policy: policy,
                        client: client
                    )
                }
            }
            for await result in group { results.append(result) }
        }

        let now = Date()
        for result in results {
            if let attemptedAt = result.attemptedAt { lastAttemptAt[result.usage.id] = attemptedAt }
            if let report = result.report, let attemptedAt = result.attemptedAt {
                history?.record(report, accountID: result.usage.id, at: attemptedAt)
            }
        }
        snapshot = UsageSnapshot(fetchedAt: now, accounts: Self.sorted(results.map(\.usage)))
        SnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        if let history {
            history.reconcileWithDisk(now: now)
            forecasts = UsageHistoryStore.forecasts(for: snapshot, history: history.history, now: now)
            history.refreshSeeds(for: onDisk.map(\.0), now: now)
        }
    }

    private struct FetchOutcome {
        var usage: AccountUsage
        var attemptedAt: Date?
        var report: UsageReport?
    }

    private static func buildUsage(
        account: DiscoveredAccount,
        token: String?,
        previous: AccountUsage?,
        policy: FetchPolicy.Inputs,
        client: UsageClient
    ) async -> FetchOutcome {
        let label = account.label
        var usage = AccountUsage(
            id: account.id,
            label: label.title,
            detail: label.detail,
            subscriptionType: account.profile.organizationType,
            // Polls that don't fetch must keep the last verdict on the token.
            tokenFailure: token == nil ? nil : previous?.tokenFailure,
            fetchError: nil,
            lastSuccessAt: previous?.lastSuccessAt,
            fiveHour: rolled(previous?.fiveHour),
            sevenDay: rolled(previous?.sevenDay),
            sevenDayOpus: rolled(previous?.sevenDayOpus),
            sevenDayFable: rolled(previous?.sevenDayFable),
            pingError: nil,
            needsToken: token == nil,
            configDir: account.configDir?.path,
            origin: account.origin
        )
        let attemptedAt = Date()
        guard FetchPolicy.shouldFetch(policy, now: attemptedAt), let token else {
            return FetchOutcome(usage: usage)
        }
        do {
            let report = try await client.fetch(accessToken: token)
            // Each window updates only if this fetch actually returned it;
            // otherwise it keeps the last-known value. The Haiku probe may
            // include the Fable window; Fable itself is never queried.
            usage.fiveHour = report.fiveHour ?? usage.fiveHour
            usage.sevenDay = report.sevenDay ?? usage.sevenDay
            usage.sevenDayOpus = report.sevenDayOpus ?? usage.sevenDayOpus
            usage.sevenDayFable = report.sevenDayFable ?? usage.sevenDayFable
            usage.lastSuccessAt = Date()
            usage.tokenFailure = nil
            return FetchOutcome(usage: usage, attemptedAt: attemptedAt, report: report)
        } catch UsageClientError.unauthorized(let failure) {
            usage.tokenFailure = failure
        } catch {
            usage.fetchError = error.localizedDescription
        }
        return FetchOutcome(usage: usage, attemptedAt: attemptedAt)
    }

    // A usage window whose reset time has passed has rolled over to ~0 while we
    // weren't polling. Reflect that instead of showing a stale full bar.
    private static func rolled(_ window: UsageWindow?) -> UsageWindow? {
        guard let window, let resetsAt = window.resetsAt else { return window }
        if resetsAt <= Date() { return UsageWindow(utilization: 0, resetsAt: nil) }
        return window
    }

    private static func sorted(_ accounts: [AccountUsage]) -> [AccountUsage] {
        accounts.sorted { rank($0) == rank($1) ? $0.id < $1.id : rank($0) < rank($1) }
    }

    private static func rank(_ account: AccountUsage) -> Int {
        let type = account.subscriptionType?.lowercased() ?? ""
        if type.contains("max") || type.contains("pro") { return 0 }
        if type.contains("team") || type.contains("enterprise") { return 1 }
        return 2
    }
}
