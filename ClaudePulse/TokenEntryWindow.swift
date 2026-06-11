import SwiftUI
import AppKit

struct TokenEntryWindow: View {
    let accountID: String?
    @EnvironmentObject private var poller: UsagePoller
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Usage token — \(account?.label ?? "Subscription")")
                .font(.headline)

            Text("In a terminal, run this to generate a long-lived token for this subscription:")
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

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if let id = accountID {
                        TokenStore.set(token, for: id)
                        poller.refresh(force: true)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
