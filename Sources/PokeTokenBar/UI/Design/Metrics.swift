import SwiftUI

enum Radius {
    /// Bar ends and ruler ticks inside charts.
    static let hairline: CGFloat = 1
    static let bar: CGFloat = 2
    /// Chips, tiles, tooltips, the slot picker.
    static let chip: CGFloat = 6
    /// Cards, grouped settings rows, evolution and detail panels.
    static let card: CGFloat = 8
    /// Shop, bag and scout images, big tiles.
    static let panel: CGFloat = 10
    /// Speech bubbles, the pet crowd, hit areas of floating sprites.
    static let sheet: CGFloat = 12
}

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
}

struct ShadowStyle: Equatable {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat

    static let none = ShadowStyle(opacity: 0, radius: 0, y: 0)
    /// A hovered tile or a tooltip lifting off the page.
    static let lift = ShadowStyle(opacity: 0.25, radius: 4, y: 2)
    /// The speech bubble at scale 1.
    static let bubble = ShadowStyle(opacity: 0.15, radius: 4, y: 2)
    /// Keeps white glyphs readable on a light type badge.
    static let glyph = ShadowStyle(opacity: 0.35, radius: 0.5, y: 0.5)

    func scaled(_ scale: CGFloat) -> ShadowStyle {
        ShadowStyle(opacity: opacity, radius: radius * scale, y: y * scale)
    }
}

extension View {
    func ptbShadow(_ style: ShadowStyle) -> some View {
        shadow(color: .black.opacity(style.opacity), radius: style.radius, y: style.y)
    }
}
