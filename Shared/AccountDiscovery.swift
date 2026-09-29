import Foundation

struct AccountProfile: Equatable {
    var email: String?
    var organizationName: String?
    var organizationType: String?
    var rateLimitTier: String?
    var seatTier: String?
    var hasClaudeMax: Bool
    var hasClaudePro: Bool

    static let unknown = AccountProfile(
        email: nil, organizationName: nil, organizationType: nil,
        rateLimitTier: nil, seatTier: nil, hasClaudeMax: false, hasClaudePro: false
    )
}

// One Claude Code subscription, discovered from a config dir's plaintext
// .claude.json (no keychain, no network). The config dir also owns the
// projects/ folder we watch for activity, and is how a pasted setup-token is
// associated with the right subscription.
struct DiscoveredAccount: Identifiable {
    let id: String              // accountUuid (stable, unique)
    let configDirs: [URL]       // every config dir resolving to this account
    let profile: AccountProfile
    let origin: AccountOrigin
    // Set only for a subscription with no config dir here, so no identity we
    // can read: one kept by hand, or one whose login has left this Mac.
    let fixedLabel: (title: String, detail: String?)?

    init(
        id: String,
        configDirs: [URL],
        profile: AccountProfile,
        origin: AccountOrigin = .configDir,
        fixedLabel: (title: String, detail: String?)? = nil
    ) {
        self.id = id
        self.configDirs = configDirs
        self.profile = profile
        self.origin = origin
        self.fixedLabel = fixedLabel
    }

    init(manual: ManualTokenAccount) {
        self.init(
            id: manual.id, configDirs: [], profile: .unknown,
            origin: .manual, fixedLabel: (manual.name, "Added manually")
        )
    }

    // We still hold a token for it, but no config dir is signed in to it any
    // more (logged out, or the dir was deleted). The token may still work, so
    // the subscription stays listed under the name it last showed.
    init(signedOut id: String, lastSeen: AccountUsage?) {
        var profile = AccountProfile.unknown
        profile.organizationType = lastSeen?.subscriptionType
        let label = lastSeen.map { ($0.label, $0.detail) } ?? ("Unnamed subscription", nil)
        self.init(id: id, configDirs: [], profile: profile, origin: .signedOut, fixedLabel: label)
    }

    // The dir to reference in the setup-token instructions: the canonical
    // ~/.claude if present, otherwise the shortest path. nil for a manually
    // added token — that subscription has no config dir here at all.
    var configDir: URL? {
        let defaultDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
        if configDirs.contains(where: { $0.standardizedFileURL == defaultDir.standardizedFileURL }) {
            return defaultDir
        }
        return configDirs.min { $0.path.count < $1.path.count }
    }

    var label: (title: String, detail: String?) {
        if let fixedLabel { return fixedLabel }
        return PlanLabel.make(from: profile)
    }

    // Most recent activity across all of this account's config dirs — a proxy
    // for "Claude Code is being used in this subscription right now".
    func lastActivity() -> Date? {
        let fm = FileManager.default
        var latest: Date?
        for dir in configDirs {
            let projects = dir.appendingPathComponent("projects", isDirectory: true)
            guard let enumerator = fm.enumerator(
                at: projects,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    if latest == nil || date > latest! { latest = date }
                }
            }
        }
        return latest
    }
}

enum AccountDiscovery {
    // Every subscription Claude Pulse knows about: the ones it can find on disk,
    // plus any token-only ones the user added by hand.
    static func all() -> [DiscoveredAccount] {
        var accounts = onDisk()
        let known = Set(accounts.map(\.id))
        for manual in ManualAccountStore.load().tokenAccounts where !known.contains(manual.id) {
            accounts.append(DiscoveredAccount(manual: manual))
        }
        return accounts
    }

    // Does this dir hold a logged-in Claude Code state file? Used to reject a
    // folder the user picks that isn't actually a config dir.
    static func holdsAccount(_ configDir: URL) -> Bool {
        parse(configDir) != nil
    }

    private static func onDisk() -> [DiscoveredAccount] {
        // Group config dirs by the account they hold; multiple dirs can map to
        // one account (e.g. ~/.claude and ~/.claude-team-personal). One account,
        // one token, activity merged across its dirs.
        var byID: [String: (profile: AccountProfile, dirs: [URL])] = [:]
        var order: [String] = []
        for dir in candidateDirs() {
            guard let parsed = parse(dir) else { continue }
            if byID[parsed.uuid] == nil {
                byID[parsed.uuid] = (parsed.profile, [dir])
                order.append(parsed.uuid)
            } else {
                byID[parsed.uuid]?.dirs.append(dir)
            }
        }
        return order.compactMap { uuid in
            guard let entry = byID[uuid] else { return nil }
            return DiscoveredAccount(id: uuid, configDirs: entry.dirs, profile: entry.profile)
        }
    }

    // Everywhere a logged-in config dir plausibly lives. CLAUDE_CONFIG_DIR can
    // point anywhere, so rather than only matching ~/.claude* names we sweep
    // every hidden dir under home (plus one level into ~/.config) and let the
    // state-file parse decide. Visible home dirs are deliberately NOT swept:
    // touching ~/Documents, ~/Desktop or ~/Downloads — even for a file that
    // isn't there — trips a macOS TCC prompt. Those are what the explicit
    // "Add config folder…" picker is for, and picking a folder grants access.
    private static func candidateDirs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultDir = home.appendingPathComponent(".claude", isDirectory: true)

        let hidden = subdirectories(of: home).filter { $0.lastPathComponent.hasPrefix(".") }
        // ~/.claude-team before ~/.other so the conventional names win the
        // canonical-dir pick when several dirs resolve to one account.
        let claudeNamed = hidden.filter { $0.lastPathComponent.hasPrefix(".claude") }
        let otherHidden = hidden.filter { !$0.lastPathComponent.hasPrefix(".claude") }
        let configChildren = subdirectories(of: home.appendingPathComponent(".config", isDirectory: true))

        var candidates = [defaultDir] + claudeNamed + configChildren + otherHidden
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            candidates.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        candidates += ManualAccountStore.configDirs()

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func subdirectories(of parent: URL) -> [URL] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: parent.path) else { return [] }
        return names.sorted().compactMap { name in
            let url = parent.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return url
        }
    }

    // A dir can end up with two state files — a stale $CLAUDE_CONFIG_DIR/.claude.json
    // left over from an old setup next to the live ~/.claude.json — and they can
    // name different accounts. The most recently written one is the real state;
    // picking the first candidate would attribute the dir to a dead login.
    private static func parse(_ configDir: URL) -> (uuid: String, profile: AccountProfile)? {
        var best: (modified: Date, parsed: (uuid: String, profile: AccountProfile))?
        for stateFile in stateFileCandidates(for: configDir) {
            guard let parsed = parse(stateFile: stateFile) else { continue }
            let modified = (try? stateFile.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            if best == nil || modified > best!.modified {
                best = (modified, parsed)
            }
        }
        return best?.parsed
    }

    // With CLAUDE_CONFIG_DIR set, Claude Code keeps its state file inside the
    // config dir. A stock install (no CLAUDE_CONFIG_DIR) uses ~/.claude as the
    // config dir but writes the state file to ~/.claude.json in the home root,
    // so the default dir gets that as a fallback.
    private static func stateFileCandidates(for configDir: URL) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultDir = home.appendingPathComponent(".claude", isDirectory: true)
        var candidates = [configDir.appendingPathComponent(".claude.json")]
        if configDir.standardizedFileURL == defaultDir.standardizedFileURL {
            candidates.append(home.appendingPathComponent(".claude.json"))
        }
        return candidates
    }

    private static func parse(stateFile: URL) -> (uuid: String, profile: AccountProfile)? {
        guard let data = try? Data(contentsOf: stateFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any],
              let uuid = account["accountUuid"] as? String
        else { return nil }

        let profile = AccountProfile(
            email: account["emailAddress"] as? String,
            organizationName: account["organizationName"] as? String,
            organizationType: account["organizationType"] as? String,
            rateLimitTier: (account["userRateLimitTier"] as? String)
                ?? (account["organizationRateLimitTier"] as? String),
            seatTier: account["seatTier"] as? String,
            hasClaudeMax: (account["organizationType"] as? String) == "claude_max",
            hasClaudePro: (account["organizationType"] as? String) == "claude_pro"
        )
        return (uuid, profile)
    }
}
