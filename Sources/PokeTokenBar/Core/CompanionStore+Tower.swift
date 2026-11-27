import Foundation

extension CompanionStore {
    /// Mirrors a tower reply into the save and adds what the battle paid.
    func applyTower(_ run: TowerRun, gain: TowerGain?) {
        var tower = state.tower
        tower.mirror(run)
        if let gain { tower.earn(gain.bp) }
        guard tower != state.tower else { return }
        state.tower = tower
        save()
    }

    /// Puts `id` in tower entry slot `slot`, or empties it. Refused while an `entry` run is live.
    func setTowerEntry(_ id: String?, at slot: Int) {
        guard !state.tower.entryLocked else { return }
        let owned = Set(BattleEntry.candidates(in: state).map(\.id))
        if let id, !owned.contains(id) { return }
        let ids = TowerEntry.setting(id, at: slot, in: state.tower.entry.filter(owned.contains))
        guard ids != state.tower.entry else { return }
        state.tower.entry = ids
        save()
    }

    // MARK: BP exchange

    /// The growth and battle items, then the Mega Stones of species in the Box, then the legendary scout ticket.
    var towerGoods: [TowerGood] {
        let owned = Set(state.dex.map(\.finalID))
        let stones = MegaStone.all.filter { owned.contains($0.speciesID) }.map(TowerGood.stone)
        return TowerExchange.items.map(TowerGood.item) + stones + [.legendaryScout]
    }

    func bpPrice(of good: TowerGood) -> Int? {
        switch good {
        case .item(let kind): price(of: kind).map(TowerExchange.bp(forTokens:))
        case .stone(let stone): TowerExchange.bp(forTokens: price(of: .megaStone(stone)))
        case .legendaryScout: TowerExchange.legendaryScoutBP
        }
    }

    func canExchange(_ good: TowerGood) -> Bool {
        guard let cost = bpPrice(of: good), state.tower.bp >= cost else { return false }
        switch good {
        case .item(let kind): return !isSoldOut(kind)
        case .stone(let stone): return megaStoneOwnedTotal(stone) == 0
        case .legendaryScout: return true
        }
    }

    /// Spends BP, never tokens, so it leaves no token receipt to undo.
    @discardableResult
    func exchange(_ good: TowerGood) -> Bool {
        guard canExchange(good), let cost = bpPrice(of: good) else { return false }
        state.tower.bp -= cost
        state.inventory[good.inventoryKey, default: 0] += 1
        save()
        return true
    }
}
