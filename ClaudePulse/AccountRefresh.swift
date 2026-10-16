import Foundation

enum AccountRefresh {
    struct Outcome {
        var usage: AccountUsage
        var attemptedAt: Date?
        var report: UsageReport?
    }

    static func codex(
        account: CodexAccount,
        previous: AccountUsage?,
        force: Bool,
        isActive: Bool,
        lastAttemptAt: Date?,
        now: Date,
        read: (CodexAccount) async throws -> UsageReport
    ) async -> Outcome {
        var usage = carryingOver(previous, now: now, into: AccountUsage(
            id: account.id,
            label: account.title,
            detail: account.email,
            subscriptionType: account.plan,
            tokenFailure: previous?.tokenFailure,
            provider: .codex
        ))
        if account.isExpired(at: now) {
            usage.tokenFailure = .expired
            return Outcome(usage: usage)
        }
        guard FetchPolicy.shouldRead(force: force, isActive: isActive, lastAttemptAt: lastAttemptAt, now: now) else {
            return Outcome(usage: usage)
        }
        return await fetched(usage, attemptedAt: now) {
            try await read(account)
        }
    }

    static func carryingOver(_ previous: AccountUsage?, now: Date, into usage: AccountUsage) -> AccountUsage {
        var usage = usage
        usage.lastSuccessAt = previous?.lastSuccessAt
        usage.fiveHour = rolled(previous?.fiveHour, now: now)
        usage.sevenDay = rolled(previous?.sevenDay, now: now)
        usage.sevenDayOpus = rolled(previous?.sevenDayOpus, now: now)
        usage.sevenDayFable = rolled(previous?.sevenDayFable, now: now)
        return usage
    }

    static func fetched(
        _ usage: AccountUsage,
        attemptedAt: Date,
        report fetch: () async throws -> UsageReport
    ) async -> Outcome {
        var usage = usage
        do {
            let report = try await fetch()
            // Each window updates only if this fetch actually returned it;
            // otherwise it keeps the last-known value. The Haiku probe may
            // include the Fable window; Fable itself is never queried.
            usage.fiveHour = report.fiveHour ?? usage.fiveHour
            usage.sevenDay = report.sevenDay ?? usage.sevenDay
            usage.sevenDayOpus = report.sevenDayOpus ?? usage.sevenDayOpus
            usage.sevenDayFable = report.sevenDayFable ?? usage.sevenDayFable
            usage.lastSuccessAt = Date()
            usage.tokenFailure = nil
            return Outcome(usage: usage, attemptedAt: attemptedAt, report: report)
        } catch UsageClientError.unauthorized(let failure) {
            usage.tokenFailure = failure
        } catch {
            usage.fetchError = error.localizedDescription
        }
        return Outcome(usage: usage, attemptedAt: attemptedAt)
    }

    // A usage window whose reset time has passed has rolled over to ~0 while we
    // weren't polling. Reflect that instead of showing a stale full bar.
    private static func rolled(_ window: UsageWindow?, now: Date) -> UsageWindow? {
        guard let window, let resetsAt = window.resetsAt else { return window }
        if resetsAt <= now { return UsageWindow(utilization: 0, resetsAt: nil) }
        return window
    }
}
