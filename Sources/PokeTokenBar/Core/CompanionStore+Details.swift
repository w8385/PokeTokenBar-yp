import Foundation

extension CompanionStore {
    // MARK: Pokémon combat profiles / details

    /// Exact current/final individuals for a Pokédex species. Earlier evolution stages remain
    /// species reference pages; the same evolved individual is not duplicated as a second creature.
    func pokemonIndividuals(speciesID: Int, form: PokemonForm? = nil) -> [DexEntry] {
        let form = PokemonForm.resolved(speciesID: speciesID, form: form)
        return dexEntriesSorted.filter {
            $0.finalID == speciesID && $0.profile != nil
                && PokemonForm.resolved(speciesID: speciesID, form: $0.form) == form
        }
    }

    /// Loads immutable PokéAPI metadata and persists any deferred profile fields exactly once.
    func loadPokemonDetails(speciesID: Int) async {
        if let details = pokemonDetailsByID[speciesID] {
            enrichProfiles(for: speciesID, with: details)
            return
        }
        guard let detailProvider, !loadingPokemonDetailIDs.contains(speciesID) else { return }
        loadingPokemonDetailIDs.insert(speciesID)
        failedPokemonDetailIDs.remove(speciesID)
        defer { loadingPokemonDetailIDs.remove(speciesID) }
        do {
            let details = try await detailProvider.pokemonDetails(speciesID: speciesID)
            pokemonDetailsByID[speciesID] = details
            enrichProfiles(for: speciesID, with: details)
        } catch {
            failedPokemonDetailIDs.insert(speciesID)
            AppLog.write("pokemon details fetch failed id=\(speciesID): \(error)")
        }
    }

    /// Startup/background warmup for the only profile needed before a detail page is opened.
    func preparePokemonProfiles() async {
        guard let speciesID = raisedGraduate?.finalID ?? state.active?.currentID else { return }
        await loadPokemonDetails(speciesID: speciesID)
    }

    private func enrichProfiles(for speciesID: Int, with details: PokemonDetails) {
        var changed = false
        if var active = state.active, active.currentID == speciesID, var profile = active.profile {
            let before = profile
            profile.enrich(with: details)
            if profile != before {
                active.profile = profile
                state.active = active
                changed = true
            }
        }
        for index in state.dex.indices where state.dex[index].finalID == speciesID {
            guard var profile = state.dex[index].profile else { continue }
            let before = profile
            profile.enrich(with: details)
            if profile != before {
                state.dex[index].profile = profile
                changed = true
            }
        }
        if changed { save() }
    }

    /// Additive migration for pre-profile saves. It never needs network and therefore cannot block launch.
    /// Deferred fields (gender/ability/moves) are filled after the cached/detail fetch succeeds.
    func migratePokemonProfilesIfNeeded() {
        var changed = false
        if var active = state.active, active.profile == nil {
            let key = "active:\(active.baseID):\(active.pathIDs.map(String.init).joined(separator: ",")):\(state.lastDate)"
            active.profile = PokemonProfile.generate(seed: PokemonProfileMigration.seed(key))
            state.active = active
            changed = true
        }
        for index in state.dex.indices {
            let entry = state.dex[index]
            if entry.profile == nil {
                let graduated = !entry.isReleased
                // Released entries only persisted their reached `chainOrder`, not the originally
                // planned form count. Treating that count as `totalForms` is the best recoverable
                // estimate, but it is an upper bound when release happened before the planned final.
                let growth = graduated
                    ? PokemonBalance.graduationTotal(entry.rarity)
                    : Self.reconstructedGrowthTokens(
                        rarity: entry.rarity, totalForms: max(1, entry.chainOrder.count),
                        completedStages: max(0, entry.chainOrder.count - 1), currentStageUsage: 0)
                var profile = PokemonProfile.generate(
                    seed: PokemonProfileMigration.seed("dex:\(entry.id):\(entry.finalID)"),
                    growthTokens: growth,
                    instanceID: entry.id)
                profile.applyGrowth(0, rarity: entry.rarity)
                state.dex[index].profile = profile
                changed = true
            }
        }
        let before = state.active?.profile
        reconcileActiveProfileGrowth()
        if !changed {
            if before != state.active?.profile { save() }
            return
        }

        // One recoverable snapshot before the first format expansion. Never overwrite it.
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("companion-state.pre-profiles-v1.json")
        if FileManager.default.fileExists(atPath: fileURL.path),
           !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
        save()
        AppLog.write("pokemon profile migration complete — previous state kept as \(backup.lastPathComponent)")
    }

    /// Completed phases retain their earned credit. Only the current raw phase is repriced
    /// by the repeat boost; its profile high-water mark prevents level loss.
    func reconcileActiveProfileGrowth() {
        guard let active = state.active else { return }
        state.active = reconciledProfileGrowth(active)
    }

    func reconciledProfileGrowth(_ mon: MonState) -> MonState {
        var active = mon
        guard var profile = active.profile else { return mon }
        let completed = Self.reconstructedGrowthTokens(
            rarity: active.rarity, totalForms: active.totalForms,
            completedStages: active.stageIndex, currentStageUsage: 0)
        let standardPhase = PokemonBalance.phaseThreshold(
            rarity: active.rarity, totalForms: active.totalForms, stageIndex: active.stageIndex)
        let fraction = min(1, max(0, Double(active.usedAtStage) / Double(max(1, stageThreshold(for: active)))))
        let candidate = min(PokemonBalance.graduationTotal(active.rarity),
                            completed + Int((Double(standardPhase) * fraction).rounded(.down)))
        profile.advanceGrowth(to: candidate, rarity: active.rarity)
        if let details = pokemonDetailsByID[active.currentID] { profile.enrich(with: details) }
        active.profile = profile
        return active
    }

    static func reconstructedGrowthTokens(rarity: Rarity, totalForms: Int,
                                          completedStages: Int, currentStageUsage: Int) -> Int {
        let forms = max(1, totalForms)
        let completed = min(max(0, completedStages), forms)
        let completedGrowth = (0..<completed).reduce(0) { total, stage in
            total + PokemonBalance.phaseThreshold(rarity: rarity, totalForms: forms, stageIndex: stage)
        }
        return min(SaveTransfer.maxTokenValue,
                   completedGrowth + min(SaveTransfer.maxTokenValue, max(0, currentStageUsage)))
    }
}
