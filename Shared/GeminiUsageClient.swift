import Foundation

struct GeminiUsageClient {
    static let usage = AccountUsage(id: "gemini", label: "Gemini", provider: .gemini)
    static let arguments = ["-p", "/usage", "--output-format", "json", "--log-file", "/dev/null"]
    static let defaultTimeout: TimeInterval = 30
    private static let geminiGroupPrefix = "gemini"
    private static let unusedWindowReset = Date(timeIntervalSince1970: 0)

    let executable: URL
    var timeout: TimeInterval = defaultTimeout

    static var stateDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)
    }

    static func installedExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/agy"),
            URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
            URL(fileURLWithPath: "/usr/local/bin/agy"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func lastActivity(in root: URL = stateDirectory) -> Date? {
        let transcripts = root.appendingPathComponent("brain", isDirectory: true)
        return FileActivity.latestModification(under: transcripts, skippingHidden: false)
    }

    func fetch() async throws -> UsageReport {
        let output = try await run()
        guard output.exitCode == 0 else {
            let message = Self.firstLine(of: output.standardError) ?? Self.firstLine(of: output.standardOutput)
            throw UsageClientError.commandFailed(message ?? "agy exited with code \(output.exitCode)")
        }
        return try Self.report(from: output.standardOutput)
    }

    static func report(from data: Data) throws -> UsageReport {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }
        guard root["status"] as? String == "SUCCESS" else {
            let response = (root["response"] as? String).flatMap { firstLine(of: Data($0.utf8)) }
            throw UsageClientError.commandFailed(response ?? "agy couldn't read your usage")
        }
        let command = root["command"] as? [String: Any]
        let payload = command?["data"] as? [String: Any]
        let groups = payload?["groups"] as? [[String: Any]] ?? []
        let gemini = groups.first { ($0["name"] as? String)?.lowercased().hasPrefix(geminiGroupPrefix) == true }
        var report = UsageReport()
        for bucket in gemini?["buckets"] as? [[String: Any]] ?? [] {
            guard let remaining = bucket["remaining_fraction"] as? Double else { continue }
            let window = UsageWindow(utilization: (1 - remaining) * 100, resetsAt: resetDate(bucket["reset_time"]))
            switch bucket["window"] as? String {
            case "5h": report.fiveHour = window
            case "weekly": report.sevenDay = window
            default: continue
            }
        }
        guard report.fiveHour != nil || report.sevenDay != nil else { throw UsageClientError.noUsageData }
        return report
    }

    private static func resetDate(_ value: Any?) -> Date? {
        guard let text = value as? String,
              let date = ISO8601DateFormatter().date(from: text),
              date > unusedWindowReset
        else { return nil }
        return date
    }

    private static func firstLine(of data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline)
        let line = lines.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return line
    }

    private struct Output {
        var exitCode: Int32
        var standardOutput: Data
        var standardError: Data
    }

    private func run() async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments
        process.standardInput = FileHandle.nullDevice
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        let completion = Completion()
        let timeout = timeout

        return try await withCheckedThrowingContinuation { continuation in
            completion.continuation = continuation
            do {
                try process.run()
            } catch {
                completion.finish(.failure(error))
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let errorsRead = DispatchGroup()
                var errors = Data()
                errorsRead.enter()
                DispatchQueue.global(qos: .utility).async {
                    errors = standardError.fileHandleForReading.readDataToEndOfFile()
                    errorsRead.leave()
                }
                let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errorsRead.wait()
                let result = Output(exitCode: process.terminationStatus, standardOutput: output, standardError: errors)
                completion.finish(.success(result))
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                let timedOut = UsageClientError.commandFailed("agy didn't answer within \(Int(timeout)) s")
                guard completion.finish(.failure(timedOut)) else { return }
                process.terminate()
            }
        }
    }

    private final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        var continuation: CheckedContinuation<Output, Error>?

        @discardableResult
        func finish(_ result: Result<Output, Error>) -> Bool {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
            return pending != nil
        }
    }
}
