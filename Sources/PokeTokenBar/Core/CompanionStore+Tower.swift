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
}
