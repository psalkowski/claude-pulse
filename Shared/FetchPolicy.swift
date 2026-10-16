import Foundation

enum FetchPolicy {
    static let idleInterval: TimeInterval = 5 * 60
    static let idleSafetyMargin: TimeInterval = 2 * 60

    struct Inputs {
        var hasToken: Bool
        var force: Bool
        var keepAlive: Bool
        var isActive: Bool
        var sessionResetsAt: Date?
        var lastAttemptAt: Date?
    }

    static func shouldFetch(_ inputs: Inputs, now: Date) -> Bool {
        guard inputs.hasToken else { return false }
        if inputs.force || inputs.keepAlive || inputs.isActive { return true }
        guard let resetsAt = inputs.sessionResetsAt,
              resetsAt.timeIntervalSince(now) >= idleSafetyMargin
        else { return false }
        return inputs.lastAttemptAt.map { now.timeIntervalSince($0) >= idleInterval } ?? true
    }

    static func shouldRead(force: Bool, isActive: Bool, lastAttemptAt: Date?, now: Date) -> Bool {
        if force || isActive { return true }
        return lastAttemptAt.map { now.timeIntervalSince($0) >= idleInterval } ?? true
    }
}
