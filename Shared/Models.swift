import Foundation

struct UsageWindow: Codable, Equatable {
    var utilization: Double
    var resetsAt: Date?
}

struct AccountUsage: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var detail: String?
    var subscriptionType: String?
    var tokenExpired: Bool
    var fetchError: String?
    var lastSuccessAt: Date?
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var sevenDayOpus: UsageWindow?
    var sevenDaySonnet: UsageWindow?

    var pingError: String?
    var needsToken: Bool = false
    var configDir: String? = nil

    var hasAnyData: Bool {
        fiveHour != nil || sevenDay != nil || sevenDayOpus != nil || sevenDaySonnet != nil
    }
}

struct UsageSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var accounts: [AccountUsage]

    static let empty = UsageSnapshot(fetchedAt: .distantPast, accounts: [])

    static let sample = UsageSnapshot(
        fetchedAt: Date(),
        accounts: [
            AccountUsage(
                id: "sample-personal",
                label: "Max 20×",
                detail: "you@example.com",
                subscriptionType: "max",
                tokenExpired: false,
                fetchError: nil,
                lastSuccessAt: Date(),
                fiveHour: UsageWindow(utilization: 28, resetsAt: Date().addingTimeInterval(3 * 3600 + 17 * 60)),
                sevenDay: UsageWindow(utilization: 23, resetsAt: Date().addingTimeInterval(2.2 * 86400)),
                sevenDayOpus: nil,
                sevenDaySonnet: UsageWindow(utilization: 1, resetsAt: Date().addingTimeInterval(2.2 * 86400))
            ),
            AccountUsage(
                id: "sample-team",
                label: "Acme Inc.",
                detail: "Premium seat · Max 5× limits",
                subscriptionType: "team",
                tokenExpired: false,
                fetchError: nil,
                lastSuccessAt: Date(),
                fiveHour: UsageWindow(utilization: 45, resetsAt: Date().addingTimeInterval(1 * 3600 + 42 * 60)),
                sevenDay: UsageWindow(utilization: 61, resetsAt: Date().addingTimeInterval(4.5 * 86400)),
                sevenDayOpus: nil,
                sevenDaySonnet: nil
            ),
        ]
    )
}
