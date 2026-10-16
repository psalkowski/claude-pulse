import XCTest

final class FetchPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func idle(resetsIn: TimeInterval?, lastAttemptAgo: TimeInterval?) -> FetchPolicy.Inputs {
        FetchPolicy.Inputs(
            hasToken: true, force: false, keepAlive: false, isActive: false,
            sessionResetsAt: resetsIn.map { now.addingTimeInterval($0) },
            lastAttemptAt: lastAttemptAgo.map { now.addingTimeInterval(-$0) })
    }

    func testIdleAccountPollsEveryFewMinutesOnlyWhileItsWindowStaysOpen() {
        XCTAssertTrue(FetchPolicy.shouldFetch(idle(resetsIn: 3 * 3600, lastAttemptAgo: 6 * 60), now: now))
        XCTAssertFalse(FetchPolicy.shouldFetch(idle(resetsIn: 3 * 3600, lastAttemptAgo: 2 * 60), now: now))
        XCTAssertFalse(FetchPolicy.shouldFetch(idle(resetsIn: 60, lastAttemptAgo: nil), now: now))
        XCTAssertFalse(FetchPolicy.shouldFetch(idle(resetsIn: nil, lastAttemptAgo: nil), now: now))
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
