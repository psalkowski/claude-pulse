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
}
