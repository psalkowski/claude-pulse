import XCTest

final class PopoverLayoutTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func account(_ id: String, codex: Bool = false, tokenFailure: TokenFailure? = nil) -> AccountUsage {
        AccountUsage(id: id, label: id, tokenFailure: tokenFailure, provider: codex ? .codex : nil)
    }

    private func forecast(projected: Double) -> AccountForecasts {
        [.sevenDay: UsageForecast(
            kind: .sevenDay, used: projected / 2, resetsAt: now.addingTimeInterval(86400), basis: .pace,
            expected: projected / 2, probability: nil, budget: 50, hitAt: nil, pauseMinutes: nil, spanDays: 0)]
    }

    func testTheRiskiestSubscriptionOpensFirstAndCalmListsStayCollapsed() {
        let accounts = [
            account("calm"), account("risky"), account("likely"), account("also-likely"),
            account("failing", tokenFailure: .expired),
        ]
        let forecasts: [String: AccountForecasts] = [
            "calm": forecast(projected: 20),
            "risky": forecast(projected: 90),
            "likely": forecast(projected: 140),
            "also-likely": forecast(projected: 180),
            "failing": forecast(projected: 300),
        ]

        XCTAssertEqual(PopoverLayout.defaultExpanded(accounts, forecasts: forecasts), "likely")
        XCTAssertNil(PopoverLayout.defaultExpanded(Array(accounts.prefix(1)), forecasts: forecasts))
    }

    func testWidgetSlotsGoToMenuBarSubscriptionsFirst() {
        let accounts = [account("max"), account("team"), account("wsd"), account("codex:1", codex: true)]

        let twoHidden = UsageSnapshot(fetchedAt: now, accounts: accounts, hiddenAccountIDs: ["team", "wsd"])
        XCTAssertEqual(twoHidden.widgetAccounts.prefix(2).map(\.id), ["max", "codex:1"])

        let allHidden = UsageSnapshot(fetchedAt: now, accounts: accounts, hiddenAccountIDs: accounts.map(\.id))
        XCTAssertEqual(allHidden.widgetAccounts.map(\.id), accounts.map(\.id))
    }

    func testChosenExpansionSurvivesUntilItsSubscriptionDisappears() {
        let accounts = [account("a"), account("b"), account("c")]
        let forecasts: [String: AccountForecasts] = ["c": forecast(projected: 140)]

        XCTAssertEqual(PopoverLayout.expanded(stored: nil, accounts, forecasts: forecasts), "c")
        XCTAssertEqual(PopoverLayout.expanded(stored: "a", accounts, forecasts: forecasts), "a")
        XCTAssertNil(PopoverLayout.expanded(stored: PopoverLayout.noneExpanded, accounts, forecasts: forecasts))
        XCTAssertEqual(PopoverLayout.expanded(stored: "gone", accounts, forecasts: forecasts), "c")
    }

    func testSavedOrderLeadsAndNewSubscriptionsFollowInTheirDefaultOrder() {
        let accounts = [account("a"), account("b"), account("c"), account("d")]

        XCTAssertEqual(PopoverLayout.ordered(accounts, by: []).map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(PopoverLayout.ordered(accounts, by: ["c", "gone", "a"]).map(\.id), ["c", "a", "b", "d"])
    }

    func testDroppingOntoASubscriptionTakesItsPlace() {
        let ids = ["a", "b", "c", "d"]

        XCTAssertEqual(PopoverLayout.moved(ids, "a", onto: "c"), ["b", "c", "a", "d"])
        XCTAssertEqual(PopoverLayout.moved(ids, "d", onto: "b"), ["a", "d", "b", "c"])
        XCTAssertEqual(PopoverLayout.moved(ids, "a", onto: "a"), ids)
        XCTAssertEqual(PopoverLayout.moved(ids, "stranger", onto: "b"), ids)
    }
}
