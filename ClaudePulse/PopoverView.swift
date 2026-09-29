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
        VStack(alignment: .leading, spacing: 8) {
            Text("No Claude Code accounts found")
                .font(.headline)
            Text("Claude Pulse looks for logged-in config dirs under your home folder (~/.claude, ~/.claude-team, ~/.config/…). If a subscription lives somewhere else, add it by hand.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AddSubscriptionMenu(prominent: true)
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
            AddSubscriptionMenu()
            SettingsMenu()
        }
    }
}

// Discovery can only see config dirs it's allowed to look at, and a bare token
// can't be traced back to a subscription — so both escape hatches live here.
private struct AddSubscriptionMenu: View {
    var prominent = false
    @EnvironmentObject private var poller: UsagePoller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            Button("Add config folder…") { pickConfigFolder() }
            Button("Add subscription token…") {
                openWindow(id: "token-entry", value: TokenEntryWindow.newAccountValue)
                NSApp.activate(ignoringOtherApps: true)
            }
            let userAdded = ManualAccountStore.load().configDirs
            if !userAdded.isEmpty {
                Divider()
                Section("Added folders") {
                    ForEach(userAdded, id: \.self) { path in
                        Button("Forget \(URL(fileURLWithPath: path).lastPathComponent)") {
                            ManualAccountStore.removeConfigDir(path)
                            poller.refresh()
                        }
                    }
                }
            }
        } label: {
            if prominent {
                Label("Add subscription", systemImage: "plus")
            } else {
                Image(systemName: "plus")
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add a subscription Claude Pulse didn't find")
    }

    // Picking the folder is also what grants access to it: a folder chosen in an
    // open panel is readable even where an unprompted scan would trip TCC.
    private func pickConfigFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Add"
        panel.message = "Pick the Claude Code config folder for that subscription — the folder holding its .claude.json (the value of CLAUDE_CONFIG_DIR)."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard AccountDiscovery.holdsAccount(url) else {
            // The popover has already dismissed itself behind the panel, so a
            // SwiftUI .alert on this view would never appear.
            let alert = NSAlert()
            alert.messageText = "No signed-in account in that folder"
            alert.informativeText = "\(url.path) has no .claude.json with a logged-in account. Pick the folder Claude Code writes its state to, or use “Add subscription token…” instead."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        ManualAccountStore.addConfigDir(url)
        poller.refresh(force: true)
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

    private var tokenFailed: Bool { account.tokenFailure != nil }

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
                .greyedOut(tokenFailed)
                Spacer()
                statusBadge
                if !chromeless { tokenMenu }
            }
            if let failure = account.tokenFailure {
                tokenFailureNotice(failure)
            }
            if account.origin == .signedOut {
                signedOutNotice
            }
            content
                .greyedOut(tokenFailed)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tokenFailureNotice(_ failure: TokenFailure) -> some View {
        let (title, reason): (String, String) = switch failure {
        case .expired: ("Usage token expired", "Tokens from `claude setup-token` last about a year.")
        case .revoked: ("Usage token revoked", "Anthropic reports this token was revoked.")
        case .invalid: ("Usage token not accepted", "Anthropic doesn't recognize this token.")
        }
        return CredentialNotice(
            icon: "key.slash",
            tint: .orange,
            title: title,
            message: "\(reason) The numbers below are from the last successful update. Generate a new token and paste it in.",
            action: "Replace token…",
            perform: editToken
        )
    }

    private var signedOutNotice: some View {
        CredentialNotice(
            icon: "person.crop.circle.badge.xmark",
            tint: .secondary,
            title: "Signed out of Claude Code on this Mac",
            message: tokenFailed
                ? "No config folder here is signed in to this subscription. Sign in to it again in Claude Code, or keep it with a new usage token."
                : "No config folder here is signed in to this subscription, but its usage token still works. Sign in to it again in Claude Code, or keep it with just the token.",
            action: "Keep with token only…",
            perform: editToken
        )
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
                UsageRow(title: "Current session", window: window, muted: tokenFailed)
            }
            if let window = account.sevenDay {
                UsageRow(title: "Weekly · All models", window: window, muted: tokenFailed)
            }
            if let window = account.sevenDayOpus {
                UsageRow(title: "Weekly · Opus", window: window, muted: tokenFailed)
            }
            if let window = account.sevenDayFable {
                UsageRow(title: "Weekly · Fable", window: window, muted: tokenFailed)
            }
        } else {
            Text(account.configDir == nil
                 ? "No data yet — hit Refresh to load usage for this subscription."
                 : "No data yet — open Claude Code in this subscription to load usage.")
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
            if account.origin == .manual {
                Divider()
                Button("Remove subscription", role: .destructive) {
                    TokenStore.remove(for: account.id)
                    ManualAccountStore.removeTokenAccount(account.id)
                    poller.refresh()
                }
            } else if ManualAccountStore.isUserAdded(configDir: account.configDir) {
                Divider()
                Button("Forget this folder", role: .destructive) {
                    ManualAccountStore.removeConfigDir(account.configDir ?? "")
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
        if let error = account.fetchError {
            Label(error, systemImage: "wifi.exclamationmark")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }
}

private struct CredentialNotice: View {
    let icon: String
    let tint: Color
    let title: String
    let message: LocalizedStringKey
    let action: String
    let perform: () -> Void

    init(icon: String, tint: Color, title: String, message: String, action: String, perform: @escaping () -> Void) {
        self.icon = icon
        self.tint = tint
        self.title = title
        // Markdown, so `claude setup-token` renders as code.
        self.message = LocalizedStringKey(message)
        self.action = action
        self.perform = perform
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action, action: perform)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

private extension View {
    func greyedOut(_ greyed: Bool) -> some View {
        opacity(greyed ? 0.45 : 1)
    }
}

private struct UsageRow: View {
    let title: String
    let window: UsageWindow
    var muted = false

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
            UsageBar(fraction: window.utilization / 100, color: muted ? .gray : UsageFormat.color(window.utilization))
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
