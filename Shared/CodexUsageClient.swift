import Foundation

struct CodexUsageClient {
    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let userAgent = "ClaudePulse"
    private static let windowKinds: [UsageWindowKind] = [.fiveHour, .sevenDay]
    private static let windowLengthTolerance = 0.1

    var session = URLSession(configuration: UsageClient.configuration())

    func fetch(_ account: CodexAccount) async throws -> UsageReport {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(account.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.invalidResponse }
        switch http.statusCode {
        case 200: return try Self.report(from: data)
        case 401, 403: throw UsageClientError.unauthorized(.invalid)
        case 429: throw UsageClientError.rateLimited
        default: throw UsageClientError.http(http.statusCode)
        }
    }

    static func report(from data: Data) throws -> UsageReport {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }
        let limits = root["rate_limit"] as? [String: Any] ?? [:]
        var report = UsageReport()
        for key in ["primary_window", "secondary_window"] {
            guard let window = limits[key] as? [String: Any],
                  let seconds = window["limit_window_seconds"] as? Double,
                  let used = window["used_percent"] as? Double,
                  let kind = kind(lasting: seconds)
            else { continue }
            let usage = UsageWindow(
                utilization: used,
                resetsAt: (window["reset_at"] as? Double).map(Date.init(timeIntervalSince1970:))
            )
            switch kind {
            case .fiveHour: report.fiveHour = usage
            default: report.sevenDay = usage
            }
        }
        guard report.fiveHour != nil || report.sevenDay != nil else { throw UsageClientError.noUsageData }
        return report
    }

    private static func kind(lasting seconds: Double) -> UsageWindowKind? {
        windowKinds.first { abs(seconds - $0.cycle) <= $0.cycle * windowLengthTolerance }
    }
}
