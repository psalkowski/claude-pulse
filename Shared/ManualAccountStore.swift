import Foundation

// A subscription the user added by hand with just a token, for the case where
// there is nothing on disk to find (signed in on another machine, inside a
// container, or a config dir we can't reach). A pasted setup-token carries no
// readable identity — Anthropic rejects it on /api/oauth/profile with
// "does not meet scope requirement any_of(user:profile, user:office)" — so the
// display name has to come from the user, and it can't be matched to an
// accountUuid either.
struct ManualTokenAccount: Codable, Identifiable, Equatable {
    var id: String
    var name: String
}

struct ManualAccounts: Codable, Equatable {
    // Config dirs the user pointed at explicitly; scanned alongside the
    // automatic locations, so these still get a real identity and activity.
    var configDirs: [String] = []
    var tokenAccounts: [ManualTokenAccount] = []
}

enum ManualAccountStore {
    static let idPrefix = "manual:"

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudePulse", isDirectory: true)
            .appendingPathComponent("manual-accounts.json")
    }

    static func load() -> ManualAccounts {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(ManualAccounts.self, from: data)
        else { return ManualAccounts() }
        return decoded
    }

    private static func save(_ accounts: ManualAccounts) {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func isTokenAccount(_ accountID: String?) -> Bool {
        accountID?.hasPrefix(idPrefix) == true
    }

    static func name(for accountID: String) -> String? {
        load().tokenAccounts.first { $0.id == accountID }?.name
    }

    // MARK: Config dirs

    static func configDirs() -> [URL] {
        load().configDirs.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func isUserAdded(configDir path: String?) -> Bool {
        guard let path else { return false }
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        return load().configDirs.contains {
            URL(fileURLWithPath: $0).standardizedFileURL.path == target
        }
    }

    static func addConfigDir(_ url: URL) {
        var accounts = load()
        let path = url.standardizedFileURL.path
        guard !accounts.configDirs.contains(path) else { return }
        accounts.configDirs.append(path)
        save(accounts)
    }

    static func removeConfigDir(_ path: String) {
        var accounts = load()
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        accounts.configDirs.removeAll {
            URL(fileURLWithPath: $0).standardizedFileURL.path == target
        }
        save(accounts)
    }

    // MARK: Token-only accounts

    @discardableResult
    static func addTokenAccount(name: String) -> ManualTokenAccount {
        var accounts = load()
        let account = ManualTokenAccount(id: idPrefix + UUID().uuidString, name: name)
        accounts.tokenAccounts.append(account)
        save(accounts)
        return account
    }

    static func rename(_ accountID: String, to name: String) {
        var accounts = load()
        guard let index = accounts.tokenAccounts.firstIndex(where: { $0.id == accountID })
        else { return }
        accounts.tokenAccounts[index].name = name
        save(accounts)
    }

    static func removeTokenAccount(_ accountID: String) {
        var accounts = load()
        accounts.tokenAccounts.removeAll { $0.id == accountID }
        save(accounts)
    }
}
