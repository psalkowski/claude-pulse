import XCTest

final class FetchPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func idle(_ session: FetchPolicy.Session, lastAttemptAgo: TimeInterval?) -> FetchPolicy.Inputs {
        FetchPolicy.Inputs(
            hasToken: true, force: false, keepAlive: false, isActive: false,
            session: session,
            lastAttemptAt: lastAttemptAgo.map { now.addingTimeInterval(-$0) })
    }

    private func idle(resetsIn: TimeInterval?, lastAttemptAgo: TimeInterval?) -> FetchPolicy.Inputs {
        idle(.window(resetsAt: resetsIn.map { now.addingTimeInterval($0) }), lastAttemptAgo: lastAttemptAgo)
    }

    func testIdleAccountPollsEveryFewMinutesOnlyWhileItsWindowStaysOpen() {
        XCTAssertTrue(FetchPolicy.shouldFetch(idle(resetsIn: 3 * 3600, lastAttemptAgo: 6 * 60), now: now))
        XCTAssertFalse(FetchPolicy.shouldFetch(idle(resetsIn: 3 * 3600, lastAttemptAgo: 2 * 60), now: now))
        XCTAssertFalse(FetchPolicy.shouldFetch(idle(resetsIn: 60, lastAttemptAgo: nil), now: now))
        XCTAssertFalse(FetchPolicy.shouldFetch(idle(resetsIn: nil, lastAttemptAgo: nil), now: now))
        XCTAssertFalse(FetchPolicy.shouldFetch(idle(.unknown, lastAttemptAgo: nil), now: now))
    }

    func testPlanThatStopsReportingASessionWindowDropsItAndPollsEveryFewMinutesWhenIdle() async {
        let weekly = UsageWindow(utilization: 38, resetsAt: now.addingTimeInterval(5 * 86400))
        let closedSession = UsageWindow(utilization: 0, resetsAt: nil)
        let lastSession = sample(at: -3 * 86400, resetsAt: -2 * 86400)
        let weeklyRead = sample(at: -3600, resetsAt: 5 * 86400)
        let saved = AccountUsage(id: "acct", label: "Ultra", fiveHour: closedSession, sevenDay: weekly)

        let loaded = AccountRefresh.droppingOutlivedSession(saved, history: [.fiveHour: [lastSession], .sevenDay: [weeklyRead]])
        let session = FetchPolicy.Session(loaded)
        XCTAssertNil(loaded.fiveHour)
        XCTAssertEqual(session, .notOffered)
        XCTAssertTrue(FetchPolicy.shouldFetch(idle(session, lastAttemptAgo: nil), now: now))
        XCTAssertFalse(FetchPolicy.shouldFetch(idle(session, lastAttemptAgo: 2 * 60), now: now))

        let refreshed = await AccountRefresh.fetched(saved, attemptedAt: now) {
            UsageReport(sevenDay: UsageWindow(utilization: 40, resetsAt: weekly.resetsAt))
        }.usage
        XCTAssertNil(refreshed.fiveHour)
        XCTAssertEqual(refreshed.sevenDay?.utilization, 40)
        XCTAssertEqual(FetchPolicy.Session(refreshed), .notOffered)
    }

    func testClosedSessionStaysQuietWhenIdleUnlessALaterReadOmittedIt() {
        let saved = AccountUsage(id: "acct", label: "Max 5×",
                                 fiveHour: UsageWindow(utilization: 0, resetsAt: nil),
                                 sevenDay: UsageWindow(utilization: 20, resetsAt: now.addingTimeInterval(86400)))
        let lastSession = sample(at: -4 * 3600, resetsAt: -3600)
        let readStraddlingTheReset = sample(at: -3600 - 30, resetsAt: 86400)
        let readAfterSessionSamplesWerePruned = sample(at: -600, resetsAt: 86400)

        for history: [UsageWindowKind: [UsageSample]] in [
            [:],
            [.fiveHour: [lastSession]],
            [.sevenDay: [readAfterSessionSamplesWerePruned]],
            [.fiveHour: [lastSession], .sevenDay: [readStraddlingTheReset]],
        ] {
            let loaded = AccountRefresh.droppingOutlivedSession(saved, history: history)
            XCTAssertEqual(loaded.fiveHour, saved.fiveHour)
            XCTAssertFalse(FetchPolicy.shouldFetch(idle(FetchPolicy.Session(loaded), lastAttemptAgo: nil), now: now))
        }
    }

    private func sample(at offset: TimeInterval, resetsAt resetOffset: TimeInterval) -> UsageSample {
        UsageSample(at: now.addingTimeInterval(offset), percent: 10, resetsAt: now.addingTimeInterval(resetOffset))
    }

    func testFreeReadPollsWhileActiveAndEveryFewMinutesWhenIdle() {
        XCTAssertTrue(FetchPolicy.shouldRead(force: false, isActive: false, lastAttemptAt: nil, now: now))
        XCTAssertFalse(FetchPolicy.shouldRead(force: false, isActive: false, lastAttemptAt: now.addingTimeInterval(-2 * 60), now: now))
        XCTAssertTrue(FetchPolicy.shouldRead(force: false, isActive: false, lastAttemptAt: now.addingTimeInterval(-6 * 60), now: now))
        XCTAssertTrue(FetchPolicy.shouldRead(force: false, isActive: true, lastAttemptAt: now.addingTimeInterval(-10), now: now))
        XCTAssertTrue(FetchPolicy.shouldRead(force: true, isActive: false, lastAttemptAt: now.addingTimeInterval(-10), now: now))
    }

    func testActivityStillPollsRegardlessOfWindow() {
        var inputs = idle(resetsIn: nil, lastAttemptAgo: 10)
        inputs.isActive = true
        XCTAssertTrue(FetchPolicy.shouldFetch(inputs, now: now))
        inputs.hasToken = false
        XCTAssertFalse(FetchPolicy.shouldFetch(inputs, now: now))
    }
}
