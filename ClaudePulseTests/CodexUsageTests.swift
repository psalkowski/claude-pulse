import XCTest

private final class RejectingProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"detail":"Could not parse your authentication token."}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class CodexUsageTests: XCTestCase {
    private func jwt(_ claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(payload).signature"
    }

    private func authJSON(mode: String, accessToken: String?, idToken: String?) -> Data {
        var tokens: [String: Any] = ["account_id": "acct-1", "refresh_token": "r"]
        tokens["access_token"] = accessToken
        tokens["id_token"] = idToken
        return try! JSONSerialization.data(withJSONObject: ["auth_mode": mode, "tokens": tokens])
    }

    private func window(_ seconds: Int, used: Double, resetAt: Int) -> [String: Any] {
        ["used_percent": used, "limit_window_seconds": seconds, "reset_after_seconds": 100, "reset_at": resetAt]
    }

    private func usageJSON(primary: [String: Any]?, secondary: [String: Any]?) -> Data {
        let limit: [String: Any] = [
            "allowed": true, "limit_reached": false,
            "primary_window": primary ?? NSNull(), "secondary_window": secondary ?? NSNull(),
        ]
        return try! JSONSerialization.data(withJSONObject: ["plan_type": "pro", "rate_limit": limit])
    }

    func testChatGPTSignInIsReadAsASubscriptionAndAPIKeyIsNot() {
        let expiry = 1_792_000_000
        let identity = jwt([
            "email": "you@example.com",
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-1", "chatgpt_plan_type": "pro"],
        ])
        let account = CodexAccount.parse(authJSON: authJSON(mode: "chatgpt", accessToken: jwt(["exp": expiry]), idToken: identity))

        XCTAssertEqual(account?.id, "codex:acct-1")
        XCTAssertEqual(account?.title, "ChatGPT Pro")
        XCTAssertEqual(account?.email, "you@example.com")
        XCTAssertEqual(account?.isExpired(at: Date(timeIntervalSince1970: TimeInterval(expiry - 1))), false)
        XCTAssertEqual(account?.isExpired(at: Date(timeIntervalSince1970: TimeInterval(expiry))), true)

        XCTAssertNil(CodexAccount.parse(authJSON: authJSON(mode: "apikey", accessToken: nil, idToken: nil)))
    }

    func testWindowsAreAssignedByTheirLengthNotTheirSlot() throws {
        let weeklyOnly = try CodexUsageClient.report(from: usageJSON(
            primary: window(604_800, used: 22, resetAt: 1_792_649_592), secondary: nil))
        XCTAssertNil(weeklyOnly.fiveHour)
        XCTAssertEqual(weeklyOnly.sevenDay, UsageWindow(utilization: 22, resetsAt: Date(timeIntervalSince1970: 1_792_649_592)))

        let both = try CodexUsageClient.report(from: usageJSON(
            primary: window(604_800, used: 40, resetAt: 2_000), secondary: window(18_000, used: 7.5, resetAt: 1_000)))
        XCTAssertEqual(both.fiveHour?.utilization, 7.5)
        XCTAssertEqual(both.sevenDay?.utilization, 40)

        XCTAssertThrowsError(try CodexUsageClient.report(from: usageJSON(
            primary: window(86_400, used: 10, resetAt: 1_000), secondary: nil))) { error in
            guard case UsageClientError.noUsageData = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testFailedSignInKeepsTheLastNumbersAndRecoversOnceCodexRefreshes() async {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let resetsAt = now.addingTimeInterval(3 * 86400)
        func account(expiresIn: TimeInterval) -> CodexAccount {
            CodexAccount(accountID: "acct-1", email: nil, plan: "pro", accessToken: "token",
                         accessTokenExpiresAt: now.addingTimeInterval(expiresIn))
        }
        var reads = 0
        func poll(_ account: CodexAccount, after previous: AccountUsage?, lastAttemptAgo: TimeInterval,
                  answer: Result<UsageReport, Error>) async -> AccountUsage {
            await AccountRefresh.codex(
                account: account, previous: previous, force: false, isActive: false,
                lastAttemptAt: now.addingTimeInterval(-lastAttemptAgo), now: now
            ) { _ in
                reads += 1
                return try answer.get()
            }.usage
        }
        let earlier = AccountUsage(id: "codex:acct-1", label: "ChatGPT Pro",
                                   sevenDay: UsageWindow(utilization: 40, resetsAt: resetsAt), provider: .codex)
        let refreshed = UsageReport(sevenDay: UsageWindow(utilization: 45, resetsAt: resetsAt))

        let expired = await poll(account(expiresIn: -60), after: earlier, lastAttemptAgo: 600, answer: .success(refreshed))
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(expired.tokenFailure, .expired)
        XCTAssertEqual(expired.sevenDay?.utilization, 40)

        let recovered = await poll(account(expiresIn: 86400), after: expired, lastAttemptAgo: 600, answer: .success(refreshed))
        XCTAssertEqual(reads, 1)
        XCTAssertNil(recovered.tokenFailure)
        XCTAssertEqual(recovered.sevenDay?.utilization, 45)

        let rejected = await poll(account(expiresIn: 86400), after: recovered, lastAttemptAgo: 600,
                                  answer: .failure(UsageClientError.unauthorized(.invalid)))
        XCTAssertEqual(rejected.tokenFailure, .invalid)
        XCTAssertEqual(rejected.sevenDay?.utilization, 45)

        let notDue = await poll(account(expiresIn: 86400), after: rejected, lastAttemptAgo: 60, answer: .success(refreshed))
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(notDue.tokenFailure, .invalid)
    }

    func testRejectedSignInIsReportedAsATokenFailure() async {
        let configuration = UsageClient.configuration()
        configuration.protocolClasses = [RejectingProtocol.self]
        var client = CodexUsageClient()
        client.session = URLSession(configuration: configuration)
        let account = CodexAccount(accountID: "acct-1", email: nil, plan: "pro", accessToken: "token", accessTokenExpiresAt: nil)

        do {
            _ = try await client.fetch(account)
            XCTFail("a 401 must not produce a report")
        } catch UsageClientError.unauthorized(let failure) {
            XCTAssertEqual(failure, .invalid)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(RejectingProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(RejectingProtocol.lastRequest?.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct-1")
    }
}
