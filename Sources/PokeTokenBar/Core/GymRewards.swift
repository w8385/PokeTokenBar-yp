import Foundation

/// What a first clear gives. Re-clears give nothing: `GymRewards.reward` answers nil once the badge is held.
struct GymReward: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case gymBadge(index: Int)
        case hallOfFame
        case orgBadge
        case hiddenBoss
    }

    let region: String
    let battleID: String
    let kind: Kind
    /// A TM granted with it; nil when the pool of unowned TMs for this reward is empty.
    let tmMoveID: Int?
    /// The badges after the reward.
    let badges: GymBadges

    var prize: HiddenBossPrize? { kind == .hiddenBoss ? HiddenBossPrize.prize(for: region) : nil }
}

enum GymRewards {
    /// A gym's TM is of its type and gets stronger with the gym's index; the champion's and a boss's is any
    /// move of power 100 or more.
    static let finaleMinPower = 100

    static func reward(for opponent: GymOpponent, region: String, badges: GymBadges, ownedTMs: Set<Int>,
                       catalog: [MachineEntry] = MachineCatalog.moves) -> GymReward? {
        let current = badges.region(region)
        var updated = badges
        switch opponent.kind {
        case "gym":
            guard !current.gyms.contains(opponent.index) else { return nil }
            updated.update(region) { $0.gyms.insert(opponent.index) }
            let move = gymTM(type: opponent.types.first, index: opponent.index, owned: ownedTMs, catalog: catalog)
            return GymReward(region: region, battleID: opponent.id, kind: .gymBadge(index: opponent.index),
                             tmMoveID: move, badges: updated)
        case "champion":
            guard !current.hallOfFame else { return nil }
            updated.update(region) { $0.hallOfFame = true }
            return GymReward(region: region, battleID: opponent.id, kind: .hallOfFame,
                             tmMoveID: finaleTM(seed: opponent.id, owned: ownedTMs, catalog: catalog), badges: updated)
        case "boss":
            guard !current.orgBeaten else { return nil }
            updated.update(region) { $0.orgBeaten = true }
            return GymReward(region: region, battleID: opponent.id, kind: .orgBadge,
                             tmMoveID: finaleTM(seed: opponent.id, owned: ownedTMs, catalog: catalog), badges: updated)
        case "hidden":
            guard !current.hiddenBeaten else { return nil }
            updated.update(region) { $0.hiddenBeaten = true }
            return GymReward(region: region, battleID: opponent.id, kind: .hiddenBoss,
                             tmMoveID: finaleTM(seed: opponent.id, owned: ownedTMs, catalog: catalog), badges: updated)
        default:
            return nil
        }
    }

    /// The unowned attack TMs of `type` below the finale power, weakest first, with gym 1 taking the weakest
    /// and gym 8 the strongest; nil when none is left.
    static func gymTM(type: String?, index: Int, owned: Set<Int>, catalog: [MachineEntry]) -> Int? {
        guard let type else { return nil }
        let pool = catalog.filter { $0.type == type && !$0.isWeather && $0.power > 0 && $0.power < finaleMinPower && !owned.contains($0.id) }
            .sorted { ($0.power, $0.id) < ($1.power, $1.id) }
        guard !pool.isEmpty else { return nil }
        let rank = (max(1, min(GymBadges.gymsPerRegion, index)) - 1) * (pool.count - 1) / (GymBadges.gymsPerRegion - 1)
        return pool[rank].id
    }

    /// An unowned move of power `finaleMinPower` or more, picked by `seed` so the same trainer always offers
    /// the same one; nil when none is left.
    static func finaleTM(seed: String, owned: Set<Int>, catalog: [MachineEntry]) -> Int? {
        let pool = catalog.filter { !$0.isWeather && $0.power >= finaleMinPower && !owned.contains($0.id) }
            .sorted { ($0.power, $0.id) < ($1.power, $1.id) }
        guard !pool.isEmpty else { return nil }
        return pool[Int(stableHash(seed) % UInt64(pool.count))].id
    }

    /// FNV-1a; `hashValue` changes every launch.
    static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}
