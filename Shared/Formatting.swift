import SwiftUI

enum UsageFormat {
    static func glyph(_ percentage: Double) -> String {
        switch percentage {
        case 88...: return "●"
        case 63...: return "◕"
        case 38...: return "◑"
        case 13...: return "◔"
        default: return "○"
        }
    }

    static func color(_ percentage: Double) -> Color {
        switch percentage {
        case 70...: return .red
        case 30...: return .orange
        default: return .green
        }
    }

    static func percentText(_ percentage: Double) -> String {
        "\(Int(percentage.rounded()))% used"
    }

    static func resetText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Resets momentarily" }
        if interval < 24 * 3600 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            if hours > 0 { return "Resets in \(hours) hr \(minutes) min" }
            return "Resets in \(minutes) min"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return "Resets \(formatter.string(from: date))"
    }

    static func shortResetText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "resets now" }
        if interval < 24 * 3600 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            if hours > 0 { return "\(hours)h \(minutes)m" }
            return "\(minutes)m"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }
}

extension UsageFormat {
    static func riskColor(_ risk: ForecastRisk) -> Color {
        switch risk {
        case .onPace: return .green
        case .atRisk: return .orange
        case .likely: return .red
        }
    }

    static func riskLabel(_ risk: ForecastRisk) -> String {
        switch risk {
        case .onPace: return "On pace"
        case .atRisk: return "At risk"
        case .likely: return "Likely to hit"
        }
    }

    static func shortTitle(_ kind: UsageWindowKind) -> String {
        switch kind {
        case .fiveHour: return "Session"
        case .sevenDay: return "Week"
        case .sevenDayOpus: return "Opus"
        case .sevenDayFable: return "Fable"
        }
    }

    static func endNoun(_ kind: UsageWindowKind) -> String {
        kind == .fiveHour ? "session" : "week"
    }

    static func moment(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }

    static func pause(_ minutes: Double) -> String {
        minutes < 90 ? "\(Int(minutes.rounded()))m" : "\(Int((minutes / 60).rounded()))h"
    }

    static func advice(_ forecast: UsageForecast) -> String? {
        if forecast.needsCut {
            let pause = forecast.pauseMinutes.map { ", or pause ~\(Self.pause($0))" } ?? ""
            return "Use ~\(forecast.cutPercent)% less\(pause)"
        }
        guard let room = forecast.spareRoom else { return nil }
        if room >= 2 { return "Plenty of room to spare" }
        if room < 0.1 { return "Little room to spare" }
        return "Room for ~\(UsageForecast.rounded(room * 100, step: 5))% more than usual"
    }

    static func learningNote(_ forecasts: [UsageForecast]) -> String? {
        if forecasts.contains(where: { $0.basis == .pace }) {
            let days = forecasts.map(\.spanDays).min() ?? 0
            let day = min(2, Int(days.rounded(.down)) + 1)
            return "Learning your usage pattern: day \(day) of 2. Until then, forecasts assume your current pace."
        }
        if forecasts.contains(where: { $0.basis == .history }) {
            return "Forecast based on your past sessions, adapting as new data arrives."
        }
        return nil
    }
}
