import Foundation

enum PopoverLayout {
    static let compactThreshold = 3

    static func isCompact(_ accounts: [AccountUsage]) -> Bool {
        accounts.count >= compactThreshold
    }

    static func showsProviders(_ accounts: [AccountUsage]) -> Bool {
        Set(accounts.map(\.isCodex)).count > 1
    }

    static func worstRisk(of account: AccountUsage, in forecasts: [String: AccountForecasts]) -> ForecastRisk? {
        guard account.tokenFailure == nil else { return nil }
        return forecasts[account.id]?.values.map(\.risk).max()
    }

    static func defaultExpanded(_ accounts: [AccountUsage], forecasts: [String: AccountForecasts]) -> String? {
        var riskiest: (id: String, risk: ForecastRisk)?
        for account in accounts {
            guard let risk = worstRisk(of: account, in: forecasts),
                  risk > (riskiest?.risk ?? .onPace)
            else { continue }
            riskiest = (account.id, risk)
        }
        return riskiest?.id
    }

    static let noneExpanded = ""

    static func expanded(stored: String?, _ accounts: [AccountUsage], forecasts: [String: AccountForecasts]) -> String? {
        guard let stored else { return defaultExpanded(accounts, forecasts: forecasts) }
        if stored == noneExpanded { return nil }
        guard accounts.contains(where: { $0.id == stored }) else {
            return defaultExpanded(accounts, forecasts: forecasts)
        }
        return stored
    }

    static func ordered(_ accounts: [AccountUsage], by savedOrder: [String]) -> [AccountUsage] {
        let position = Dictionary(savedOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return accounts.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (position[lhs.element.id] ?? Int.max, position[rhs.element.id] ?? Int.max)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    static func moved(_ ids: [String], _ id: String, onto target: String) -> [String] {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return ids }
        var result = ids
        result.insert(result.remove(at: from), at: to)
        return result
    }
}
