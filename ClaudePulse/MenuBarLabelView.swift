import SwiftUI

struct MenuBarLabelView: View {
    @EnvironmentObject private var poller: UsagePoller
    @EnvironmentObject private var settings: MenuBarSettings
    @StateObject private var animator = GaugeAnimator()

    var body: some View {
        Image(nsImage: animator.image)
            .onAppear {
                poller.start()
                animator.update(targets: targets)
            }
            .onChange(of: targets) { _, newTargets in
                animator.update(targets: newTargets)
            }
    }

    private var targets: [GaugeAnimator.Target] {
        poller.snapshot.accounts
            .filter { settings.isVisible($0.id) }
            .map {
                GaugeAnimator.Target(
                    utilization: $0.fiveHour?.utilization,
                    dimmed: $0.tokenExpired
                )
            }
    }
}
