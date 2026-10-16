import Foundation

struct CodexAccount: Equatable {
    static let idPrefix = "codex:"

    let accountID: String
    let email: String?
    let plan: String?
    let accessToken: String
    let accessTokenExpiresAt: Date?

    var id: String { Self.idPrefix + accountID }

    var title: String {
        guard let plan, !plan.isEmpty else { return "ChatGPT" }
        return "ChatGPT \(plan.prefix(1).uppercased())\(plan.dropFirst())"
    }

    func isExpired(at now: Date) -> Bool {
        accessTokenExpiresAt.map { $0 <= now } ?? false
    }

    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    static func discover() -> CodexAccount? {
        guard let data = try? Data(contentsOf: homeDirectory.appendingPathComponent("auth.json")) else { return nil }
        return parse(authJSON: data)
    }

    static func lastActivity() -> Date? {
        FileActivity.latestModification(under: homeDirectory.appendingPathComponent("sessions", isDirectory: true))
    }

    static func parse(authJSON data: Data) -> CodexAccount? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["auth_mode"] as? String != "apikey",
              let tokens = root["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty
        else { return nil }

        let identity = (tokens["id_token"] as? String).flatMap { claims(of: $0) } ?? [:]
        let auth = identity["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        guard let accountID = tokens["account_id"] as? String ?? auth["chatgpt_account_id"] as? String,
              !accountID.isEmpty
        else { return nil }

        return CodexAccount(
            accountID: accountID,
            email: identity["email"] as? String,
            plan: auth["chatgpt_plan_type"] as? String,
            accessToken: accessToken,
            accessTokenExpiresAt: (claims(of: accessToken)?["exp"] as? Double).map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func claims(of jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
