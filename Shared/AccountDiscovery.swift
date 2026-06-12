import Foundation

struct AccountProfile: Equatable {
    var email: String?
    var organizationName: String?
    var organizationType: String?
    var rateLimitTier: String?
    var seatTier: String?
    var hasClaudeMax: Bool
    var hasClaudePro: Bool
}

// One Claude Code subscription, discovered from a config dir's plaintext
// .claude.json (no keychain, no network). The config dir also owns the
// projects/ folder we watch for activity, and is how a pasted setup-token is
// associated with the right subscription.
struct DiscoveredAccount: Identifiable {
    let id: String              // accountUuid (stable, unique)
    let configDirs: [URL]       // every config dir resolving to this account
    let profile: AccountProfile

    // The dir to reference in the setup-token instructions: the canonical
    // ~/.claude if present, otherwise the shortest path.
    var configDir: URL {
        let defaultDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
        if configDirs.contains(where: { $0.standardizedFileURL == defaultDir.standardizedFileURL }) {
            return defaultDir
        }
        return configDirs.min { $0.path.count < $1.path.count } ?? defaultDir
    }

    var label: (title: String, detail: String?) { PlanLabel.make(from: profile) }

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
    static func all() -> [DiscoveredAccount] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var dirs: [URL] = [home.appendingPathComponent(".claude", isDirectory: true)]
        if let names = try? fm.contentsOfDirectory(atPath: home.path) {
            for name in names where name.hasPrefix(".claude") && name != ".claude" {
                var isDir: ObjCBool = false
                let url = home.appendingPathComponent(name, isDirectory: true)
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    dirs.append(url)
                }
            }
        }

        // Group config dirs by the account they hold; multiple dirs can map to
        // one account (e.g. ~/.claude and ~/.claude-team-personal). One account,
        // one token, activity merged across its dirs.
        var byID: [String: (profile: AccountProfile, dirs: [URL])] = [:]
        var order: [String] = []
        for dir in dirs {
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

    private static func parse(_ configDir: URL) -> (uuid: String, profile: AccountProfile)? {
        for stateFile in stateFileCandidates(for: configDir) {
            if let parsed = parse(stateFile: stateFile) { return parsed }
        }
        return nil
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
