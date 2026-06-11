import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: UsageEntry
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        if entry.snapshot.accounts.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "gauge.with.needle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Open Claude Pulse to load usage")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(entry.snapshot.accounts.prefix(2)) { account in
                        AccountColumn(account: account)
                        if account.id != entry.snapshot.accounts.prefix(2).last?.id {
                            Divider()
                        }
                    }
                }
                staleFooter
            }
        default:
            VStack(spacing: 4) {
                if let account = entry.snapshot.accounts.first {
                    AccountColumn(account: account)
                }
                staleFooter
            }
        }
    }

    @ViewBuilder
    private var staleFooter: some View {
        if entry.snapshot.fetchedAt < Date().addingTimeInterval(-15 * 60) {
            HStack {
                Spacer()
                Text("Updated \(entry.snapshot.fetchedAt, style: .relative) ago")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccountColumn: View {
    let account: AccountUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(account.label)
                        .font(.caption.bold())
                        .lineLimit(1)
                    if account.tokenExpired {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                }
                if let detail = account.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let window = account.fiveHour {
                WindowGauge(title: "Session", window: window)
            }
            if let window = account.sevenDay {
                WindowGauge(title: "Week", window: window)
            }
            if let window = account.sevenDayOpus {
                WindowGauge(title: "Opus", window: window)
            }
            if let window = account.sevenDaySonnet {
                WindowGauge(title: "Sonnet", window: window)
            }
            if !account.hasAnyData {
                Text("No data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WindowGauge: View {
    let title: String
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(UsageFormat.shortResetText(window.resetsAt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.utilization.rounded()))%")
                    .font(.caption2.bold().monospacedDigit())
            }
            UsageBar(fraction: window.utilization / 100, color: UsageFormat.color(window.utilization), height: 5)
        }
    }
}
