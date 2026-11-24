import XCTest

final class GeminiUsageTests: XCTestCase {
    private func bucket(_ id: String, window: String, remaining: Double, resetTime: String) -> [String: Any] {
        ["id": id, "name": id, "window": window, "remaining_fraction": remaining, "reset_time": resetTime]
    }

    private func usageJSON(groups: [[String: Any]]) -> Data {
        let command: [String: Any] = ["name": "usage", "data": ["description": "", "groups": groups]]
        return try! JSONSerialization.data(withJSONObject: [
            "conversation_id": "", "status": "SUCCESS", "response": "", "command": command,
        ])
    }

    private let geminiGroup: [String: Any] = [
        "name": "Gemini Models",
        "description": "Models within this group: Gemini 4 Neon",
        "buckets": [
            ["id": "gemini-weekly", "name": "Weekly Limit Remaining", "window": "weekly",
             "remaining_fraction": 0.9174273610115051, "reset_time": "2026-12-01T11:32:45Z"],
            ["id": "gemini-5h", "name": "Five Hour Limit Remaining", "window": "5h",
             "remaining_fraction": 1, "reset_time": "1970-01-01T00:00:00Z"],
        ],
    ]

    private let thirdPartyGroup: [String: Any] = [
        "name": "Claude and GPT models",
        "description": "Models within this group: Claude Opus 5.5",
        "buckets": [
            ["id": "3p-weekly", "name": "Weekly Limit Remaining", "window": "weekly",
             "remaining_fraction": 0.5, "reset_time": "2026-11-30T08:00:00Z"],
            ["id": "3p-5h", "name": "Five Hour Limit Remaining", "window": "5h",
             "remaining_fraction": 0.25, "reset_time": "2026-11-24T18:48:01Z"],
        ],
    ]

    func testOnlyTheGeminiGroupIsReadAndAFullWindowHasNoReset() throws {
        let report = try GeminiUsageClient.report(from: usageJSON(groups: [thirdPartyGroup, geminiGroup]))

        XCTAssertEqual(report.fiveHour, UsageWindow(utilization: 0, resetsAt: nil))
        let weekly = try XCTUnwrap(report.sevenDay)
        XCTAssertEqual(weekly.utilization, 8.257, accuracy: 0.001)
        XCTAssertEqual(weekly.resetsAt, ISO8601DateFormatter().date(from: "2026-12-01T11:32:45Z"))

        XCTAssertThrowsError(try GeminiUsageClient.report(from: usageJSON(groups: [thirdPartyGroup]))) { error in
            guard case UsageClientError.noUsageData = error else { return XCTFail("unexpected \(error)") }
        }
    }

    private func script(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agy-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func failure(of client: GeminiUsageClient) async -> String? {
        do {
            _ = try await client.fetch()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func testAgyFailingOrHangingIsReportedInItsOwnWords() async throws {
        let refused = try script("echo 'Not signed in to Antigravity.' >&2; exit 2")
        let refusal = await failure(of: GeminiUsageClient(executable: refused))
        XCTAssertEqual(refusal, "Not signed in to Antigravity.")

        let silent = try script("exit 3")
        let silence = await failure(of: GeminiUsageClient(executable: silent))
        XCTAssertEqual(silence, "agy exited with code 3")

        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("agy-pid-\(UUID().uuidString)")
        let hanging = try script("echo $$ > '\(pidFile.path)'; exec sleep 20")
        let started = Date()
        let timeout = await failure(of: GeminiUsageClient(executable: hanging, timeout: 1))
        XCTAssertEqual(timeout, "agy didn't answer within 1 s")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)

        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        let pid = try XCTUnwrap(pid_t(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
        addTeardownBlock {
            kill(pid, SIGKILL)
            try? FileManager.default.removeItem(at: pidFile)
        }
        let deadline = Date().addingTimeInterval(2)
        while kill(pid, 0) == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotEqual(kill(pid, 0), 0, "agy is still running after the timeout")
    }

    func testActivityIsReadFromAgyTranscriptsInsideItsHiddenFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agy-state-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let logs = root.appendingPathComponent("brain/conversation-1/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let transcript = logs.appendingPathComponent("transcript.jsonl")
        try Data("{}\n".utf8).write(to: transcript)
        let writtenAt = Date(timeIntervalSince1970: 1_795_000_000)
        try FileManager.default.setAttributes([.modificationDate: writtenAt], ofItemAtPath: transcript.path)

        XCTAssertEqual(GeminiUsageClient.lastActivity(in: root), writtenAt)
    }

    func testAFailedReadStaysVisibleUntilTheNextReadClearsIt() async {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let resetsAt = now.addingTimeInterval(3 * 86400)
        var reads = 0
        func poll(after previous: AccountUsage?, lastAttemptAgo: TimeInterval,
                  answer: Result<UsageReport, Error>) async -> AccountUsage {
            await AccountRefresh.read(
                GeminiUsageClient.usage, previous: previous, force: false, isActive: false,
                lastAttemptAt: now.addingTimeInterval(-lastAttemptAgo), now: now
            ) {
                reads += 1
                return try answer.get()
            }.usage
        }
        let earlier = AccountUsage(id: GeminiUsageClient.usage.id, label: "Gemini",
                                   sevenDay: UsageWindow(utilization: 8, resetsAt: resetsAt), provider: .gemini)
        let refreshed = UsageReport(sevenDay: UsageWindow(utilization: 9, resetsAt: resetsAt))

        let failed = await poll(after: earlier, lastAttemptAgo: 600,
                                answer: .failure(UsageClientError.commandFailed("Not signed in to Antigravity.")))
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(failed.fetchError, "Not signed in to Antigravity.")
        XCTAssertEqual(failed.sevenDay?.utilization, 8)

        let skipped = await poll(after: failed, lastAttemptAgo: 60, answer: .success(refreshed))
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(skipped.fetchError, "Not signed in to Antigravity.")
        XCTAssertEqual(skipped.sevenDay?.utilization, 8)

        let recovered = await poll(after: skipped, lastAttemptAgo: 600, answer: .success(refreshed))
        XCTAssertEqual(reads, 2)
        XCTAssertNil(recovered.fetchError)
        XCTAssertEqual(recovered.sevenDay?.utilization, 9)
        XCTAssertEqual(recovered.provider, .gemini)
        XCTAssertEqual(recovered.label, "Gemini")
    }
}
