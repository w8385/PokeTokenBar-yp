import SwiftUI

/// How a chip looks while its filter or toggle is on.
struct ChipTint: Equatable {
    let color: Color
    let fill: Double
    let stroke: Double

    static let accent = ChipTint(color: .accentColor, fill: 0.12, stroke: 0.5)
    static let shiny = ChipTint(color: .yellow, fill: 0.18, stroke: 0.6)
}

extension View {
    /// Grouped rows: control background, a separator hairline, `Radius.card`.
    func ptbCard() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    /// A quiet tinted block behind detail text: the species flavor, evolution and friend rows.
    func ptbPanel(radius: CGFloat = Radius.card) -> some View {
        background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: radius))
    }

    /// Filter chips, toggles and the search box. `active` tints it while the filter is on.
    func ptbChip(active: ChipTint? = nil) -> some View {
        background(active.map { $0.color.opacity($0.fill) } ?? Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Radius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.chip)
                    .strokeBorder(active.map { $0.color.opacity($0.stroke) } ?? Color.secondary.opacity(0.2),
                                  lineWidth: 0.5)
            )
    }
}

/// Squeezes while pressed.
struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
