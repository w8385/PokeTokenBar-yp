import SwiftUI

/// The Stellar Crystal's icon. The games have no such item, so it is drawn here: a faceted crystal that carries
/// the Mega ring's rainbow sweep, shaded facet by facet, with a four-point star on its upper edge.
@MainActor
struct StellarCrystalArt: View {
    var size: CGFloat = 30

    private static let top = CGPoint(x: 0.5, y: 0.04)
    private static let right = CGPoint(x: 0.86, y: 0.36)
    private static let left = CGPoint(x: 0.14, y: 0.36)
    private static let waist = CGPoint(x: 0.5, y: 0.36)
    private static let bottom = CGPoint(x: 0.5, y: 0.96)

    var body: some View {
        ZStack {
            UnitPolygon(points: [Self.top, Self.right, Self.bottom, Self.left])
                .fill(AngularGradient(colors: Palette.megaKeystone, center: .center))
            facet([Self.top, Self.left, Self.waist], shade: Color.white, opacity: 0.35)
            facet([Self.top, Self.right, Self.waist], shade: Palette.stellarNight, opacity: 0.15)
            facet([Self.left, Self.waist, Self.bottom], shade: Palette.stellarNight, opacity: 0.4)
            facet([Self.right, Self.waist, Self.bottom], shade: Palette.stellarNight, opacity: 0.6)
            UnitPolygon(points: [Self.top, Self.right, Self.bottom, Self.left])
                .stroke(Color.white.opacity(0.6), lineWidth: size * 0.03)
            UnitStar(center: CGPoint(x: 0.74, y: 0.2), radius: 0.15)
                .fill(Color.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func facet(_ points: [CGPoint], shade: Color, opacity: Double) -> some View {
        UnitPolygon(points: points).fill(shade.opacity(opacity))
    }
}

/// A polygon given in unit coordinates, scaled to the view's square.
private struct UnitPolygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let mapped = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
            if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        path.closeSubpath()
        return path
    }
}

/// A four-point star: long tips on the axes, short waists between them.
private struct UnitStar: Shape {
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let tips = [CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0)]
        let waists = [CGPoint(x: 0.28, y: -0.28), CGPoint(x: 0.28, y: 0.28), CGPoint(x: -0.28, y: 0.28),
                      CGPoint(x: -0.28, y: -0.28)]
        var path = Path()
        for index in tips.indices {
            for (offset, vertex) in [tips[index], waists[index]].enumerated() {
                let point = CGPoint(x: rect.minX + (center.x + vertex.x * radius) * rect.width,
                                    y: rect.minY + (center.y + vertex.y * radius) * rect.height)
                if index == 0 && offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        path.closeSubpath()
        return path
    }
}
