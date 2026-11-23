/// Shared duplicate reduction for species and form selection. Keep every candidate selectable.
enum CollectionWeight {
    static func adjusted(_ weight: Int, isCollected: Bool) -> Int {
        isCollected ? max(1, weight / 2) : max(1, weight)
    }
}

/// The weighted base-species roll. Eggs use `.captureRate`; the scout draw flattens it to `.sqrtCaptureRate`.
enum SpeciesRoll {
    enum Weighting {
        case captureRate
        /// sqrt(rate) scaled by 1000 so the roll stays integer.
        case sqrtCaptureRate

        func base(_ captureRate: Int) -> Int {
            switch self {
            case .captureRate: return captureRate
            case .sqrtCaptureRate: return Int((Double(max(0, captureRate)).squareRoot() * 1000).rounded())
            }
        }
    }

    /// One roll over the weights, halved for collected lines. Consumes exactly one `rng.next()`.
    static func pick(from candidates: [BaseSpecies], weighting: Weighting = .captureRate,
                     isCollected: (Int) -> Bool, rng: inout any RandomNumberGenerator) -> BaseSpecies? {
        let weights = candidates.map {
            CollectionWeight.adjusted(weighting.base($0.captureRate), isCollected: isCollected($0.id))
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var r = Int(rng.next() % UInt64(total))
        for (i, w) in weights.enumerated() {
            r -= w
            if r < 0 { return candidates[i] }
        }
        return candidates.last
    }

    /// `count` distinct species by repeated rolls without replacement, in Pokédex order.
    /// A pool of `count` or fewer is returned whole.
    static func drawDistinct(from candidates: [BaseSpecies], count: Int, weighting: Weighting = .captureRate,
                             isCollected: (Int) -> Bool, rng: inout any RandomNumberGenerator) -> [Int] {
        var pool = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.id < $1.id }
        guard pool.count > count else { return pool.map(\.id) }
        var drawn: [Int] = []
        while drawn.count < count, let picked = pick(from: pool, weighting: weighting, isCollected: isCollected, rng: &rng) {
            drawn.append(picked.id)
            pool.removeAll { $0.id == picked.id }
        }
        return drawn.sorted()
    }
}
