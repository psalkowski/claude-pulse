import SwiftUI
import AppKit
import WidgetKit

// Renders the menubar, popover and widget to PNGs using the anonymized
// UsageSnapshot.sample data — so README images regenerate from code with no
// manual editing and never contain real account data. Invoked by launching the
// app binary with:  --render-docs <output-dir>
@MainActor
enum DocRenderer {
    static func renderIfRequested() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--render-docs"), idx + 1 < args.count else { return }
        let outDir = URL(fileURLWithPath: args[idx + 1])
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let poller = UsagePoller(previewing: .sample)
        let settings = MenuBarSettings()

        let popover = PopoverView(chromeless: true)
            .environmentObject(poller)
            .environmentObject(settings)
            .background(Color(red: 0.13, green: 0.13, blue: 0.14))
        save(popover, to: outDir.appendingPathComponent("popover.png"))

        let widget = UsageWidgetView(
            entry: UsageEntry(date: Date(), snapshot: .sample),
            familyOverride: .systemMedium
        )
            .padding(16)
            .frame(width: 360, height: 170)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        save(widget, to: outDir.appendingPathComponent("widget.png"))

        let menubar = MenuBarIconView(gauges: [
            GaugeSpec(utilization: 28, dimmed: false),
            GaugeSpec(utilization: 100, dimmed: false),
        ])
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(red: 0.14, green: 0.15, blue: 0.17))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        save(menubar, to: outDir.appendingPathComponent("menubar.png"))

        print("Rendered docs images to \(outDir.path)")
        exit(0)
    }

    private static func save<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
