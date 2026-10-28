import SwiftUI
import AppKit

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private final class FitView: NSView {
    var height: CGFloat = 0 { didSet { fit() } }
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.fit()
            }
        }
        fit()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func fit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, self.height > 0 else { return }
            let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: window.frame.width, height: self.height)).height
            guard abs(target - window.frame.height) > 0.5 else { return }
            var frame = window.frame
            frame.origin.y += frame.height - target
            frame.size.height = target
            window.setFrame(frame, display: true)
        }
    }
}

private struct WindowFit: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> FitView { FitView() }

    func updateNSView(_ view: FitView, context: Context) { view.height = height }
}

extension View {
    // A MenuBarExtra window doesn't follow its content when that shrinks (an
    // account collapsing, one disappearing), leaving blank bands above and below.
    func fitsHostingWindow() -> some View {
        modifier(HostingWindowFit())
    }
}

private struct HostingWindowFit: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(ContentHeightKey.self) { height = $0 }
            .background(WindowFit(height: height))
    }
}
