import Foundation
import AppKit
import WidgetKit

@MainActor
final class UsagePoller: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false

    static let pollInterval: TimeInterval = 60
    static let activeWindow: TimeInterval = 10 * 60
    static let keepAliveKey = "keepSessionsActive"

    private var timer: Timer?
    private var started = false
    private let client = UsageClient()

    init() {
        snapshot = SnapshotStore.load() ?? .empty
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
    // if idle, knowingly starting a session. Automatic polling only fetches
    // accounts that are active (or when "keep sessions active" is on).
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
        let discovered = await Task.detached(priority: .utility) {
            AccountDiscovery.all().map { account -> (DiscoveredAccount, Date?) in
                (account, account.lastActivity())
            }
        }.value

        let previousByID = Dictionary(snapshot.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var results: [AccountUsage] = []

        await withTaskGroup(of: AccountUsage.self) { group in
            for (account, lastActivity) in discovered {
                let previous = previousByID[account.id]
                let token = TokenStore.token(for: account.id)
                let isActive = lastActivity.map { Date().timeIntervalSince($0) < Self.activeWindow } ?? false
                let shouldFetch = token != nil && (force || keepAlive || isActive)
                group.addTask { [client] in
                    await Self.buildUsage(
                        account: account,
                        token: token,
                        previous: previous,
                        shouldFetch: shouldFetch,
                        client: client
                    )
                }
            }
            for await result in group { results.append(result) }
        }

        snapshot = UsageSnapshot(fetchedAt: Date(), accounts: Self.sorted(results))
        SnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func buildUsage(
        account: DiscoveredAccount,
        token: String?,
        previous: AccountUsage?,
        shouldFetch: Bool,
        client: UsageClient
    ) async -> AccountUsage {
        let label = account.label
        var usage = AccountUsage(
            id: account.id,
            label: label.title,
            detail: label.detail,
            subscriptionType: account.profile.organizationType,
            tokenExpired: false,
            fetchError: nil,
            lastSuccessAt: previous?.lastSuccessAt,
            fiveHour: rolled(previous?.fiveHour),
            sevenDay: rolled(previous?.sevenDay),
            sevenDayOpus: rolled(previous?.sevenDayOpus),
            sevenDaySonnet: rolled(previous?.sevenDaySonnet),
            pingError: nil,
            needsToken: token == nil,
            configDir: account.configDir.path
        )
        guard shouldFetch, let token else { return usage }
        do {
            let report = try await client.fetch(accessToken: token)
            usage.fiveHour = report.fiveHour ?? usage.fiveHour
            usage.sevenDay = report.sevenDay ?? usage.sevenDay
            usage.sevenDayOpus = report.sevenDayOpus ?? usage.sevenDayOpus
            usage.sevenDaySonnet = report.sevenDaySonnet ?? usage.sevenDaySonnet
            usage.lastSuccessAt = Date()
        } catch {
            usage.fetchError = error.localizedDescription
            if case UsageClientError.unauthorized = error { usage.tokenExpired = true }
        }
        return usage
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
