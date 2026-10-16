import XCTest

final class UsageHistoryFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private func history(account: String, percent: Double) -> UsageHistory {
        let sample = UsageSample(at: Date(timeIntervalSince1970: 1_800_000_000), percent: percent, resetsAt: Date(timeIntervalSince1970: 1_800_018_000))
        return UsageHistory(samples: [account: [.fiveHour: [sample]]])
    }

    func testFailedWriteIsRetriedUntilItLands() throws {
        let blocker = directory.appendingPathComponent("support")
        try Data().write(to: blocker)
        let file = UsageHistoryFile(url: blocker.appendingPathComponent("usage-history.json"))
        let recorded = history(account: "a", percent: 5)

        _ = file.save(recorded)
        XCTAssertTrue(file.hasUnsavedChanges)

        try FileManager.default.removeItem(at: blocker)
        _ = file.save(recorded)
        XCTAssertFalse(file.hasUnsavedChanges)
        XCTAssertEqual(UsageHistoryFile(url: file.url).load(), recorded)
    }

    func testUnreadableHistoryIsNeverOverwrittenAndIsMergedOnceReadable() throws {
        let url = directory.appendingPathComponent("usage-history.json")
        let onDisk = history(account: "a", percent: 5)
        _ = UsageHistoryFile(url: url).save(onDisk)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)

        let file = UsageHistoryFile(url: url)
        XCTAssertNil(file.load())
        let recorded = history(account: "b", percent: 7)
        _ = file.save(recorded)
        XCTAssertTrue(file.hasUnsavedChanges)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(UsageHistoryFile(url: url).load(), onDisk)
        let merged = file.save(recorded)
        XCTAssertEqual(Set(merged.samples.keys), ["a", "b"])
        XCTAssertEqual(UsageHistoryFile(url: url).load(), merged)
    }

    func testHistoryUnreadableAtLaunchIsPickedUpOnceReadableWithoutNewReadings() throws {
        let url = directory.appendingPathComponent("usage-history.json")
        let onDisk = history(account: "a", percent: 5)
        _ = UsageHistoryFile(url: url).save(onDisk)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)

        let file = UsageHistoryFile(url: url)
        let launched = file.load() ?? UsageHistory()
        XCTAssertEqual(file.reconcile(launched), UsageHistory())

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(file.reconcile(launched), onDisk)
        XCTAssertFalse(file.isBlocked)
    }

    func testCorruptHistoryIsSetAsideInsteadOfLost() throws {
        let url = directory.appendingPathComponent("usage-history.json")
        try Data("not json".utf8).write(to: url)

        XCTAssertEqual(UsageHistoryFile(url: url).load(), UsageHistory())
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("usage-history.unreadable.json")), Data("not json".utf8))
    }
}
