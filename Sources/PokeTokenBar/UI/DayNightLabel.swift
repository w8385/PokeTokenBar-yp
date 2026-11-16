import SwiftUI

/// Where the sun and moon sit on a 20-minute day+night cycle and what the sky behind them looks like.
/// Pure functions of the clock's degrees (see `DayPeriod.cycleDegrees`), so they are testable without a view.
enum DayNightSky {
    /// Unit offset from the dial's horizon centre (x right, y up). The sun rises on the left at 0°, tops out at
    /// 90° and sets on the right at 180°; the moon is half a turn behind.
    static func sun(degrees: Double) -> (x: Double, y: Double) { position(180 - degrees) }
    static func moon(degrees: Double) -> (x: Double, y: Double) { position(-degrees) }

    private static func position(_ angle: Double) -> (x: Double, y: Double) {
        let radians = angle * .pi / 180
        return (cos(radians), sin(radians))
    }

    /// Sky colour from the sun's height (-1...1): navy below the horizon, orange at the switches, blue by day.
    static func sky(degrees: Double) -> (red: Double, green: Double, blue: Double) {
        let height = sun(degrees: degrees).y
        let t = min(1, max(0, (height + 0.3) / 0.6))
        let night = (0.07, 0.10, 0.27), dusk = (0.98, 0.58, 0.30), day = (0.38, 0.68, 0.96)
        let (from, to, f) = t < 0.5 ? (night, dusk, t * 2) : (dusk, day, (t - 0.5) * 2)
        return (from.0 + (to.0 - from.0) * f, from.1 + (to.1 - from.1) * f, from.2 + (to.2 - from.2) * f)
    }

    static func starOpacity(degrees: Double) -> Double { min(1, max(0, -sun(degrees: degrees).y * 2)) }
}

/// Upper half of the unit ellipse — the dial's window onto the sky.
private struct HalfDisc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY), radius: rect.width / 2,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// A small horizon window with the sun and moon travelling across it, plus "Day 7m". The angle is read from
/// the clock every 15 seconds, never animated continuously; the timeline stops while the popover is closed.
@MainActor
struct DayNightLabel: View {
    let store: CompanionStore
    static let dialWidth: CGFloat = 28

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            let now = store.dayPeriodNow()
            let minutes = CompanionStore.minutes(now.secondsLeft)
            HStack(spacing: 4) {
                dial(degrees: now.degrees)
                Text(store.l.dayNightBadge(now.period, minutesLeft: minutes))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
            }
            .help(store.l.dayNightHelp)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(store.l.dayNightAccessibility(now.period, minutesLeft: minutes))
        }
    }

    private func dial(degrees: Double) -> some View {
        DayNightDial(degrees: degrees, width: Self.dialWidth)
    }
}

@MainActor
struct DayNightDial: View {
    let degrees: Double
    let width: CGFloat

    private var radius: CGFloat { width / 2 }
    /// Everything inside the disc scales with the width; 40 pt is the design size.
    private var k: CGFloat { width / 40 }

    var body: some View {
        let sky = DayNightSky.sky(degrees: degrees)
        let orbit = radius - 6 * k
        let sun = DayNightSky.sun(degrees: degrees)
        let moon = DayNightSky.moon(degrees: degrees)
        ZStack {
            Color(red: sky.red, green: sky.green, blue: sky.blue)
            Group {
                Circle().frame(width: 2 * k, height: 2 * k).offset(x: -10 * k, y: -radius + 9 * k)
                Circle().frame(width: 1.5 * k, height: 1.5 * k).offset(x: 5 * k, y: -radius + 6 * k)
                Circle().frame(width: 2 * k, height: 2 * k).offset(x: 12 * k, y: -radius + 12 * k)
            }
            .foregroundStyle(.white)
            .opacity(DayNightSky.starOpacity(degrees: degrees))
            .offset(y: radius / 2)
            Image(systemName: "sun.max.fill").font(.ptb(.body, scale: k))
                .foregroundStyle(Palette.sun)
                .offset(x: sun.x * orbit, y: -sun.y * orbit + radius / 2)
            Image(systemName: "moon.fill").font(.ptb(.small, scale: k))
                .foregroundStyle(Palette.moon)
                .offset(x: moon.x * orbit, y: -moon.y * orbit + radius / 2)
        }
        .frame(width: width, height: radius)
        .clipShape(HalfDisc())
        .overlay(HalfDisc().stroke(Color.secondary.opacity(0.5), lineWidth: max(0.5, k)))
        .animation(.easeInOut(duration: 0.4), value: degrees)
        .accessibilityHidden(true)
    }
}
