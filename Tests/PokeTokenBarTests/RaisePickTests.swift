import XCTest
@testable import PokeTokenBar

private struct LineProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [
            EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                rarity: .common,
                names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"], 6: ["en": "Charizard"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "p", height: 1, weight: 1, baseExperience: nil, genderRate: -1,
                       types: [], baseStats: [:], abilities: [],
                       moves: [PokemonMoveOption(name: "late-move", learnMethods: [
                        PokemonMoveLearnMethod(method: "level-up", level: 55)])])
    }
}

/// Raising a graduate parks the line (or egg) untouched; usage goes only to the raised one.
@MainActor
final class RaisePickTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private static let lineID = "line"
    private static let firstID = "first"
    private static let secondID = "second"

    private func graduate(_ id: String, species: Int, level: Int = 50, form: PokemonForm? = nil) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 11, instanceID: id)
        profile.level = 5
        profile.advanceGrowth(to: PokemonBalance.graduationTotal(.common) * (level - 5) / 95, rarity: .common)
        return DexEntry(id: id, baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                        caughtAt: Date(timeIntervalSince1970: 1_000), isShiny: false, nature: .adamant,
                        profile: profile, names: [species: ["ko": "g\(species)", "en": "g\(species)"]], form: form)
    }

    private func lineState() -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .en
        state.claimedTodayTokensByProvider = ["test": 0]
        state.lastDate = "d1"
        var profile = PokemonProfile.generate(seed: 4, instanceID: Self.lineID)
        profile.level = 20
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 777, rarity: .common,
                                totalForms: 3, profile: profile)
        state.spentTokens = 100
        state.active!.evolution.spentBaseline = 10
        state.dex = [graduate(Self.firstID, species: 25), graduate(Self.secondID, species: 95)]
        return state
    }

    private func makeStore(_ state: CompanionState) throws -> CompanionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("raise-pick-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "raise-pick-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(1.0, forKey: "growthDifficulty")
        defaults.set(true, forKey: PokemonBalance.difficultyMigratedKey)
        return CompanionStore(provider: LineProvider(), fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    private func use(_ store: CompanionStore, _ total: Int) {
        store.update(todayTokensByProvider: ["test": total], todayDate: "d1", monthTotal: total, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func entry(_ store: CompanionStore, _ id: String) throws -> DexEntry {
        try XCTUnwrap(store.state.dex.first { $0.id == id })
    }

    // MARK: switching

    func testSwitchToAGraduateAndBackKeepsTheLineExactly() throws {
        let store = try makeStore(lineState())
        let before = try json(store.state.active)
        XCTAssertTrue(store.raise(entryID: Self.firstID))
        XCTAssertEqual(store.state.raisedEntryID, Self.firstID)
        XCTAssertTrue(store.isLineParked)
        XCTAssertEqual(try json(store.state.active), before)
        XCTAssertTrue(store.resumeLine())
        XCTAssertNil(store.state.raisedEntryID)
        XCTAssertNil(store.state.parkedSpentTokens)
        XCTAssertEqual(try json(store.state.active), before)
    }

    func testRaisedGraduateIsThePokemonBeingRaised() throws {
        let store = try makeStore(lineState())
        store.raise(entryID: Self.firstID)
        XCTAssertEqual(store.currentSpeciesID, 25)
        XCTAssertFalse(store.isEgg)
        XCTAssertTrue(store.hasRaisedPokemon)
        XCTAssertFalse(store.hasActive)
        XCTAssertEqual(store.boxIndividual(id: Self.firstID)?.role, .raising)
        XCTAssertEqual(store.boxIndividual(id: Self.lineID)?.role, .parked)
    }

    func testRaisingTheRaisedOneOrAnUnknownOrPendingTradeEvolutionIsRefused() throws {
        var state = lineState()
        state.dex.append({ var e = graduate("pending", species: 95); e.tradeEvolutionPending = true; return e }())
        state.dex.append({ var e = graduate("gone", species: 95); e.releasedAt = Date(); return e }())
        let store = try makeStore(state)
        XCTAssertTrue(store.raise(entryID: Self.firstID))
        XCTAssertFalse(store.raise(entryID: Self.firstID))
        XCTAssertFalse(store.raise(entryID: "nobody"))
        XCTAssertFalse(store.raise(entryID: "pending"))
        XCTAssertFalse(store.raise(entryID: "gone"))
        XCTAssertEqual(store.state.raisedEntryID, Self.firstID)
    }

    // MARK: crediting

    func testUsageGoesOnlyToTheRaisedGraduate() throws {
        let store = try makeStore(lineState())
        let lineBefore = try json(store.state.active)
        let eggBefore = store.state.eggUsage
        let levelBefore = try XCTUnwrap(entry(store, Self.firstID).profile?.level)
        let growthBefore = try XCTUnwrap(entry(store, Self.firstID).profile?.growthTokens)
        let total = PokemonBalance.graduationTotal(.common) / 10
        store.raise(entryID: Self.firstID)
        use(store, total)
        let first = try entry(store, Self.firstID)
        XCTAssertEqual(first.profile?.growthTokens, growthBefore + total)
        XCTAssertGreaterThan(try XCTUnwrap(first.profile?.level), levelBefore)
        XCTAssertEqual(try entry(store, Self.secondID).profile?.level, levelBefore)
        XCTAssertEqual(try json(store.state.active), lineBefore)
        XCTAssertEqual(store.state.eggUsage, eggBefore)
        XCTAssertEqual(store.state.usedSinceInstall, total)
    }

    func testARaisedGraduateLearnsTheMovesOfTheLevelsItReaches() async throws {
        let store = try makeStore(lineState())
        await store.loadPokemonDetails(speciesID: 25)
        store.raise(entryID: Self.firstID)
        XCTAssertFalse(try entry(store, Self.firstID).profile?.moves.map(\.name).contains("late-move") ?? true)
        use(store, PokemonBalance.graduationTotal(.common) / 10)
        XCTAssertTrue(try entry(store, Self.firstID).profile?.moves.map(\.name).contains("late-move") ?? false)
    }

    func testAShinyRaisedGraduateDoesNotMakeTheParkedLinesSpeciesShiny() throws {
        var state = lineState()
        state.dex[0].isShiny = true
        let store = try makeStore(state)
        store.raise(entryID: Self.firstID)
        let parkedSpecies = try XCTUnwrap(store.dexSpecies.first { $0.id == 5 })
        XCTAssertFalse(parkedSpecies.isShiny)
        XCTAssertTrue(parkedSpecies.hasNormal)
        XCTAssertFalse(parkedSpecies.isRaising)
        let raisedSpecies = try XCTUnwrap(store.dexSpecies.first { $0.id == 25 })
        XCTAssertTrue(raisedSpecies.isRaising)
    }

    func testUsageGoesToTheLineAgainAfterResumingAndTheGraduateStopsGrowing() throws {
        let store = try makeStore(lineState())
        store.raise(entryID: Self.firstID)
        use(store, 1_000_000)
        let grown = try json(entry(store, Self.firstID))
        store.resumeLine()
        use(store, 1_500_000)
        XCTAssertEqual(try json(entry(store, Self.firstID)), grown)
        XCTAssertEqual(store.state.active?.usedAtStage, 777 + 500_000)
    }

    func testUsageBeforeRaisingStillGoesToTheLine() throws {
        let store = try makeStore(lineState())
        use(store, 400)
        XCTAssertEqual(store.state.active?.usedAtStage, 777 + 400)
        store.raise(entryID: Self.firstID)
        use(store, 900)
        XCTAssertEqual(store.state.active?.usedAtStage, 777 + 400)
    }

    // MARK: parked egg

    func testAParkedEggNeitherFillsNorHatches() async throws {
        var state = lineState()
        state.active = nil
        state.eggUsage = 500
        let store = try makeStore(state)
        XCTAssertTrue(store.isEgg)
        store.raise(entryID: Self.firstID)
        XCTAssertFalse(store.isEgg)
        use(store, store.eggHatchThreshold * 2)
        await store.hatch(baseID: 4)
        await store.hatchIfNeeded()
        XCTAssertNil(store.state.active)
        XCTAssertEqual(store.state.eggUsage, 500)
        store.resumeLine()
        XCTAssertTrue(store.isEgg)
        XCTAssertEqual(store.state.eggUsage, 500)
        await store.hatch(baseID: 4)
        XCTAssertNotNil(store.state.active)
    }

    // MARK: second graduate

    func testASecondGraduateSendsTheFirstBackWithItsLevel() throws {
        let store = try makeStore(lineState())
        let lineBefore = try json(store.state.active)
        store.raise(entryID: Self.firstID)
        use(store, PokemonBalance.graduationTotal(.common) / 10)
        let reached = try XCTUnwrap(entry(store, Self.firstID).profile?.level)
        XCTAssertGreaterThan(reached, 50)
        XCTAssertTrue(store.raise(entryID: Self.secondID))
        XCTAssertEqual(store.state.raisedEntryID, Self.secondID)
        XCTAssertEqual(store.boxIndividual(id: Self.firstID)?.role, .graduated)
        XCTAssertEqual(store.boxIndividual(id: Self.firstID)?.level, reached)
        use(store, PokemonBalance.graduationTotal(.common) / 5)
        XCTAssertEqual(try entry(store, Self.firstID).profile?.level, reached)
        XCTAssertEqual(store.state.parkedSpentTokens, 100)
        store.resumeLine()
        XCTAssertEqual(try json(store.state.active), lineBefore)
    }

    // MARK: resume

    func testResumeShiftsTheSpendBaselineBySpendingDuringThePark() throws {
        var state = lineState()
        state.usedSinceInstall = 9_000_000_000
        let store = try makeStore(state)
        store.raise(entryID: Self.firstID)
        XCTAssertTrue(store.buy(.rareCandy))
        let spent = store.state.spentTokens - 100
        XCTAssertGreaterThan(spent, 0)
        store.resumeLine()
        XCTAssertEqual(store.state.active?.evolution.spentBaseline, 10 + spent)
    }

    func testAReleasedRaisedGraduateResumesTheLineOnReconcile() throws {
        var state = lineState()
        state.raisedEntryID = Self.firstID
        state.parkedSpentTokens = 100
        state.spentTokens = 250
        state.dex[0].releasedAt = Date()
        state.reconcileRaised()
        XCTAssertNil(state.raisedEntryID)
        XCTAssertNil(state.parkedSpentTokens)
        XCTAssertEqual(state.active?.evolution.spentBaseline, 10 + 150)
    }

    // MARK: save

    func testASaveWithoutTheNewFieldsDecodesAndDoesNotWriteThemBack() throws {
        let data = try JSONEncoder().encode(lineState())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "raisedEntryID")
        object.removeValue(forKey: "parkedSpentTokens")
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CompanionState.self, from: old)
        XCTAssertNil(decoded.raisedEntryID)
        XCTAssertNil(decoded.parkedSpentTokens)
        XCTAssertEqual(try json(decoded.active), try json(lineState().active))
        let text = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(text.contains("raisedEntryID"))
        XCTAssertFalse(text.contains("parkedSpentTokens"))
    }

    func testASnapshotPreviewShowsTheRaisedGraduateNotTheParkedLine() throws {
        var state = lineState()
        XCTAssertEqual(state.currentPokemonPreview.speciesID, 5)
        state.raisedEntryID = Self.firstID
        XCTAssertEqual(state.currentPokemonPreview.speciesID, 25)
        state.active = nil
        XCTAssertEqual(state.currentPokemonPreview.speciesID, 25)
        state.raisedEntryID = nil
        XCTAssertNil(state.currentPokemonPreview.speciesID)
    }

    func testTheRaisedPointerSurvivesAReload() throws {
        let store = try makeStore(lineState())
        store.raise(entryID: Self.firstID)
        let data = try JSONEncoder().encode(store.state)
        let decoded = try JSONDecoder().decode(CompanionState.self, from: data)
        XCTAssertEqual(decoded.raisedEntryID, Self.firstID)
        XCTAssertEqual(decoded.parkedSpentTokens, 100)
    }

    func testAPointerToAMissingEntryIsDroppedOnLoad() throws {
        var state = lineState()
        state.raisedEntryID = "nobody"
        state.parkedSpentTokens = 100
        state.reconcileRaised()
        XCTAssertNil(state.raisedEntryID)
        XCTAssertNil(state.parkedSpentTokens)
    }

    // MARK: battle

    func testBattleAutoPickFollowsTheRaisedOneAndTheParkedLineSitsOut() throws {
        let store = try makeStore(lineState())
        XCTAssertEqual(BattleEntry.autoFighter(state: store.state)?.id, Self.lineID)
        store.raise(entryID: Self.secondID)
        XCTAssertEqual(BattleEntry.autoFighter(state: store.state)?.id, Self.secondID)
        XCTAssertEqual(BattleEntry.autoFighter(state: store.state)?.isRaised, true)
        XCTAssertFalse(BattleEntry.candidates(in: store.state).contains { $0.id == Self.lineID })
        XCTAssertEqual(BattleEntry.candidates(in: store.state).filter(\.isRaised).count, 1)
        store.resumeLine()
        XCTAssertEqual(BattleEntry.autoFighter(state: store.state)?.id, Self.lineID)
    }

    func testThePartySendsTheRaisedGraduateFirst() throws {
        let store = try makeStore(lineState())
        store.raise(entryID: Self.secondID)
        XCTAssertEqual(PartyBuilder.party(from: store.state).first?.pokemonID, 95)
    }

    // MARK: trade

    func testTradeRefusesTheRaisedGraduateAndTheParkedLine() throws {
        let store = try makeStore(lineState())
        let line = try XCTUnwrap(store.boxIndividual(id: Self.lineID)?.entry)
        XCTAssertEqual(store.tradeRefusal(for: line, fightingIDs: []), .raising)
        XCTAssertNil(store.tradeRefusal(for: try entry(store, Self.firstID), fightingIDs: []))
        store.raise(entryID: Self.firstID)
        XCTAssertEqual(store.tradeRefusal(for: try entry(store, Self.firstID), fightingIDs: []), .raising)
        XCTAssertEqual(store.tradeRefusal(for: line, fightingIDs: []), .parked)
        XCTAssertNil(store.tradeRefusal(for: try entry(store, Self.secondID), fightingIDs: []))
        let offered = TradePool.build(state: store.state, fightingIDs: []) { _ in "n" }.map(\.id)
        XCTAssertEqual(offered, [Self.secondID])
        XCTAssertEqual(store.tradableEntries(fightingIDs: []).map(\.id), [Self.secondID])
    }

    // MARK: representative

    func testBoxRepresentativeMatchesTheDexPathAndClears() throws {
        let store = try makeStore(lineState())
        let dexStore = try makeStore(lineState())
        let pikachu = try entry(store, Self.firstID)
        XCTAssertFalse(store.isRepresentative(pikachu))
        XCTAssertTrue(store.toggleRepresentative(of: pikachu))
        XCTAssertTrue(dexStore.setRepresentativeSpeciesID(25))
        XCTAssertEqual(store.state.representativeSpeciesID, dexStore.state.representativeSpeciesID)
        XCTAssertEqual(store.state.representativeForm, dexStore.state.representativeForm)
        XCTAssertTrue(store.isRepresentative(pikachu))
        XCTAssertTrue(store.isRepresentative(try XCTUnwrap(store.dexSpecies.first { $0.id == 25 })))
        XCTAssertFalse(store.isRepresentative(try entry(store, Self.secondID)))
        XCTAssertTrue(store.toggleRepresentative(of: pikachu))
        XCTAssertNil(store.state.representativeSpeciesID)
        XCTAssertFalse(store.isRepresentative(pikachu))
    }

    func testBoxRepresentativeKeepsTheFormOfTheIndividual() throws {
        var state = lineState()
        let unown = PokemonForm.unownSpeciesID
        state.dex.append(graduate("unown-b", species: unown, form: .b))
        state.dex.append(graduate("unown-c", species: unown, form: .c))
        let store = try makeStore(state)
        let b = try entry(store, "unown-b"), c = try entry(store, "unown-c")
        XCTAssertTrue(store.toggleRepresentative(of: b))
        XCTAssertEqual(store.state.representativeForm, .b)
        XCTAssertTrue(store.isRepresentative(b))
        XCTAssertFalse(store.isRepresentative(c))
        XCTAssertTrue(store.toggleRepresentative(of: c))
        XCTAssertEqual(store.state.representativeForm, .c)
        XCTAssertFalse(store.isRepresentative(b))
    }

    func testTheRaisedLineIndividualCanBeTheRepresentativeToo() throws {
        let store = try makeStore(lineState())
        let line = try XCTUnwrap(store.boxIndividual(id: Self.lineID)?.entry)
        XCTAssertTrue(store.toggleRepresentative(of: line))
        XCTAssertEqual(store.state.representativeSpeciesID, 5)
        XCTAssertTrue(store.isRepresentative(line))
    }
}
