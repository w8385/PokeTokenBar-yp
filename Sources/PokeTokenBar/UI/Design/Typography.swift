import SwiftUI

/// The numeric type scale. Text that follows Dynamic Type uses the system styles (`.caption`, `.callout`);
/// these are for fixed-size glyphs, badges, chips and the recap LCD, where the size is part of the layout.
struct FontSize: Equatable {
    let points: CGFloat

    static let micro = FontSize(points: 7)
    static let tiny = FontSize(points: 8)
    static let caption = FontSize(points: 9)
    static let small = FontSize(points: 10)
    static let body = FontSize(points: 11)
    static let label = FontSize(points: 12)
    static let control = FontSize(points: 13)
    static let lead = FontSize(points: 15)
    static let headline = FontSize(points: 17)
    static let title = FontSize(points: 22)
    static let display = FontSize(points: 24)
    static let hero = FontSize(points: 28)
}

extension Font {
    /// A token size, optionally scaled together with the view it sits in (the day/night dial).
    static func ptb(_ size: FontSize, scale: CGFloat = 1, weight: Font.Weight? = nil,
                    design: Font.Design? = nil) -> Font {
        .system(size: size.points * scale, weight: weight, design: design)
    }
}
