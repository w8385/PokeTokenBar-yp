import Foundation

/// A Pokémon that can take the raised slot or an Exp. Share: its next step still needs stage XP and nothing else
/// the player has to do.
struct MoveOnCandidate: Equatable {
    let id: String
    let xpLeft: Int
    let boxedAt: Date
}

/// What takes the raised slot after a stuck Pokémon leaves it.
enum MoveOnNext: Equatable {
    case egg
    case raise(String)
    case resume(String)
}

/// The raised Pokémon whose full XP waits on something only the player can do.
struct StuckRaised: Equatable {
    let id: String
    let speciesID: Int
    let name: String
    let needs: [EvolutionRequirement]
    let isGraduate: Bool
}

extension EvolutionRule {
    /// Stage XP still needed on the cheapest path that opens without the player; 0 when such a path needs none.
    func stageXPLeft(in ctx: EvolutionContext) -> Int {
        paths.filter { path in path.allSatisfy { $0.isMet(in: ctx) || $0.opensWithoutPlayer(in: ctx) } }
            .map { path in
                path.map { requirement -> Int in
                    guard case .longStage(let percent) = requirement else { return 0 }
                    return max(0, percent * ctx.stageThreshold / 100 - ctx.stageXP)
                }.max() ?? 0
            }
            .min() ?? 0
    }
}

extension EvolutionRules {
    static let byFromSpecies: [Int: [EvolutionRule]] = Dictionary(
        grouping: table.filter { $0.from != nil }, by: { $0.from ?? 0 })
}

extension CompanionStore {
    static let stuckMoveOnDelay: TimeInterval = 30 * 60
    static let autoMoveOnKey = "autoMoveOnWhenStuck"

    /// The least XP left wins; on a tie, the one boxed longest.
    nonisolated static func closestCandidate(_ candidates: [MoveOnCandidate], excluding: Set<String> = []) -> MoveOnCandidate? {
        candidates.filter { $0.xpLeft > 0 && !excluding.contains($0.id) }
            .min { ($0.xpLeft, $0.boxedAt) < ($1.xpLeft, $1.boxedAt) }
    }

    // MARK: Stuck raised Pokémon

    /// Nil while nothing is stuck, and while its line isn't loaded yet (`isStuckUnknown`).
    var stuckRaised: StuckRaised? {
        if let graduate = raisedGraduate {
            guard let evolving = evolvingGraduate, !holdsEverstone(graduate.id) else { return nil }
            let context = graduateContext(graduate)
            let rules = graduateOptions(evolving.entry, in: evolving.line).map { EvolutionRules.rule(for: $0.speciesID) }
            guard let first = rules.first ?? nil, rules.allSatisfy({ $0?.waitsOnPlayer(in: context) == true }) else {
                return nil
            }
            return StuckRaised(id: graduate.id, speciesID: graduate.finalID, name: displayName,
                               needs: first.playerRequirements(in: context), isGraduate: true)
        }
        guard canSkipEvolution, let a = state.active, let id = a.profile?.instanceID,
              let gate = pendingEvolutionGate(), gate.rule.waitsOnPlayer(in: gate.context) else { return nil }
        return StuckRaised(id: id, speciesID: a.currentID, name: displayName,
                           needs: gate.rule.playerRequirements(in: gate.context), isGraduate: false)
    }

    var isStuckUnknown: Bool {
        if let graduate = raisedGraduate { return raisedGraduateLine?.baseID != graduate.baseID }
        return state.active != nil && currentLine == nil
    }

    func isKeptWaiting(_ id: String, species: Int) -> Bool { state.keepWaiting[id] == species }

    /// The Home line under a stuck Pokémon: what it needs, and what happens when the wait runs out.
    var moveOnStatus: (needs: String, minutes: Int, next: MoveOnNext, toGraduates: Bool)? {
        guard autoMoveOn, let stuck = stuckRaised, !isKeptWaiting(stuck.id, species: stuck.speciesID) else { return nil }
        var elapsed: TimeInterval = 0
        if !isAttended, let watch = state.stuckWatch, watch.id == stuck.id { elapsed = clock().timeIntervalSince(watch.since) }
        return (requirementsText(stuck.needs), Self.minutes(max(0, Self.stuckMoveOnDelay - elapsed)),
                plannedNext(after: stuck), stuck.isGraduate)
    }

    private func plannedNext(after stuck: StuckRaised) -> MoveOnNext {
        if let pick = raiseCandidate(excluding: stuck.id) { return .raise(candidateName(pick.id)) }
        return stuck.isGraduate ? .resume(parkedLineName ?? l.parkedEggName) : .egg
    }

    func raiseCandidate(excluding id: String) -> MoveOnCandidate? {
        Self.closestCandidate(moveOnCandidates().filter { canRaise(entryID: $0.id) }, excluding: [id])
    }

    /// Each bag copy goes to the closest Pokémon that can use it, one per Pokémon; with none left it stays in the bag.
    /// Returns the notice lines. The caller saves.
    func giveBagExpSharesToCandidates() -> [String] {
        guard autoMoveOn, itemCount(.expShare) > 0 else { return [] }
        let candidates = moveOnCandidates()
        var excluded = expShareExcluded
        var lines: [String] = []
        while itemCount(.expShare) > 0, let pick = Self.closestCandidate(candidates, excluding: excluded) {
            excluded.insert(pick.id)
            if placeBagExpShare(on: pick.id) { lines.append(l.expShareFromBagLine(to: candidateName(pick.id))) }
        }
        return lines
    }

    /// A copy on the Pokémon move-on just raised would sit idle there, so it goes to the closest candidate.
    func passExpShare(offRaised raised: (id: String, name: String)?) -> [String] {
        guard let raised, holdsExpShare(raised.id),
              let pick = Self.closestCandidate(moveOnCandidates(), excluding: expShareExcluded),
              moveExpShare(from: raised.id, to: pick.id) else { return [] }
        return [l.expShareMovedLine(raised.name, to: candidateName(pick.id))]
    }

    private var expShareExcluded: Set<String> {
        Set(state.expShareHolders + [state.raisedEntryID].compactMap { $0 }).union(state.expShareTakenOff)
    }

    func requirementsText(_ requirements: [EvolutionRequirement]) -> String {
        requirements.map {
            l.evolutionRequirementText($0, speciesName: { speciesIndex?.entry($0)?.names[language.rawValue] ?? "#\($0)" },
                                       shopDifficulty: shopDifficulty)
        }.joined(separator: " + ")
    }

    func candidateName(_ id: String) -> String {
        state.dex.first { $0.id == id }.map(dexEntryName) ?? "#\(id)"
    }

    // MARK: Candidates

    /// Stored lines and graduates whose next step or Box graduation still needs XP and waits on nothing the player
    /// must do.
    func moveOnCandidates() -> [MoveOnCandidate] {
        var result: [MoveOnCandidate] = []
        for (id, stored) in state.storedLines {
            guard let left = storedXPLeft(id: id, stored) else { continue }
            let boxedAt = state.dex.first { $0.id == id }.flatMap { $0.releasedAt ?? $0.caughtAt } ?? .distantPast
            result.append(MoveOnCandidate(id: id, xpLeft: left, boxedAt: boxedAt))
        }
        for entry in state.dex where !entry.isReleased {
            guard let left = graduateXPLeft(entry) else { continue }
            result.append(MoveOnCandidate(id: entry.id, xpLeft: left, boxedAt: entry.caughtAt ?? .distantPast))
        }
        return result
    }

    /// The rule of the step the stored line planned next; nil at its last planned form or for an XP-only step.
    func plannedStoredStep(_ mon: MonState) -> EvolutionRule? {
        let next = mon.stageIndex + 1
        guard mon.plannedPathIDs.indices.contains(next) else { return nil }
        return EvolutionRules.rule(for: mon.plannedPathIDs[next])
    }

    /// At its last planned form, the XP left to Box graduation. An Everstone doesn't stop that once the loaded line
    /// shows no step left; an old save's plan can end before the line does.
    private func storedXPLeft(id: String, _ stored: StoredLine) -> Int? {
        let mon = stored.mon
        guard !isTradeLocked(id), mon.dittoDisguise == nil || mon.dittoRevealed,
              !holdsEverstone(id) || isKnownFinalForm(mon),
              !isKeptWaiting(id, species: mon.currentID) else { return nil }
        let left = max(0, stageThreshold(for: mon) - mon.usedAtStage)
        guard let rule = plannedStoredStep(mon), !rule.paths.isEmpty else { return left }
        let context = storedLineContext(stored)
        guard !rule.waitsOnPlayer(in: context) else { return nil }
        return max(left, rule.stageXPLeft(in: context))
    }

    func isKnownFinalForm(_ mon: MonState) -> Bool {
        guard !mon.plannedPathIDs.indices.contains(mon.stageIndex + 1),
              let node = expShareLines[mon.baseID]?.tree.node(withID: mon.currentID) else { return false }
        return growthOptions(of: node, gender: mon.profile?.gender).isEmpty
    }

    private func graduateXPLeft(_ entry: DexEntry) -> Int? {
        let rules = (EvolutionRules.byFromSpecies[entry.finalID] ?? []).filter { !$0.paths.isEmpty && !$0.isItemOnly }
        guard !rules.isEmpty, entry.profile != nil, entry.tradeEvolutionPending != true, !isTradeLocked(entry.id),
              !holdsEverstone(entry.id), !isKeptWaiting(entry.id, species: entry.finalID) else { return nil }
        let context = graduateContext(entry)
        return rules.filter { !$0.waitsOnPlayer(in: context) }
            .map { $0.stageXPLeft(in: context) }
            .min()
    }

    // MARK: Idle Exp. Share holders

    /// A holder that can't use more XP passes its copy to the closest candidate, or back to the bag. Returns the
    /// notice lines; the caller posts them.
    func moveIdleExpShares() -> [String] {
        guard autoMoveOn else { return [] }
        var lines: [String] = []
        for holder in state.expShareHolders where holder != state.raisedEntryID && isIdleExpShareHolder(holder) {
            let from = candidateName(holder)
            if let pick = Self.closestCandidate(moveOnCandidates(), excluding: expShareExcluded),
               moveExpShare(from: holder, to: pick.id) {
                lines.append(l.expShareMovedLine(from, to: candidateName(pick.id)))
            } else if returnExpShareToBag(from: holder) {
                lines.append(l.expShareBaggedLine(from))
            }
        }
        return lines
    }

    /// Unknown (its line not loaded yet) counts as busy.
    func isIdleExpShareHolder(_ id: String) -> Bool {
        if let stored = state.storedLines[id] {
            let mon = stored.mon
            guard let line = expShareLines[mon.baseID], let node = line.tree.node(withID: mon.currentID),
                  mon.dittoDisguise == nil || mon.dittoRevealed, !holdsEverstone(id) else { return false }
            let options = growthOptions(of: node, gender: mon.profile?.gender)
            guard !options.isEmpty, mon.usedAtStage >= stageThreshold(for: mon) else { return false }
            let next = lineStep(of: mon, at: node, among: options).next
            guard let rule = EvolutionRules.rule(for: next.speciesID), !rule.paths.isEmpty else { return false }
            let context = storedLineContext(stored)
            return !rule.paths.contains { path in
                path.allSatisfy { ($0.opensByItself && $0.isMet(in: context)) || $0.opensWithoutPlayer(in: context) }
            }
        }
        guard let entry = state.dex.first(where: { $0.id == id && !$0.isReleased }),
              let line = expShareLines[entry.baseID] else { return false }
        let options = graduateOptions(entry, in: line)
        if options.isEmpty { return (entry.profile?.level ?? 5) >= 100 }
        guard !holdsEverstone(id) else { return false }
        let context = graduateContext(entry)
        return options.allSatisfy { EvolutionRules.rule(for: $0.speciesID)?.waitsOnPlayer(in: context) == true }
    }
}
