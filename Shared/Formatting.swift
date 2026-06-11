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
