import SwiftUI

// A simple capsule progress bar. Used instead of SwiftUI's ProgressView because
// ProgressView does not render in an off-screen ImageRenderer (doc generation),
// and a capsule is visually equivalent.
struct UsageBar: View {
    let fraction: Double   // 0...1
    let color: Color
    var height: CGFloat = 6
    var projectedFraction: Double? = nil
    var elapsedFraction: Double? = nil

    private static let markOverhang: CGFloat = 3
    private static let markHalo: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                if let projectedFraction, projectedFraction > fraction {
                    Capsule()
                        .fill(color.opacity(0.35))
                        .frame(width: clamped(projectedFraction) * width)
                }
                Capsule()
                    .fill(color)
                    .frame(width: clamped(fraction) * width)
            }
            .frame(height: height)
            .overlay(alignment: .leading) {
                if let projectedFraction, projectedFraction > 1 {
                    mark(color: .red, width: 2, at: width - 2)
                }
            }
            .overlay(alignment: .leading) {
                if let elapsedFraction {
                    mark(color: .primary, width: 2, at: clamped(elapsedFraction) * width - 1)
                }
            }
        }
        .frame(height: height)
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private func mark(color: Color, width: CGFloat, at x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width / 2)
            .fill(color)
            .frame(width: width, height: height + 2 * Self.markOverhang)
            .padding(Self.markHalo)
            .background(
                RoundedRectangle(cornerRadius: width / 2 + Self.markHalo)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .offset(x: x - Self.markHalo)
    }
}
