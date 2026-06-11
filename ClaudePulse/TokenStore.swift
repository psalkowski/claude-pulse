import Foundation

// Stores the user-pasted long-lived setup-tokens in a 0600 file under Application
// Support. We deliberately do NOT use the macOS keychain: a self-signed app
// (no Apple Developer ID) fails the keychain partition-list check and would be
// prompted for the login password on every read. A file we own is read with no
// prompt at all — the whole point of the keychain-free design.
enum TokenStore {
    private static var fileURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudePulse", isDirectory: true)
        return base.appendingPathComponent("tokens.json")
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func persist(_ dict: [String: String]) {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func token(for accountID: String) -> String? {
        let token = load()[accountID]
        return (token?.isEmpty == false) ? token : nil
    }

    @discardableResult
    static func set(_ token: String, for accountID: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return remove(for: accountID) }
        var dict = load()
        dict[accountID] = trimmed
        persist(dict)
        return true
    }

    @discardableResult
    static func remove(for accountID: String) -> Bool {
        var dict = load()
        dict.removeValue(forKey: accountID)
        persist(dict)
        return true
    }
}
