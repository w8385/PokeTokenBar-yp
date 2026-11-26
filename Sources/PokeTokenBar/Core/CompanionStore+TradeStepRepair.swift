import Foundation

extension CompanionState {
    /// When the trade gate shipped; a graduate from before it grew under the old rules.
    static let tradeGateShippedAt = Date(timeIntervalSince1970: 1_794_575_760)

    /// Once per save: a Pokémon that grew through a held-item trade step without ever owning the item goes back to the
    /// form before that step. Plain trade steps and Pokémon traded in stay as they are.
    mutating func revertUnearnedTradeSteps() {
        guard !unearnedTradeStepsReverted else { return }
        unearnedTradeStepsReverted = true
        var dropped: Set<String> = []
        for index in dex.indices {
            let entry = dex[index]
            guard !entry.isReleased, entry.originalTrainer == nil,
                  let caughtAt = entry.caughtAt, caughtAt >= Self.tradeGateShippedAt,
                  let step = unearnedTradeStep(in: entry.chainOrder) else { continue }
            let kept = Array(entry.chainOrder.prefix(step))
            dex[index].chainOrder = kept
            dex[index].finalID = kept[kept.count - 1]
            dex[index].profile?.abilityName = nil
            dropped.insert("\(entry.baseID):\(entry.finalID)")
            collectedFinals.insert("\(entry.baseID):\(dex[index].finalID)")
        }
        collectedFinals.subtract(dropped.subtracting(dex.map { "\($0.baseID):\($0.finalID)" }))
        for (id, line) in storedLines {
            guard let mon = revertedMon(line.mon) else { continue }
            storedLines[id]?.mon = mon
        }
        if let mon = active.flatMap(revertedMon) { active = mon }
    }

    private func revertedMon(_ mon: MonState) -> MonState? {
        guard mon.tradeGated == true,
              let step = unearnedTradeStep(in: mon.reachedIDs) else { return nil }
        var mon = mon
        mon.pathIDs = Array(mon.pathIDs.prefix(step))
        mon.plannedPathIDs = mon.pathIDs
        mon.stageIndex = step - 1
        mon.totalForms = step
        mon.evolution = EvolutionProgress()
        mon.profile?.abilityName = nil
        return mon
    }

    /// The index of the first step in `chain` that needs a held item this save never owned.
    private func unearnedTradeStep(in chain: [Int]) -> Int? {
        chain.indices.dropFirst().first { index in
            guard let rule = EvolutionRules.rule(for: chain[index]), rule.isTradeOnly,
                  rule.from == chain[index - 1], case .holding(let item) = rule.trade else { return false }
            return inventory[item.rawValue] == nil
        }
    }
}
