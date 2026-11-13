import Foundation
import Observation

/// A graduated Pokémon standing beside the active one.
struct FriendSubject: Equatable, Identifiable, Sendable {
    let entryID: String
    let speciesID: Int
    let isShiny: Bool
    let form: PokemonForm?
    let isFemale: Bool
    var id: String { entryID }

    init(_ entry: DexEntry) {
        entryID = entry.id
        speciesID = entry.finalID
        isShiny = entry.isShiny
        form = PokemonForm.resolved(speciesID: entry.finalID, form: entry.form)
        isFemale = entry.profile?.gender == .female
    }
}

/// Display-only reactions between the active Pokémon (slot 0) and its friends (slots 1…).
/// Nothing here reaches the save or a roll. One instance per surface (Home, floating pet).
@MainActor
@Observable
final class PetCrowd {
    enum Bubble: String, Equatable { case heart = "❤️", note = "🎵", cheer = "🎉" }
    enum Idle: Equatable { case hop, heart, note }

    static let idleDelayRange: ClosedRange<TimeInterval> = 20...40
    /// How long a turn or bubble stays before the crowd settles back.
    static let settleDelay: Duration = .seconds(2.5)

    /// Slots from left to right on screen; its count is the number of Pokémon standing there.
    private(set) var order: [Int] = [0]
    private(set) var hopTicks: [Int] = [0, 0, 0]
    private(set) var facingRight: [Bool] = [false, false, false]
    private(set) var bubbles: [Bubble?] = [nil, nil, nil]
    private(set) var motionAllowed = true
    /// Floating pet only: which side of the main pet the friends stand on.
    var friendsOnLeft = true

    private var idleTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private let delayProvider: () -> TimeInterval
    private let settle: Duration

    init(settle: Duration = PetCrowd.settleDelay,
         delayProvider: @escaping () -> TimeInterval = { TimeInterval.random(in: PetCrowd.idleDelayRange) }) {
        self.settle = settle
        self.delayProvider = delayProvider
    }

    var friendCount: Int { max(0, order.count - 1) }
    var isIdleLoopRunning: Bool { idleTask != nil }

    // MARK: Lifecycle

    /// The one entry point that decides whether the idle timer runs: only while shown, with at least one friend,
    /// and with motion allowed. A hidden surface passes `active: false` and holds no task.
    func configure(order: [Int], motionAllowed: Bool, active: Bool) {
        let slots = Array(order.prefix(hopTicks.count))
        let normalized = slots.isEmpty ? [0] : slots
        if self.order != normalized {
            self.order = normalized
            clearReactions()
        }
        self.motionAllowed = motionAllowed
        if !motionAllowed { clearReactions() }
        if active, motionAllowed, friendCount > 0 {
            if idleTask == nil { startIdleLoop() }
        } else {
            stop()
        }
    }

    func stop() {
        idleTask?.cancel(); idleTask = nil
        settleTask?.cancel(); settleTask = nil
        clearReactions()
    }

    private func clearReactions() {
        facingRight = [false, false, false]
        bubbles = [nil, nil, nil]
    }

    private func startIdleLoop() {
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.delayProvider()
                try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(delay * 0.1))
                if Task.isCancelled { return }
                self.fireIdle()
            }
        }
    }

    // MARK: Reactions

    /// Two Pokémon face each other and show a bubble, or hop together.
    func fireIdle(using rng: inout some RandomNumberGenerator) {
        guard motionAllowed, let pick = Self.pickIdle(slots: order, using: &rng) else { return }
        play(pick.kind, between: pick.pair.0, and: pick.pair.1, bubbleOn: Bool.random(using: &rng) ? pick.pair.0 : pick.pair.1)
    }

    func fireIdle() {
        var rng = SystemRandomNumberGenerator()
        fireIdle(using: &rng)
    }

    static func pickIdle(slots: [Int], using rng: inout some RandomNumberGenerator) -> (pair: (Int, Int), kind: Idle)? {
        guard slots.count >= 2 else { return nil }
        var pool = slots
        let first = pool.remove(at: Int.random(in: 0..<pool.count, using: &rng))
        let second = pool[Int.random(in: 0..<pool.count, using: &rng)]
        let kind: Idle = [.heart, .note, .hop].randomElement(using: &rng) ?? .hop
        return ((first, second), kind)
    }

    func play(_ kind: Idle, between a: Int, and b: Int, bubbleOn: Int) {
        guard motionAllowed, tracks(a), tracks(b), a != b else { return }
        switch kind {
        case .hop:
            hop(a); hop(b)
        case .heart, .note:
            face(a, toward: b); face(b, toward: a)
            bubbles[bubbleOn] = kind == .heart ? .heart : .note
            scheduleSettle()
        }
    }

    /// A click on `slot`: the others turn toward it and hop once. A friend that was clicked also hops and shows a heart.
    func clicked(slot: Int) {
        guard tracks(slot) else { return }
        if motionAllowed {
            for other in order where other != slot {
                face(other, toward: slot)
                hop(other)
            }
        }
        if slot != 0 {
            if motionAllowed { hop(slot) }
            bubbles[slot] = .heart
        }
        scheduleSettle()
    }

    /// The active Pokémon leveled up, evolved, hatched or graduated: the friends cheer.
    func cheer() {
        for slot in order where slot != 0 {
            if motionAllowed { hop(slot) }
            bubbles[slot] = .cheer
        }
        scheduleSettle()
    }

    func isFacingRight(_ slot: Int) -> Bool { facingRight.indices.contains(slot) && facingRight[slot] }
    func hopTick(_ slot: Int) -> Int { hopTicks.indices.contains(slot) ? hopTicks[slot] : 0 }
    func bubble(_ slot: Int) -> Bubble? { bubbles.indices.contains(slot) ? bubbles[slot] : nil }

    private func tracks(_ slot: Int) -> Bool { order.contains(slot) && hopTicks.indices.contains(slot) }

    private func hop(_ slot: Int) { hopTicks[slot] += 1 }

    /// Front sprites look left; a Pokémon turning toward a target on its right is mirrored.
    private func face(_ slot: Int, toward target: Int) {
        guard let from = order.firstIndex(of: slot), let to = order.firstIndex(of: target) else { return }
        facingRight[slot] = to > from
    }

    /// One one-shot task, restarted by every reaction; no standing timer.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self, settle] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self else { return }
            self.clearReactions()
        }
    }
}
