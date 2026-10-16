import Foundation
import WidgetKit

@MainActor
final class MenuBarSettings: ObservableObject {
    private nonisolated static let key = "menuBarHiddenAccounts"

    @Published var hiddenAccountIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenAccountIDs).sorted(), forKey: Self.key)
            SnapshotStore.update { $0.hiddenAccountIDs = Array(hiddenAccountIDs).sorted() }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    init() {
        hiddenAccountIDs = Self.storedHiddenIDs()
    }

    nonisolated static func storedHiddenIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
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
