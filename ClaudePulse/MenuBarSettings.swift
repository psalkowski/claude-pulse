import Foundation

@MainActor
final class MenuBarSettings: ObservableObject {
    private static let key = "menuBarHiddenAccounts"

    @Published var hiddenAccountIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenAccountIDs).sorted(), forKey: Self.key)
        }
    }

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        hiddenAccountIDs = Set(stored)
    }

    func isVisible(_ accountID: String) -> Bool {
        !hiddenAccountIDs.contains(accountID)
    }

    func setVisible(_ visible: Bool, accountID: String) {
        if visible {
            hiddenAccountIDs.remove(accountID)
        } else {
            hiddenAccountIDs.insert(accountID)
        }
    }
}
