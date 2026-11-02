import Foundation

enum FetchPolicy {
    static let idleInterval: TimeInterval = 5 * 60
    static let idleSafetyMargin: TimeInterval = 2 * 60

    enum Session: Equatable {
        case unknown
        case window(resetsAt: Date?)
        case notOffered

        init(_ usage: AccountUsage?) {
            if let fiveHour = usage?.fiveHour {
                self = .window(resetsAt: fiveHour.resetsAt)
            } else if usage?.sevenDay != nil {
                self = .notOffered
            } else {
                self = .unknown
            }
        }
    }

    struct Inputs {
        var hasToken: Bool
        var force: Bool
        var keepAlive: Bool
        var isActive: Bool
        var session: Session
        var lastAttemptAt: Date?
    }

    static func shouldFetch(_ inputs: Inputs, now: Date) -> Bool {
        guard inputs.hasToken else { return false }
        if inputs.force || inputs.keepAlive || inputs.isActive { return true }
        guard allowsIdlePolling(inputs.session, now: now) else { return false }
        return inputs.lastAttemptAt.map { now.timeIntervalSince($0) >= idleInterval } ?? true
    }

    private static func allowsIdlePolling(_ session: Session, now: Date) -> Bool {
        switch session {
        case .notOffered: true
        case .window(let resetsAt?): resetsAt.timeIntervalSince(now) >= idleSafetyMargin
        case .window(nil), .unknown: false
        }
    }

    static func shouldRead(force: Bool, isActive: Bool, lastAttemptAt: Date?, now: Date) -> Bool {
        if force || isActive { return true }
        return lastAttemptAt.map { now.timeIntervalSince($0) >= idleInterval } ?? true
    }
}
