import Foundation

enum UsageWindowKind: String, Codable, CaseIterable, CodingKeyRepresentable {
    case fiveHour
    case sevenDay
    case sevenDayOpus
    case sevenDayFable

    var cycle: TimeInterval {
        self == .fiveHour ? 5 * HourOfWeek.hour : 168 * HourOfWeek.hour
    }
}

struct UsageSample: Codable, Equatable {
    var at: Date
    var percent: Double
    var resetsAt: Date
}

enum ForecastBasis: String, Codable {
    case pace
    case history
    case own
}

enum ForecastRisk: Int, Comparable {
    case onPace
    case atRisk
    case likely

    static func < (lhs: ForecastRisk, rhs: ForecastRisk) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct TranscriptActivity: Equatable {
    var counts: [Int]
    var first: Date
    var last: Date
    var total: Int
}

typealias AccountForecasts = [UsageWindowKind: UsageForecast]

struct UsageForecast: Equatable {
    var kind: UsageWindowKind
    var used: Double
    var resetsAt: Date
    var basis: ForecastBasis
    var expected: Double
    var probability: Double?
    var budget: Double
    var hitAt: Date?
    var pauseMinutes: Double?
    var spanDays: Double

    var isLearned: Bool { basis != .pace }

    var projected: Double { used + expected }

    var risk: ForecastRisk {
        guard let probability else {
            if projected >= 100 { return .likely }
            return projected >= UsageForecaster.closeProjection ? .atRisk : .onPace
        }
        let crossed = UsageForecaster.riskThresholds.filter { probability >= $0 }.count
        return ForecastRisk(rawValue: crossed) ?? .likely
    }

    var cutPercent: Int {
        guard expected > 0 else { return 0 }
        return Self.rounded((1 - budget / expected) * 100, step: 5)
    }

    var needsCut: Bool { risk > .onPace && cutPercent > 0 }

    var spareRoom: Double? {
        guard risk == .onPace, isLearned, expected > 0 else { return nil }
        return budget / expected - 1
    }

    func elapsedFraction(now: Date) -> Double {
        let left = max(0, resetsAt.timeIntervalSince(now))
        return min(1, max(0, (kind.cycle - left) / kind.cycle))
    }

    static func rounded(_ value: Double, step: Double) -> Int {
        Int((value / step).rounded() * step)
    }
}

enum HourOfWeek {
    static let hour: TimeInterval = 3600
    static let count = 168

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    static func bucket(of date: Date) -> Int {
        let components = calendar.dateComponents([.weekday, .hour], from: date)
        return ((components.weekday ?? 1) - 1) * 24 + (components.hour ?? 0)
    }

    private static func nextStart(after date: Date) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.end ?? date.addingTimeInterval(hour)
    }

    struct Piece {
        var bucket: Int
        var start: Date
        var hours: Double
    }

    static func pieces(from: Date, to: Date) -> [Piece] {
        var pieces: [Piece] = []
        var cursor = from
        while cursor < to {
            let end = min(to, nextStart(after: cursor))
            pieces.append(Piece(bucket: bucket(of: cursor), start: cursor, hours: end.timeIntervalSince(cursor) / hour))
            cursor = end
        }
        return pieces
    }
}

enum UsageForecaster {
    static let history: TimeInterval = 28 * 86400
    static let closeProjection = 85.0
    static let riskThresholds = [0.25, 0.6]

    private static let halfLife: TimeInterval = 14 * 86400
    private static let attribution: TimeInterval = HourOfWeek.hour
    private static let pauseStep: TimeInterval = 5 * 60
    private static let minObservedHours = 48.0
    private static let minBucketHours = 0.25
    private static let safeZ = 1.2816
    private static let dailySigma = 0.4
    private static let modelSigma = 0.5
    private static let fullLearnHours = 14.0 * 24
    private static let seedSpanDays = 10.0
    private static let minSeedElapsedWeight = 0.5
    private static let minSeedEvents = 500
    private static let minSeedSpanDays = 7.0
    private static let seedSmoothing = [0.25, 0.5, 0.25]

    private struct Profile {
        var rates: [Double]
        var observedHours: Double
    }

    static func record(_ sample: UsageSample, into samples: [UsageSample]) -> [UsageSample] {
        let recent = samples.filter { sample.at.timeIntervalSince($0.at) <= history }
        if let last = recent.last, last.resetsAt == sample.resetsAt, last.percent == sample.percent {
            return recent
        }
        return recent + [sample]
    }

    private static func learnProfile(_ samples: [UsageSample], now: Date) -> Profile {
        var usage = [Double](repeating: 0, count: HourOfWeek.count)
        var observed = [Double](repeating: 0, count: HourOfWeek.count)
        var observedHours = 0.0

        for (before, after) in zip(samples, samples.dropFirst()) {
            guard before.resetsAt == after.resetsAt, after.at > before.at else { continue }

            let weight = pow(0.5, now.timeIntervalSince(after.at) / halfLife)
            observedHours += after.at.timeIntervalSince(before.at) / HourOfWeek.hour
            for piece in HourOfWeek.pieces(from: before.at, to: after.at) {
                observed[piece.bucket] += weight * piece.hours
            }

            let attributedFrom = max(before.at, after.at.addingTimeInterval(-attribution))
            let perHour = weight * max(0, after.percent - before.percent) / (after.at.timeIntervalSince(attributedFrom) / HourOfWeek.hour)
            for piece in HourOfWeek.pieces(from: attributedFrom, to: after.at) {
                usage[piece.bucket] += perHour * piece.hours
            }
        }

        let totalObserved = observed.reduce(0, +)
        let mean = totalObserved > 0 ? usage.reduce(0, +) / totalObserved : 0
        let rates = zip(usage, observed).map { value, hours in hours >= minBucketHours ? value / hours : mean }
        return Profile(rates: rates, observedHours: observedHours)
    }

    private static func expected(_ profile: Profile, from: Date, to: Date) -> Double {
        HourOfWeek.pieces(from: from, to: to).reduce(0) { $0 + profile.rates[$1.bucket] * $1.hours }
    }

    private static func hitTime(_ profile: Profile, from: Date, to: Date, headroom: Double) -> Date? {
        var remaining = headroom
        for piece in HourOfWeek.pieces(from: from, to: to) {
            let rate = profile.rates[piece.bucket]
            let amount = rate * piece.hours
            if rate > 0, amount >= remaining {
                return piece.start.addingTimeInterval(remaining / rate * HourOfWeek.hour)
            }
            remaining -= amount
        }
        return nil
    }

    private static func chanceOfHit(headroom: Double, expected: Double, sigma: Double) -> Double {
        if headroom <= 0 { return 1 }
        if expected <= 0 { return 0 }
        let z = (log(headroom / expected) + sigma * sigma / 2) / sigma
        return 1 - 0.5 * (1 + erf(z / 2.0.squareRoot()))
    }

    private static func elapsedHours(_ kind: UsageWindowKind, hoursLeft: Double) -> Double {
        kind.cycle / HourOfWeek.hour - hoursLeft
    }

    private static func paceExpected(_ kind: UsageWindowKind, used: Double, hoursLeft: Double) -> Double {
        let elapsed = elapsedHours(kind, hoursLeft: hoursLeft)
        return elapsed < 1 ? 0 : used / elapsed * hoursLeft
    }

    private static func paceHitAt(_ kind: UsageWindowKind, used: Double, hoursLeft: Double, now: Date, headroom: Double) -> Date? {
        let elapsed = elapsedHours(kind, hoursLeft: hoursLeft)
        guard elapsed >= 1, used > 0 else { return nil }
        let hoursToHit = headroom / (used / elapsed)
        return hoursToHit < hoursLeft ? now.addingTimeInterval(hoursToHit * HourOfWeek.hour) : nil
    }

    private static func seededRates(_ seed: [Double], kind: UsageWindowKind, used: Double, resetsAt: Date, now: Date) -> [Double]? {
        guard used > 0 else { return nil }
        let cycleStart = resetsAt.addingTimeInterval(-kind.cycle)
        let elapsedWeight = HourOfWeek.pieces(from: cycleStart, to: now).reduce(0) { $0 + seed[$1.bucket] * $1.hours }
        guard elapsedWeight >= minSeedElapsedWeight else { return nil }
        let scale = used / elapsedWeight
        return seed.map { $0 * scale }
    }

    private static func pauseNeeded(_ profile: Profile, now: Date, resetsAt: Date, mustSkip: Double) -> Double {
        var low = 0
        var high = Int((resetsAt.timeIntervalSince(now) / pauseStep).rounded(.up))
        while low < high {
            let middle = (low + high) / 2
            let skipped = expected(profile, from: now, to: min(resetsAt, now.addingTimeInterval(Double(middle) * pauseStep)))
            if skipped >= mustSkip {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return Double(low) * pauseStep / 60
    }

    static func forecast(
        kind: UsageWindowKind,
        samples: [UsageSample],
        used: Double,
        resetsAt: Date,
        now: Date,
        seed: [Double]? = nil
    ) -> UsageForecast {
        let hoursLeft = max(0, resetsAt.timeIntervalSince(now) / HourOfWeek.hour)
        let headroom = max(0, 100 - used)
        let own = learnProfile(samples, now: now)
        let ownWeight = own.observedHours < minObservedHours ? 0 : min(1, own.observedHours / fullLearnHours)
        let fromHistory = seed.flatMap { seededRates($0, kind: kind, used: used, resetsAt: resetsAt, now: now) }
        let ownSpanDays = own.observedHours / 24

        guard fromHistory != nil || own.observedHours >= minObservedHours else {
            return UsageForecast(
                kind: kind, used: used, resetsAt: resetsAt, basis: .pace,
                expected: paceExpected(kind, used: used, hoursLeft: hoursLeft),
                probability: nil, budget: headroom,
                hitAt: paceHitAt(kind, used: used, hoursLeft: hoursLeft, now: now, headroom: headroom),
                pauseMinutes: nil, spanDays: ownSpanDays
            )
        }

        let rates = fromHistory.map { history in
            zip(own.rates, history).map { ownWeight * $0 + (1 - ownWeight) * $1 }
        } ?? own.rates
        let profile = Profile(rates: rates, observedHours: own.observedHours)
        let basis: ForecastBasis = fromHistory == nil || ownWeight >= 0.5 ? .own : .history
        let spanDays = max(ownSpanDays, fromHistory == nil ? 0 : seedSpanDays)
        let expectedUsage = expected(profile, from: now, to: resetsAt)
        let sigma = (dailySigma * dailySigma / max(1, hoursLeft / 24) + modelSigma * modelSigma / max(1, spanDays)).squareRoot()
        let budget = headroom / exp(safeZ * sigma - sigma * sigma / 2)

        return UsageForecast(
            kind: kind, used: used, resetsAt: resetsAt, basis: basis,
            expected: expectedUsage,
            probability: chanceOfHit(headroom: headroom, expected: expectedUsage, sigma: sigma),
            budget: budget,
            hitAt: expectedUsage > headroom ? hitTime(profile, from: now, to: resetsAt, headroom: headroom) : nil,
            pauseMinutes: expectedUsage > budget ? pauseNeeded(profile, now: now, resetsAt: resetsAt, mustSkip: expectedUsage - budget) : nil,
            spanDays: spanDays
        )
    }

    static func seedWeights(_ activity: TranscriptActivity) -> [Double]? {
        guard activity.counts.count == HourOfWeek.count,
              activity.total >= minSeedEvents,
              activity.last.timeIntervalSince(activity.first) / 86400 >= minSeedSpanDays
        else { return nil }
        let smoothed = (0..<HourOfWeek.count).map { hour in
            seedSmoothing.enumerated().reduce(0.0) { sum, item in
                let neighbour = (hour + item.offset - 1 + HourOfWeek.count) % HourOfWeek.count
                return sum + item.element * Double(activity.counts[neighbour])
            }
        }
        let mean = smoothed.reduce(0, +) / Double(HourOfWeek.count)
        return mean > 0 ? smoothed.map { $0 / mean } : nil
    }
}
