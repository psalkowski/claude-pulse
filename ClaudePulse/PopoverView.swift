import SwiftUI
import ServiceManagement

struct PopoverView: View {
    @EnvironmentObject private var poller: UsagePoller
    var chromeless = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if poller.snapshot.accounts.isEmpty {
                emptyState
            } else {
                ForEach(poller.snapshot.accounts) { account in
                    AccountCard(account: account, chromeless: chromeless)
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No Claude Code accounts found")
                .font(.headline)
            Text("Sign in with Claude Code first (a logged-in ~/.claude or ~/.claude-team), then reopen Claude Pulse.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if poller.snapshot.fetchedAt > .distantPast {
                Text("Updated \(poller.snapshot.fetchedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if chromeless { EmptyView() } else {
                footerControls
            }
        }
    }

    @ViewBuilder
    private var footerControls: some View {
        Group {
            Button {
                poller.refresh(force: true)
            } label: {
                if poller.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh now (makes a request, starting a session)")
            SettingsMenu()
        }
    }
}

private struct SettingsMenu: View {
    @EnvironmentObject private var poller: UsagePoller
    @EnvironmentObject private var settings: MenuBarSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(UsagePoller.keepAliveKey) private var keepSessionsActive = false
    @ObservedObject private var updater = AppUpdater.shared

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Menu {
            if !poller.snapshot.accounts.isEmpty {
                Section("Show in Menu Bar") {
                    ForEach(poller.snapshot.accounts) { account in
                        Toggle(account.label, isOn: Binding(
                            get: { settings.isVisible(account.id) },
                            set: { settings.setVisible($0, accountID: account.id) }
                        ))
                    }
                }
                Divider()
            }
            Toggle("Keep sessions active", isOn: $keepSessionsActive)
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Divider()
            Text("Version \(appVersion)")
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            Button("Quit Claude Pulse") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onChange(of: keepSessionsActive) { _, enabled in
            if enabled { poller.refresh(force: true) }
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

private struct AccountCard: View {
    let account: AccountUsage
    var chromeless = false
    @EnvironmentObject private var poller: UsagePoller
    @Environment(\.openWindow) private var openWindow

    private func editToken() {
        openWindow(id: "token-entry", value: account.id)
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.label)
                        .font(.headline)
                    if let detail = account.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusBadge
                if !chromeless { tokenMenu }
            }
            content
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        if account.needsToken {
            Button {
                editToken()
            } label: {
                Label("Add usage token", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else if account.hasAnyData {
            if let window = account.fiveHour {
                UsageRow(title: "Current session", window: window)
            }
            if let window = account.sevenDay {
                UsageRow(title: "Weekly · All models", window: window)
            }
            if let window = account.sevenDayOpus {
                UsageRow(title: "Weekly · Opus", window: window)
            }
            if let window = account.sevenDaySonnet {
                UsageRow(title: "Weekly · Sonnet", window: window)
            }
        } else {
            Text("No data yet — open Claude Code in this subscription to load usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tokenMenu: some View {
        Menu {
            Button(account.needsToken ? "Add token…" : "Replace token…") { editToken() }
            if !account.needsToken {
                Button("Remove token", role: .destructive) {
                    TokenStore.remove(for: account.id)
                    poller.refresh()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var statusBadge: some View {
        if account.tokenExpired {
            Label("Token rejected", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        } else if let error = account.fetchError {
            Label(error, systemImage: "wifi.exclamationmark")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }
}

private struct UsageRow: View {
    let title: String
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(UsageFormat.percentText(window.utilization))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            UsageBar(fraction: window.utilization / 100, color: UsageFormat.color(window.utilization))
            // A stable window value never re-evaluates the row, so a plain Text would
            // freeze the countdown; TimelineView ticks the clock to recompute it.
            TimelineView(.everyMinute) { context in
                Text(UsageFormat.resetText(window.resetsAt, now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
