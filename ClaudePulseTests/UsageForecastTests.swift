import XCTest

final class UsageForecastTests: XCTestCase {
    private let hour: TimeInterval = 3600
    private let pastWeeks = 3

    private func date(day: Int, hour hourOfDay: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hourOfDay))!
    }

    private func monday(_ week: Int) -> Date { date(day: 5 + week * 7) }

    private var thursdayMorning: Date { date(day: 5 + pastWeeks * 7 + 3, hour: 8) }

    private var nextMonday: Date { monday(pastWeeks + 1) }

    private func isWorkHour(_ date: Date) -> Bool {
        let components = Calendar.current.dateComponents([.weekday, .hour], from: date)
        return (2...6).contains(components.weekday!) && (10..<17).contains(components.hour!)
    }

    private func workWeekSamples() -> [UsageSample] {
        (0..<pastWeeks).flatMap { week -> [UsageSample] in
            var percent = 0.0
            return (0...(7 * 24)).map { offset in
                let at = monday(week).addingTimeInterval(Double(offset) * hour)
                defer { if isWorkHour(at) { percent += 1 } }
                return UsageSample(at: at, percent: percent, resetsAt: monday(week + 1))
            }
        }
    }

    private func weeklyForecast(used: Double, seed: [Double]? = nil) -> UsageForecast {
        let samples = workWeekSamples() + [
            UsageSample(at: monday(pastWeeks), percent: 0, resetsAt: nextMonday),
            UsageSample(at: thursdayMorning, percent: used, resetsAt: nextMonday),
        ]
        return UsageForecaster.forecast(
            kind: .sevenDay, samples: samples, used: used, resetsAt: nextMonday, now: thursdayMorning, seed: seed)
    }

    private func singleReadingForecast(used: Double, seed: [Double]? = nil) -> UsageForecast {
        let now = thursdayMorning
        let resetsAt = now.addingTimeInterval(19 * hour)
        return UsageForecaster.forecast(
            kind: .sevenDay,
            samples: [UsageSample(at: now, percent: used, resetsAt: resetsAt)],
            used: used, resetsAt: resetsAt, now: now, seed: seed)
    }

    func testOvershootingWeekIsLikelyWithHitHourAndPause() throws {
        let forecast = weeklyForecast(used: 90)

        XCTAssertTrue(forecast.isLearned)
        XCTAssertGreaterThan(try XCTUnwrap(forecast.probability), 0.8)
        XCTAssertEqual(Calendar.current.component(.weekday, from: try XCTUnwrap(forecast.hitAt)), 6)
        let pause = try XCTUnwrap(forecast.pauseMinutes)
        XCTAssertGreaterThan(pause, 6 * 60)
        XCTAssertLessThan(pause, 12 * 60)
        XCTAssertEqual(forecast.risk, .likely)
    }

    func testWeekWithHeadroomIsOnPace() throws {
        let forecast = weeklyForecast(used: 40)

        XCTAssertLessThan(try XCTUnwrap(forecast.probability), 0.05)
        XCTAssertEqual(forecast.risk, .onPace)
    }

    func testTooLittleHistoryFallsBackToCurrentPace() {
        let forecast = singleReadingForecast(used: 90)

        XCTAssertEqual(forecast.basis, .pace)
        XCTAssertNil(forecast.probability)
    }

    func testNearLimitWithoutHistoryIsAtRiskAndSaysWhenItRunsOut() throws {
        XCTAssertEqual(singleReadingForecast(used: 88).risk, .atRisk)

        let running = singleReadingForecast(used: 92)
        let hitAt = try XCTUnwrap(running.hitAt)
        XCTAssertGreaterThan(hitAt, thursdayMorning)
        XCTAssertLessThan(hitAt, thursdayMorning.addingTimeInterval(19 * hour))
    }

    func testHistorySeedGivesRhythmForecastFromFirstReading() {
        let forecast = singleReadingForecast(used: 88, seed: Array(repeating: 1, count: HourOfWeek.count))

        XCTAssertEqual(forecast.basis, .history)
        XCTAssertGreaterThan(forecast.expected, 10)
        XCTAssertLessThan(forecast.expected, 13)
        XCTAssertGreaterThanOrEqual(forecast.risk, .atRisk)
    }

    func testUnchangedReadingIsRecordedOnce() {
        let sample = UsageSample(at: Date(timeIntervalSince1970: 0), percent: 5, resetsAt: Date(timeIntervalSince1970: 3600))
        var later = sample
        later.at = sample.at.addingTimeInterval(60)

        XCTAssertEqual(UsageForecaster.record(later, into: [sample]), [sample])
    }

    func testSteppingThroughAutumnClockChangeTerminates() {
        let beforeChange = date(day: 24, hour: 12)
        let after = beforeChange.addingTimeInterval(72 * hour)
        let forecast = UsageForecaster.forecast(
            kind: .sevenDay,
            samples: [
                UsageSample(at: beforeChange, percent: 10, resetsAt: nextMonday),
                UsageSample(at: after, percent: 20, resetsAt: nextMonday),
            ],
            used: 20, resetsAt: nextMonday, now: after)

        XCTAssertEqual(forecast.spanDays, 3, accuracy: 1e-9)
    }

    func testTranscriptCountsBecomeWeightsWithMeanOneAndShortHistoryIsRejected() throws {
        let counts = (0..<HourOfWeek.count).map { $0 % 24 >= 8 ? 10 : 0 }
        let start = Date(timeIntervalSince1970: 0)
        let weights = try XCTUnwrap(UsageForecaster.seedWeights(
            TranscriptActivity(counts: counts, first: start, last: start.addingTimeInterval(10 * 86400), total: 1000)))

        XCTAssertEqual(weights.reduce(0, +) / Double(HourOfWeek.count), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(weights[12], weights[3])
        XCTAssertNil(UsageForecaster.seedWeights(
            TranscriptActivity(counts: counts, first: start, last: start.addingTimeInterval(2 * 86400), total: 1000)))
    }
}
