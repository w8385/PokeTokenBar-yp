import SwiftUI

/// The one speech-bubble style: window-background fill, continuous rounded corners, a soft shadow and a
/// small triangle tail at the bottom center. `scale` shrinks every measure together, so the emoji bubbles
/// are the pet's speech bubble made smaller rather than a second style.
struct BubbleMetrics: Equatable {
    let scale: CGFloat

    var cornerRadius: CGFloat { 12 * scale }
    var tailWidth: CGFloat { 10 * scale }
    var tailHeight: CGFloat { 6 * scale }
    var shadowRadius: CGFloat { 4 * scale }
    var shadowOffsetY: CGFloat { 2 * scale }

    /// Limit alerts and agent messages.
    static let standard = BubbleMetrics(scale: 1)
    /// One-emoji reactions.
    static let mini = BubbleMetrics(scale: 0.5)
}

/// A rounded box whose tail hangs from the bottom center and sits inside `rect`.
struct BubbleShape: Shape {
    let metrics: BubbleMetrics

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - metrics.tailHeight)
        let box = Path(roundedRect: body, cornerRadius: min(metrics.cornerRadius, body.height / 2), style: .continuous)
        let overlap = metrics.scale
        var tail = Path()
        tail.move(to: CGPoint(x: rect.midX - metrics.tailWidth / 2, y: body.maxY - overlap))
        tail.addLine(to: CGPoint(x: rect.midX + metrics.tailWidth / 2, y: body.maxY - overlap))
        tail.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        tail.closeSubpath()
        return box.union(tail)
    }
}

extension View {
    /// Draws the bubble behind the view and reserves the tail's height under it.
    func speechBubbleSurface(_ metrics: BubbleMetrics = .standard) -> some View {
        padding(.bottom, metrics.tailHeight)
            .background(
                BubbleShape(metrics: metrics)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: metrics.shadowRadius, y: metrics.shadowOffsetY)
            )
            // A hairline keeps the bubble readable where it sits on the same background color (Home, dark mode).
            .overlay(BubbleShape(metrics: metrics).stroke(Color(nsColor: .separatorColor), lineWidth: 0.75))
    }
}
