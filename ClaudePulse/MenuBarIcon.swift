import SwiftUI
import AppKit

struct GaugeSpec {
    let utilization: Double?
    let dimmed: Bool
}

struct MenuBarIconView: View {
    let gauges: [GaugeSpec]

    var body: some View {
        HStack(spacing: 8) {
            if gauges.isEmpty {
                gauge(GaugeSpec(utilization: nil, dimmed: true))
            }
            ForEach(Array(gauges.enumerated()), id: \.offset) { _, spec in
                gauge(spec)
            }
        }
        .frame(height: 18)
        .padding(.horizontal, 2)
    }

    private func gauge(_ spec: GaugeSpec) -> some View {
        let color = spec.dimmed ? Color.secondary : Color.primary
        let value = min(max((spec.utilization ?? 0) / 100, 0.0001), 1)
        return ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 2.6)
            Circle()
                .trim(from: 0, to: value)
                .stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label(spec.utilization))
                .font(.system(size: fontSize(spec.utilization), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(width: 17, height: 17)
    }

    private func label(_ utilization: Double?) -> String {
        guard let utilization else { return "–" }
        return "\(Int(utilization.rounded()))"
    }

    private func fontSize(_ utilization: Double?) -> CGFloat {
        let value = utilization.map { Int($0.rounded()) } ?? 0
        return value >= 100 ? 6.5 : 8.5
    }
}

enum MenuBarIconRenderer {
    @MainActor
    static func render(specs: [GaugeSpec]) -> NSImage {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let content = MenuBarIconView(gauges: specs)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            return NSImage(size: NSSize(width: 8, height: 18))
        }
        image.isTemplate = false
        return image
    }
}

@MainActor
final class GaugeAnimator: ObservableObject {
    struct Target: Equatable {
        let utilization: Double?
        let dimmed: Bool
    }

    @Published private(set) var image = NSImage(size: NSSize(width: 8, height: 18))

    private var displayed: [Double?] = []
    private var dimmed: [Bool] = []
    private var initialized = false
    private var timer: Timer?

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.renderNow() }
        }
    }

    func update(targets: [Target]) {
        let values = targets.map(\.utilization)
        dimmed = targets.map(\.dimmed)
        guard initialized, displayed.count == values.count else {
            displayed = values
            initialized = true
            renderNow()
            return
        }
        animate(to: values)
    }

    private func animate(to targets: [Double?]) {
        timer?.invalidate()
        let starts = displayed
        let unchanged = zip(starts, targets).allSatisfy { ($0 ?? -1) == ($1 ?? -1) }
        if unchanged {
            displayed = targets
            renderNow()
            return
        }
        let duration = 0.6
        let step = 1.0 / 30
        var elapsed = 0.0
        timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] timer in
            elapsed += step
            let progress = min(elapsed / duration, 1)
            let eased = 1 - pow(1 - progress, 3)
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.displayed = zip(starts, targets).map { start, end in
                    guard let end else { return nil }
                    let from = start ?? end
                    return from + (end - from) * eased
                }
                self.renderNow()
                if progress >= 1 { timer.invalidate() }
            }
        }
    }

    private func renderNow() {
        let specs = (0..<displayed.count).map { index in
            GaugeSpec(
                utilization: displayed[index],
                dimmed: index < dimmed.count ? dimmed[index] : false
            )
        }
        image = MenuBarIconRenderer.render(specs: specs)
    }
}
