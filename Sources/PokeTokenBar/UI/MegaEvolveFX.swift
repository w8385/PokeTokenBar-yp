import SwiftUI

/// The one-shot Mega Evolution effect: the base sprite charges up white, a keystone-coloured ring pulses out,
/// a flash hides the swap, and the Mega sprite settles in. Everything here is a pure function of time.
enum MegaEvolveFX {
    static let duration: TimeInterval = 1.4
    static let swapTime: TimeInterval = 0.62
    static let crossfadeDuration: TimeInterval = 0.25
    /// An event older than this no longer explains a sprite change.
    static let eventWindow: TimeInterval = 2
    /// A surface that appears after the equip only plays if the equip was this recent.
    static let mountWindow: TimeInterval = 0.6

    struct Frame: Equatable {
        let showsMega: Bool
        let scale: Double
        let glow: Double
        let flash: Double
        /// Ring radius as a fraction of the sprite box, and its opacity. nil while no ring is visible.
        let ring: (scale: Double, opacity: Double)?

        static func == (lhs: Frame, rhs: Frame) -> Bool {
            lhs.showsMega == rhs.showsMega && lhs.scale == rhs.scale && lhs.glow == rhs.glow
                && lhs.flash == rhs.flash && lhs.ring?.scale == rhs.ring?.scale && lhs.ring?.opacity == rhs.ring?.opacity
        }
    }

    static func frame(at t: TimeInterval) -> Frame {
        let t = max(t, 0)
        let charge = smooth(ramp(t, 0, 0.55))
        let flash = t < swapTime ? ramp(t, 0.45, swapTime) : 1 - ramp(t, swapTime, 0.95)
        if t < swapTime {
            return Frame(showsMega: false, scale: 1 + 0.05 * charge, glow: charge, flash: flash, ring: ring(at: t))
        }
        let settle = ramp(t, swapTime, duration)
        let scale = 1 - 0.12 * exp(-3 * settle) * cos(2 * .pi * 1.1 * settle)
        let glow = 1 - smooth(ramp(t, swapTime, 1.05))
        return Frame(showsMega: true, scale: t >= duration ? 1 : scale, glow: glow, flash: flash, ring: ring(at: t))
    }

    private static func ring(at t: TimeInterval) -> (scale: Double, opacity: Double)? {
        let p = ramp(t, 0.35, 1.15)
        guard p > 0, p < 1 else { return nil }
        return (0.35 + 0.8 * (1 - (1 - p) * (1 - p)), sin(.pi * p))
    }

    /// Opacity of the incoming layer while a plain crossfade runs (reduce motion, unequip, swapping stones).
    static func crossfade(at t: TimeInterval) -> Double { smooth(ramp(t, 0, crossfadeDuration)) }

    private static func ramp(_ t: Double, _ from: Double, _ to: Double) -> Double { min(max((t - from) / (to - from), 0), 1) }
    private static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}

/// What a surface draws right now: one layer when idle, two while a crossfade runs, plus the effect overlay.
struct MegaEvolveRender: Equatable {
    struct Layer: Equatable, Identifiable {
        /// nil is the base sprite.
        let megaID: Int?
        let opacity: Double
        var id: Int { megaID ?? 0 }
    }

    var layers: [Layer]
    var fx: MegaEvolveFX.Frame?
}

/// Per-surface state of the effect. Starts only from a fresh store event that matches this surface's own
/// sprite change, so a relaunch, a redraw, or a holder that is not on screen never plays it.
struct MegaEvolveStageModel: Equatable {
    enum Phase: Equatable {
        case idle
        case evolving(start: Date, mega: Int)
        case crossfading(start: Date, from: Int?, to: Int?)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastEventID: Int?
    private(set) var runID = 0

    var isRunning: Bool { phase != .idle }

    var runDuration: TimeInterval {
        switch phase {
        case .idle: 0
        case .evolving: MegaEvolveFX.duration
        case .crossfading: MegaEvolveFX.crossfadeDuration
        }
    }

    mutating func megaChanged(from old: Int?, to new: Int?, event: MegaEvolveEvent?, now: Date, reduceMotion: Bool) {
        guard old != new, let event = fresh(event, now: now, window: MegaEvolveFX.eventWindow) else { return }
        switch event.kind {
        case .equip where new == event.megaSpriteID:
            start(event, from: old, to: new, now: now, reduceMotion: reduceMotion)
        case .unequip where old == event.megaSpriteID && new == nil:
            start(event, from: old, to: nil, now: now, reduceMotion: true)
        default:
            break
        }
    }

    mutating func mounted(megaSpriteID: Int?, event: MegaEvolveEvent?, now: Date, reduceMotion: Bool) {
        guard let megaSpriteID, let event = fresh(event, now: now, window: MegaEvolveFX.mountWindow),
              event.kind == .equip, event.megaSpriteID == megaSpriteID else { return }
        start(event, from: nil, to: megaSpriteID, now: now, reduceMotion: reduceMotion)
    }

    mutating func finish() { phase = .idle }

    func render(at now: Date, megaSpriteID: Int?) -> MegaEvolveRender {
        let idle = MegaEvolveRender(layers: [.init(megaID: megaSpriteID, opacity: 1)], fx: nil)
        switch phase {
        case .idle:
            return idle
        case .evolving(let start, let mega):
            let t = now.timeIntervalSince(start)
            guard t < MegaEvolveFX.duration else { return idle }
            let frame = MegaEvolveFX.frame(at: t)
            return MegaEvolveRender(layers: [.init(megaID: frame.showsMega ? mega : nil, opacity: 1)], fx: frame)
        case .crossfading(let start, let from, let to):
            let t = now.timeIntervalSince(start)
            guard t < MegaEvolveFX.crossfadeDuration else { return idle }
            let incoming = MegaEvolveFX.crossfade(at: t)
            return MegaEvolveRender(layers: [.init(megaID: from, opacity: 1 - incoming), .init(megaID: to, opacity: incoming)],
                                    fx: nil)
        }
    }

    private func fresh(_ event: MegaEvolveEvent?, now: Date, window: TimeInterval) -> MegaEvolveEvent? {
        guard let event, event.id != lastEventID, now.timeIntervalSince(event.at) <= window else { return nil }
        return event
    }

    private mutating func start(_ event: MegaEvolveEvent, from: Int?, to: Int?, now: Date, reduceMotion: Bool) {
        lastEventID = event.id
        runID += 1
        if from == nil, let to, !reduceMotion {
            phase = .evolving(start: now, mega: to)
        } else {
            phase = .crossfading(start: now, from: from, to: to)
        }
    }
}

/// Wraps a sprite so a fresh Mega equip or unequip plays the effect on it. `content` draws the sprite for a
/// Mega id, or the base sprite for nil. Idle, the schedule is paused and nothing runs per frame.
@MainActor
struct MegaEvolveStage<Content: View>: View {
    let megaSpriteID: Int?
    let size: CGFloat
    let event: MegaEvolveEvent?
    var animated = true
    @ViewBuilder let content: (Int?) -> Content
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var model = MegaEvolveStageModel()

    private var reduceMotion: Bool { systemReduceMotion || !animated }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isRunning)) { context in
            MegaEvolveRenderView(render: model.render(at: context.date, megaSpriteID: megaSpriteID),
                                 size: size, content: content)
        }
        .onChange(of: megaSpriteID) { old, new in
            model.megaChanged(from: old, to: new, event: event, now: Date(), reduceMotion: reduceMotion)
        }
        .onAppear {
            model.mounted(megaSpriteID: megaSpriteID, event: event, now: Date(), reduceMotion: reduceMotion)
        }
        .task(id: model.runID) {
            guard model.isRunning else { return }
            try? await Task.sleep(for: .seconds(model.runDuration + 0.05))
            if !Task.isCancelled { model.finish() }
        }
    }
}

/// The pixels of one frame of the effect. The live stage and the screenshot tests draw through this.
@MainActor
struct MegaEvolveRenderView<Content: View>: View {
    let render: MegaEvolveRender
    let size: CGFloat
    @ViewBuilder let content: (Int?) -> Content

    var body: some View {
        let fx = render.fx
        ZStack(alignment: .bottom) {
            ForEach(render.layers) { layer in
                content(layer.megaID)
                    .opacity(layer.opacity)
                    .brightness((fx?.glow ?? 0) * 0.85)
                    .shadow(color: .white.opacity(fx?.glow ?? 0), radius: 10 * (fx?.glow ?? 0))
                    .scaleEffect(fx?.scale ?? 1, anchor: .bottom)
            }
            if let fx {
                MegaEvolveOverlay(frame: fx, size: size).allowsHitTesting(false)
            }
        }
    }
}

@MainActor
private struct MegaEvolveOverlay: View {
    let frame: MegaEvolveFX.Frame
    let size: CGFloat

    private static let keystone: [Color] = [
        Color(red: 1.0, green: 0.44, blue: 0.71), Color(red: 0.61, green: 0.42, blue: 1.0),
        Color(red: 0.25, green: 0.82, blue: 1.0), Color(red: 0.36, green: 0.89, blue: 0.49),
        Color(red: 1.0, green: 0.85, blue: 0.29), Color(red: 1.0, green: 0.44, blue: 0.71),
    ]

    var body: some View {
        ZStack {
            if let ring = frame.ring {
                Circle()
                    .strokeBorder(AngularGradient(colors: Self.keystone, center: .center), lineWidth: max(2, size * 0.06))
                    .frame(width: size * 0.9, height: size * 0.9)
                    .scaleEffect(ring.scale)
                    .opacity(ring.opacity)
            }
            RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.55)
                .opacity(frame.flash)
        }
        .frame(width: size, height: size)
    }
}
