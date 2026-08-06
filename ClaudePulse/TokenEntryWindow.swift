import SwiftUI
import AppKit

struct TokenEntryWindow: View {
    // Sentinel window value for "adding a subscription we never discovered".
    // A real accountID is a uuid or a ManualAccountStore id, never this.
    static let newAccountValue = "+new"

    let accountID: String?
    @EnvironmentObject private var poller: UsagePoller
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var name = ""

    private var isNew: Bool { accountID == nil || accountID == Self.newAccountValue }
    private var isManual: Bool { isNew || ManualAccountStore.isTokenAccount(accountID) }

    private var account: AccountUsage? {
        poller.snapshot.accounts.first { $0.id == accountID }
    }

    private var command: String {
        let dir = account?.configDir ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.isEmpty || dir == home + "/.claude" {
            return "claude setup-token"
        }
        return "CLAUDE_CONFIG_DIR=\(dir) claude setup-token"
    }

    private var canSave: Bool {
        let hasToken = !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasToken && (!isNew || hasName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Add subscription" : "Usage token — \(account?.label ?? "Subscription")")
                .font(.headline)

            if isNew {
                Text("For a subscription Claude Pulse can't find on disk. A setup-token carries no readable identity, so give it a name yourself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isManual {
                TextField("Name (e.g. Work Max)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            Text(isNew
                 ? "Where you're signed in to that subscription, run:"
                 : "In a terminal, run this to generate a long-lived token for this subscription:")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy command")
            }

            Text("Then paste the printed token below:")
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField("sk-ant-oat…", text: $token)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

            if isNew {
                Text("Usage for a manually added subscription only refreshes when you hit Refresh, or with “Keep sessions active” on — without a config folder there's no activity to detect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            if let accountID, !isNew { name = ManualAccountStore.name(for: accountID) ?? "" }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNew {
            let created = ManualAccountStore.addTokenAccount(name: trimmedName)
            TokenStore.set(token, for: created.id)
        } else if let accountID {
            if isManual, !trimmedName.isEmpty { ManualAccountStore.rename(accountID, to: trimmedName) }
            TokenStore.set(token, for: accountID)
        }
        poller.refresh(force: true)
        dismiss()
    }
}
