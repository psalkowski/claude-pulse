import SwiftUI
import AppKit
import WidgetKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let didInitialSetupKey = "didInitialLaunchSetup"

    func applicationDidFinishLaunching(_ notification: Notification) {
        DocRenderer.renderIfRequested()
        enableLaunchAtLoginOnFirstRun()
        _ = AppUpdater.shared
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func enableLaunchAtLoginOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.didInitialSetupKey) else { return }
        defaults.set(true, forKey: Self.didInitialSetupKey)
        try? SMAppService.mainApp.register()
    }
}

@main
struct ClaudePulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
