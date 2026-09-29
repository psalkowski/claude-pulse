import Foundation

struct UsageReport {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var sevenDayOpus: UsageWindow?
    var sevenDayFable: UsageWindow?
}

enum UsageClientError: LocalizedError {
    case unauthorized(TokenFailure)
    case rateLimited
    case http(Int)
    case invalidResponse
    case noUsageHeaders

    var errorDescription: String? {
        switch self {
        case .unauthorized(let failure): return "Token \(failure.rawValue) — replace it"
        case .rateLimited: return "Rate limited (429)"
        case .http(let code): return "HTTP \(code)"
        case .invalidResponse: return "Invalid response"
        case .noUsageHeaders: return "No usage headers returned"
        }
    }
}

// Reads subscription usage from the `anthropic-ratelimit-unified-*` headers that
// Anthropic attaches to every /v1/messages response — the same source Claude
// Code uses for its statusline. A minimal 1-token request is enough; the body is
// discarded. This costs ~1 token and (re)starts the 5-hour window, so callers
// should only invoke it when that subscription is actively in use.
struct UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let userAgent = "claude-cli/2.1.173 (external, cli)"
    static let haikuModel = "claude-haiku-4-5-20251001"

    // Use Haiku for every window it returns, including a passive Fable window.
    // Probing Fable directly would consume its limited weekly allowance.
    func fetch(accessToken: String) async throws -> UsageReport {
        try await fetch(accessToken: accessToken, model: Self.haikuModel)
    }

    private func fetch(accessToken: String, model: String) async throws -> UsageReport {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20,claude-code-20250219", forHTTPHeaderField: "anthropic-beta")
        request.setValue("cli", forHTTPHeaderField: "x-app")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "system": "You are Claude Code, Anthropic's official CLI for Claude.",
            "messages": [["role": "user", "content": "ping"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.invalidResponse }

        // Read the usage headers regardless of status — a 429 (limit reached)
        // still carries the unified rate-limit headers, and that's exactly the
        // data we want (it shows the window at ~100%). Only fall back to an
        // error when no usage headers are present at all.
        let fiveHour = window(from: http, prefix: "5h")
        let sevenDay = window(from: http, prefix: "7d")
        if fiveHour != nil || sevenDay != nil {
            return UsageReport(
                fiveHour: fiveHour,
                sevenDay: sevenDay,
                sevenDayOpus: window(from: http, prefix: "7d_opus"),
                sevenDayFable: window(from: http, prefix: "7d_fable")
            )
        }

        switch http.statusCode {
        case 401, 403: throw UsageClientError.unauthorized(Self.tokenFailure(fromErrorBody: data))
        case 429: throw UsageClientError.rateLimited
        case 200: throw UsageClientError.noUsageHeaders
        default: throw UsageClientError.http(http.statusCode)
        }
    }

    // Same patterns Claude Code matches on these messages. Anything else —
    // "OAuth access token is invalid.", "Invalid bearer token" — is invalid.
    static func tokenFailure(fromErrorBody data: Data) -> TokenFailure {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (root?["error"] as? [String: Any])?["message"] as? String ?? ""
        func matches(_ pattern: String) -> Bool {
            message.range(of: pattern, options: .regularExpression) != nil
        }
        if matches(#"^OAuth (?:access )?token has expired\b"#) { return .expired }
        if matches(#"^OAuth (?:access )?token has been revoked\b"#) { return .revoked }
        return .invalid
    }

    private func window(from http: HTTPURLResponse, prefix: String) -> UsageWindow? {
        guard let utilString = header(http, "anthropic-ratelimit-unified-\(prefix)-utilization"),
              let fraction = Double(utilString)
        else { return nil }
        var resetsAt: Date?
        if let resetString = header(http, "anthropic-ratelimit-unified-\(prefix)-reset"),
           let epoch = Double(resetString) {
            resetsAt = Date(timeIntervalSince1970: epoch)
        }
        return UsageWindow(utilization: fraction * 100, resetsAt: resetsAt)
    }

    private func header(_ http: HTTPURLResponse, _ name: String) -> String? {
        (http.value(forHTTPHeaderField: name)).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
