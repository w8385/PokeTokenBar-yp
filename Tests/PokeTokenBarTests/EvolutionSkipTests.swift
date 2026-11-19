import XCTest
@testable import PokeTokenBar

private func node(_ id: Int, _ children: [EvoNode] = []) -> EvoNode {
    EvoNode(speciesID: id, children: children, methods: [EvoMethod(trigger: "level-up")])
}

private struct SkipProvider: PokeProviding {
    let tree: EvoNode
    var names: [Int: [String: String]] = [:]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: tree.speciesID, tree: tree, rarity: .common, names: names)
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private final class SkipClock: @unchecked Sendable {
    var now = Calendar.current.date(bySettingHour: 12, minute: 5, second: 0, of: Date())!
    func set(_ period: DayPeriod) {
        now = Calendar.current.date(bySettingHour: 12, minute: period == .day ? 5 : 15, second: 0, of: Date())!
    }
}

@MainActor
final class EvolutionSkipTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    private var lastFile: URL?
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func store(tree: EvoNode, clock: SkipClock = SkipClock(), inventory: [ItemKind: Int] = [:],
                       state: CompanionState = CompanionState(), names: [Int: [String: String]] = [:]) throws
        -> CompanionStore {
        var state = state
        state.installBaselineSet = true
        for (kind, count) in inventory { state.inventory[kind.rawValue] = count }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evo-skip-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        lastFile = file
        let suite = "evo-skip-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: SkipProvider(tree: tree, names: names), clock: { clock.now }, fileURL: file,
                              rng: SeededRNG(seed: 1), dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func pet(_ s: CompanionStore, _ clock: SkipClock, times: Int) {
        for _ in 0..<times { clock.now.addTimeInterval(11); s.recordPet() }
    }

    private func raisingEntry(_ s: CompanionStore) throws -> DexEntry {
        try XCTUnwrap(s.boxIndividuals.first { $0.role == .raising }?.entry)
    }

    /// Munchlax ready for Snorlax with no pets, skipped, then raised again with its line loaded.
    private func raisedSkippedMunchlax(_ clock: SkipClock, pets: Int = 0, inventory: [ItemKind: Int] = [:]) async throws
        -> (CompanionStore, String) {
        let s = try store(tree: node(446, [node(143)]), clock: clock, inventory: inventory)
        await s.hatch(baseID: 446)
        pet(s, clock, times: pets)
        s.applyUsage(s.tokensToNext)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        XCTAssertTrue(s.skipEvolutionAndGraduate())
        XCTAssertTrue(s.raise(entryID: id))
        await s.checkRaisedGraduateEvolution()
        return (s, id)
    }

    // MARK: Skip

    func testSkipIsOfferedOnlyOnceTheFormIsReadyAndAConditionHoldsItBack() async throws {
        let s = try store(tree: node(446, [node(143)]))
        await s.hatch(baseID: 446)
        XCTAssertFalse(s.canSkipEvolution, "not ready yet")
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 446)
        XCTAssertTrue(s.canSkipEvolution, "ready and Snorlax waits for pets")
        let cards = s.evolutionCards(for: 446, individual: try raisingEntry(s))
        let skipCard = try XCTUnwrap(cards.first { $0.offersSkip })
        XCTAssertEqual(skipCard.rule.species, 143, "the card offering the skip is the step the growth is held on")
    }

    func testOnlyTheClockBlockingOffersNoSkip() async throws {
        let clock = SkipClock()
        let s = try store(tree: node(433, [node(358)]), clock: clock)
        await s.hatch(baseID: 433)
        pet(s, clock, times: 40)
        clock.set(.day)
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 433, "Chimecho waits for the night")
        XCTAssertFalse(s.canSkipEvolution)
        XCTAssertFalse(s.skipEvolutionAndGraduate())
        XCTAssertNotNil(s.state.active)
        XCTAssertFalse(s.evolutionCards(for: 433, individual: try raisingEntry(s)).contains { $0.offersSkip })
    }

    func testAConditionLeftBesideTheClockStillOffersTheSkip() async throws {
        let clock = SkipClock()
        let s = try store(tree: node(433, [node(358)]), clock: clock)
        await s.hatch(baseID: 433)
        clock.set(.day)
        s.applyUsage(s.tokensToNext)
        XCTAssertTrue(s.canSkipEvolution, "the pets are missing too")
    }

    func testAFormWithNothingLeftToSkipOffersNoSkip() async throws {
        let plain = try store(tree: node(1, [node(2)]))
        await plain.hatch(baseID: 1)
        plain.applyUsage(plain.tokensToNext - 1)
        XCTAssertFalse(plain.canSkipEvolution, "a plain step has no gate")
        let last = try store(tree: node(143))
        await last.hatch(baseID: 143)
        XCTAssertFalse(last.canSkipEvolution, "a last form graduates by itself")
        XCTAssertFalse(last.skipEvolutionAndGraduate())
    }

    func testAnEverstoneHoldsTheFormSoThereIsNoSkip() async throws {
        let s = try store(tree: node(446, [node(143)]), inventory: [.everstone: 1])
        await s.hatch(baseID: 446)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        XCTAssertTrue(s.equip(.everstone, to: id))
        s.applyUsage(s.tokensToNext)
        XCTAssertFalse(s.canSkipEvolution)
    }

    func testSkippingGraduatesTheCurrentFormAndKeepsItsProgress() async throws {
        let clock = SkipClock()
        let s = try store(tree: node(446, [node(143)]), clock: clock)
        await s.hatch(baseID: 446)
        pet(s, clock, times: 12)
        s.applyUsage(s.tokensToNext + 7)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        XCTAssertTrue(s.skipEvolutionAndGraduate())
        XCTAssertNil(s.state.active, "a new egg comes")
        XCTAssertEqual(s.state.eggUsage, 0)
        let entry = try XCTUnwrap(s.state.dex.first { $0.id == id })
        XCTAssertEqual(entry.finalID, 446)
        XCTAssertEqual(entry.chainOrder, [446])
        XCTAssertEqual(s.state.graduateEvolution[id]?.pets, 12)
        XCTAssertEqual(s.state.graduateEvolution[id]?.graduateXP, 7)
        XCTAssertNil(s.state.graduateEvolution[id]?.stuckNotified)
        XCTAssertNotNil(s.justGraduated)
        XCTAssertNil(s.pendingEvolutionGate(), "the egg has no step")
    }

    func testADisguisedDittoOffersNoSkip() async throws {
        var state = CompanionState()
        state.active = MonState(baseID: 446, pathIDs: [446], plannedPathIDs: [446, 143], stageIndex: 0,
                                usedAtStage: 100_000_000, rarity: .common, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 3), dittoDisguise: 446)
        let s = try store(tree: node(446, [node(143)]), state: state)
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        for _ in 0..<100 where s.currentLine == nil { await Task.yield() }
        XCTAssertNotNil(s.currentLine)
        XCTAssertNotNil(s.pendingEvolutionGate(), "the step is held by pets")
        XCTAssertFalse(s.canSkipEvolution, "a Ditto in disguise must not graduate as the form it copies")
    }

    func testAGraduateTakesThePlainStepThatMatchesTheClock() async throws {
        let split = EvoNode(speciesID: 1, children: [
            EvoNode(speciesID: 2, children: [], methods: [EvoMethod(trigger: "level-up", timeOfDay: "day")]),
            EvoNode(speciesID: 3, children: [], methods: [EvoMethod(trigger: "level-up", timeOfDay: "night")]),
        ], methods: [])
        var state = CompanionState()
        state.dex = [DexEntry(id: "g", baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date(),
                              profile: PokemonProfile.generate(seed: 5))]
        let clock = SkipClock()
        clock.set(.night)
        let s = try store(tree: split, clock: clock, state: state)
        XCTAssertTrue(s.raise(entryID: "g"))
        await s.checkRaisedGraduateEvolution()
        XCTAssertEqual(s.currentSpeciesID, 3)
    }

    func testAMidFormGraduateWithNoSavedProgressStartsFresh() async throws {
        var state = CompanionState()
        state.dex = [DexEntry(id: "traded", baseID: 446, finalID: 446, chainOrder: [446], rarity: .common,
                              caughtAt: Date(), profile: PokemonProfile.generate(seed: 5))]
        let clock = SkipClock()
        let names = [446: ["en": "Munchlax"], 143: ["en": "Snorlax"]]
        let s = try store(tree: node(446, [node(143)]), clock: clock, state: state, names: names)
        XCTAssertTrue(s.raise(entryID: "traded"))
        await s.checkRaisedGraduateEvolution()
        XCTAssertNil(s.state.graduateEvolution["traded"])
        pet(s, clock, times: 29)
        XCTAssertEqual(s.state.graduateEvolution["traded"]?.pets, 29)
        XCTAssertEqual(s.currentSpeciesID, 446)
        pet(s, clock, times: 1)
        XCTAssertEqual(s.currentSpeciesID, 143)
        let entry = try XCTUnwrap(s.state.dex.first)
        XCTAssertEqual(entry.names?[143]?["en"], "Snorlax", "the new form is named offline")
        XCTAssertEqual(entry.namesVersion, DexEntry.currentNamesVersion)
    }

    func testAConditionBlockPointsTheNotificationAtTheSkip() async throws {
        let s = try store(tree: node(446, [node(143)]))
        await s.hatch(baseID: 446)
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.latestEvent?.text, L(s.language).notifEvolveStuckSkippableBody(
            s.displayName, L(s.language).evolutionRequirementText(.pets(30), speciesName: { "#\($0)" })))
    }

    func testTheKoreanConfirmPicksTheParticleForTheName() {
        XCTAssertEqual(L(.ko).skipEvolutionConfirm("피츄"), "피츄를 지금 모습으로 졸업할까요? 새 알이 와요.")
        XCTAssertEqual(L(.ko).skipEvolutionConfirm("먹고자"), "먹고자를 지금 모습으로 졸업할까요? 새 알이 와요.")
        XCTAssertEqual(L(.ko).skipEvolutionConfirm("리자몽"), "리자몽을 지금 모습으로 졸업할까요? 새 알이 와요.")
    }

    // MARK: Evolve later

    func testARaisedGraduateEvolvesOnceItsConditionIsMetAndNotBefore() async throws {
        let clock = SkipClock()
        let (s, id) = try await raisedSkippedMunchlax(clock, pets: 10, inventory: [.leftovers: 1])
        XCTAssertTrue(s.equip(.leftovers, to: id))
        let before = try XCTUnwrap(s.state.dex.first { $0.id == id })
        XCTAssertEqual(s.currentSpeciesID, 446)
        XCTAssertEqual(s.pendingEvolutionGate()?.rule.species, 143)
        pet(s, clock, times: 19)
        XCTAssertEqual(s.currentSpeciesID, 446, "29 of 30 pets")
        XCTAssertEqual(s.state.graduateEvolution[id]?.pets, 29, "the pets before the skip still count")
        pet(s, clock, times: 1)
        XCTAssertEqual(s.currentSpeciesID, 143)
        let entry = try XCTUnwrap(s.state.dex.first { $0.id == id })
        XCTAssertEqual(entry.chainOrder, [446, 143])
        XCTAssertEqual(entry.profile?.instanceID, before.profile?.instanceID)
        XCTAssertEqual(entry.profile?.ivs, before.profile?.ivs)
        XCTAssertEqual(entry.isShiny, before.isShiny)
        XCTAssertEqual(s.heldItem(of: id), .leftovers, "the held item stays on the same individual")
        XCTAssertEqual(s.state.raisedEntryID, id, "the same individual is still raised")
        XCTAssertTrue(s.state.ownsSpecies(446), "the form it left stays in the Pokédex")
        XCTAssertTrue(s.state.ownsSpecies(143))
        XCTAssertNil(s.state.graduateEvolution[id], "a last form has nothing left to track")
        XCTAssertEqual(s.justEvolvedTo, s.displayName)
    }

    func testARaisedGraduateWaitsForTheClockLikeALine() async throws {
        let clock = SkipClock()
        let s = try store(tree: node(433, [node(358)]), clock: clock)
        await s.hatch(baseID: 433)
        clock.set(.day)
        s.applyUsage(s.tokensToNext)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        XCTAssertTrue(s.skipEvolutionAndGraduate())
        XCTAssertTrue(s.raise(entryID: id))
        await s.checkRaisedGraduateEvolution()
        clock.now = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!
        pet(s, clock, times: 40)
        XCTAssertEqual(s.state.graduateEvolution[id]?.pets, 40)
        await s.checkRaisedGraduateEvolution()
        XCTAssertEqual(s.currentSpeciesID, 433, "pets met, but not night")
        clock.now = Calendar.current.date(bySettingHour: 13, minute: 15, second: 30, of: Date())!
        s.checkEvolutionGate()
        try await waitUntil("the gate tick to evolve the raised graduate") { s.currentSpeciesID == 358 }
    }

    func testProgressSavedBeforeARelaunchKeepsCountingBeforeTheLineLoads() async throws {
        let clock = SkipClock()
        let (first, id) = try await raisedSkippedMunchlax(clock, pets: 10)
        _ = first
        let file = try XCTUnwrap(lastFile)
        let suite = "evo-skip-\(UUID())"
        suites.append(suite)
        let s = CompanionStore(provider: SkipProvider(tree: node(446, [node(143)])), clock: { clock.now }, fileURL: file,
                               rng: SeededRNG(seed: 2), dittoDisguiseRollingEnabled: false,
                               defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(s.state.raisedEntryID, id)
        XCTAssertNil(s.raisedGraduateLine, "the line is not loaded yet")
        pet(s, clock, times: 5)
        XCTAssertEqual(s.state.graduateEvolution[id]?.pets, 15)
        await s.checkRaisedGraduateEvolution()
        pet(s, clock, times: 15)
        XCTAssertEqual(s.currentSpeciesID, 143)
    }

    func testAnEverstoneHoldsARaisedGraduateToo() async throws {
        let clock = SkipClock()
        let (s, id) = try await raisedSkippedMunchlax(clock, pets: 25, inventory: [.everstone: 1])
        XCTAssertTrue(s.equip(.everstone, to: id))
        pet(s, clock, times: 10)
        XCTAssertEqual(s.currentSpeciesID, 446)
        XCTAssertTrue(s.unequip(from: id))
        XCTAssertEqual(s.currentSpeciesID, 143)
    }

    func testTheLongStagePathCountsTheGraduatesOwnXP() async throws {
        let s = try store(tree: node(705, [node(706)]))
        await s.hatch(baseID: 705)
        s.applyUsage(s.tokensToNext)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        XCTAssertTrue(s.skipEvolutionAndGraduate(), "no rain yet")
        XCTAssertTrue(s.raise(entryID: id))
        await s.checkRaisedGraduateEvolution()
        let entry = try XCTUnwrap(s.state.dex.first { $0.id == id })
        let threshold = PokemonBalance.phaseThreshold(rarity: entry.rarity, totalForms: 2, stageIndex: 0)
        XCTAssertEqual(s.currentSpeciesID, 705, "a graduate counts as 100%; the path asks for 200%")
        func credit(_ total: Int) {
            s.update(todayTokensByProvider: ["test": total], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
        }
        credit(0)
        credit(threshold - 1)
        XCTAssertEqual(s.currentSpeciesID, 705)
        credit(threshold)
        XCTAssertEqual(s.currentSpeciesID, 706)
    }

    func testATerminalGraduateHasNoStepAndKeepsTheFinalFormLabel() async throws {
        let s = try store(tree: node(143))
        await s.hatch(baseID: 143)
        s.applyUsage(s.tokensToNext)
        let id = try XCTUnwrap(s.state.dex.last?.id)
        XCTAssertTrue(s.raise(entryID: id))
        await s.checkRaisedGraduateEvolution()
        XCTAssertNil(s.pendingEvolutionGate())
        s.recordPet()
        XCTAssertNil(s.state.graduateEvolution[id])
        XCTAssertTrue(s.stageText.hasSuffix(s.l.finalForm))
    }

    func testTheParkedLinesPageDoesNotShowTheGraduatesStep() async throws {
        let (s, _) = try await raisedSkippedMunchlax(SkipClock())
        let graduate = try raisingEntry(s)
        XCTAssertTrue(s.evolutionCards(for: 446, individual: graduate).contains { $0.isNextStep && $0.context != nil })
        XCTAssertFalse(s.evolutionCards(for: 446, individual: graduate).contains { $0.offersSkip })
        XCTAssertFalse(s.stageText.hasSuffix(s.l.finalForm), "a graduate that can still evolve is not a final form")
    }

    func testAReleasedGraduateTakesItsProgressWithIt() {
        var state = CompanionState()
        state.dex = [DexEntry(id: "kept", baseID: 446, finalID: 446, chainOrder: [446], rarity: .common, caughtAt: nil),
                     DexEntry(id: "gone", baseID: 446, finalID: 446, chainOrder: [446], rarity: .common, caughtAt: nil,
                              releasedAt: Date())]
        state.graduateEvolution = ["kept": EvolutionProgress(), "gone": EvolutionProgress(), "nobody": EvolutionProgress()]
        state.dropOrphanedGraduateEvolution()
        XCTAssertEqual(Set(state.graduateEvolution.keys), ["kept"])
    }
}
