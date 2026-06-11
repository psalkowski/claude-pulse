import SwiftUI

@main
struct ClaudePulseApp: App {
    @StateObject private var poller = UsagePoller()
    @StateObject private var settings = MenuBarSettings()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(poller)
                .environmentObject(settings)
        } label: {
            MenuBarLabelView()
                .environmentObject(poller)
                .environmentObject(settings)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "token-entry", for: String.self) { $accountID in
            TokenEntryWindow(accountID: accountID)
                .environmentObject(poller)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
