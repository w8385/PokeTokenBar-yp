import Foundation

/// The growth slider older versions kept in UserDefaults. Read only to migrate saves written against it; never written.
struct LegacyGrowthDifficulty: Equatable {
    static let growthKey = "growthDifficulty"
    static let shopKey = "shopDifficulty"
    /// Set once the v2 app had multiplied the slider by 5 for its ÷5 tables.
    static let movedToV2Key = "economyDifficultyV2"
    /// The slider before that move.
    static let v1GrowthKey = "economyLegacyGrowth"

    /// The slider against the economy v1 tables.
    let v1: Double
    /// The slider against the economy v2 tables.
    let v2: Double

    init(_ defaults: UserDefaults) {
        let stored = defaults.object(forKey: Self.growthKey) as? Double
        if defaults.bool(forKey: Self.movedToV2Key) {
            let current = Self.clamped(stored)
            let before = defaults.object(forKey: Self.v1GrowthKey) as? Double
            v2 = current
            v1 = before.flatMap { Self.movedToV2($0) == current ? Self.wide($0) : nil } ?? current
        } else {
            v1 = Self.wide(stored)
            v2 = Self.movedToV2(stored)
        }
    }

    /// How many times larger a save's thresholds were than the current ones, slider included.
    func scale(fromEconomyVersion version: Int) -> Double {
        Double(Self.tableFactor(fromEconomyVersion: version)) * (version <= 1 ? v1 : v2)
    }

    /// How many times larger the bare tables of `version` were than the current ones.
    static func tableFactor(fromEconomyVersion version: Int) -> Int {
        version <= 1 ? 50 : 10
    }

    /// The v2 app ran the slider inside 10%–200%; missing or not a number was 100%.
    static func clamped(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 1 }
        return min(max(value, 0.1), 2)
    }

    /// Releases before v2 accepted 0.01%–2000%.
    static func wide(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 1 }
        return min(max(value, 0.0001), 20)
    }

    /// The v2 app's one-time move of a v1 slider: ×5, clamped. A stored 1.0 was the launch-time default and stayed 1.0.
    static func movedToV2(_ value: Double?) -> Double {
        guard let value, value.isFinite, value != 1 else { return 1 }
        return clamped(value * 5)
    }
}
