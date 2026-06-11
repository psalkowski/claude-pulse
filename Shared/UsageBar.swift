import SwiftUI

// A simple capsule progress bar. Used instead of SwiftUI's ProgressView because
// ProgressView does not render in an off-screen ImageRenderer (doc generation),
// and a capsule is visually equivalent.
struct UsageBar: View {
    let fraction: Double   // 0...1
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
