import SwiftUI

/// What a badge case slot shows.
enum GymEmblem: Equatable {
    case type(PokemonType)
    case hallOfFame
    case org
}

/// Simple original badge shapes drawn in SwiftUI: a type picks one of six outlines and its color and glyph.
@MainActor
struct GymBadgeView: View {
    let emblem: GymEmblem
    let earned: Bool
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            outline.fill(earned ? fill : Color.secondary.opacity(0.14))
            outline.stroke(earned ? Color.black.opacity(0.28) : Color.secondary.opacity(0.4), lineWidth: 1)
            Image(systemName: Self.symbol(emblem))
                .font(.ptb(.body, scale: size / 30, weight: .bold))
                .foregroundStyle(earned ? Color.white : Color.secondary.opacity(0.55))
                .ptbShadow(earned ? .glyph : .none)
        }
        .frame(width: size, height: size)
    }

    private var outline: AnyShape {
        switch emblem {
        case .type(let type): Self.shape(for: type)
        case .hallOfFame: AnyShape(GymStarShape(points: 5))
        case .org: AnyShape(GymPolygonShape(sides: 8))
        }
    }

    private var fill: Color {
        switch emblem {
        case .type(let type): type.color
        case .hallOfFame: Color.yellow
        case .org: Color.indigo
        }
    }

    static func shape(for type: PokemonType) -> AnyShape {
        let index = PokemonType.allCases.firstIndex(of: type) ?? 0
        switch index % 6 {
        case 0: return AnyShape(Circle())
        case 1: return AnyShape(GymPolygonShape(sides: 4))
        case 2: return AnyShape(GymPolygonShape(sides: 6))
        case 3: return AnyShape(GymShieldShape())
        case 4: return AnyShape(GymStarShape(points: 4))
        default: return AnyShape(GymPolygonShape(sides: 3))
        }
    }

    static func symbol(_ emblem: GymEmblem) -> String {
        switch emblem {
        case .hallOfFame: "trophy.fill"
        case .org: "theatermasks.fill"
        case .type(let type):
            switch type {
            case .normal: "circle.circle.fill"
            case .fire: "flame.fill"
            case .water: "drop.fill"
            case .electric: "bolt.fill"
            case .grass: "leaf.fill"
            case .ice: "snowflake"
            case .fighting: "hand.raised.fill"
            case .poison: "cross.vial.fill"
            case .ground: "mountain.2.fill"
            case .flying: "wind"
            case .psychic: "eye.fill"
            case .bug: "ant.fill"
            case .rock: "diamond.fill"
            case .ghost: "moon.fill"
            case .dragon: "tornado"
            case .dark: "moon.stars.fill"
            case .steel: "gearshape.fill"
            case .fairy: "sparkles"
            }
        }
    }
}

/// A regular polygon with a vertex at the top (a square becomes a diamond).
struct GymPolygonShape: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for corner in 0..<sides {
            let angle = -Double.pi / 2 + Double(corner) * 2 * .pi / Double(sides)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            corner == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

struct GymStarShape: Shape {
    let points: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * (points == 4 ? 0.5 : 0.45)
        var path = Path()
        for vertex in 0..<(points * 2) {
            let radius = vertex.isMultiple(of: 2) ? outer : inner
            let angle = -Double.pi / 2 + Double(vertex) * .pi / Double(points)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            vertex == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

struct GymShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY * 0.9))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.minX, y: rect.maxY * 0.9))
        path.closeSubpath()
        return path
    }
}
