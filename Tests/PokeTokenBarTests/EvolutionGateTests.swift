import XCTest
@testable import PokeTokenBar

private func node(_ id: Int, _ children: [EvoNode] = [], item: String? = nil) -> EvoNode {
    EvoNode(speciesID: id, children: children,
            methods: item.map { [EvoMethod(trigger: "use-item", item: $0)] } ?? [EvoMethod(trigger: "level-up")])
}

private struct GateProvider: PokeProviding {
    let tree: EvoNode
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: tree.speciesID, tree: tree, rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private final class GateClock: @unchecked Sendable {
    var now = Date()
    func set(hour: Int) { now = Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: Date())! }
}

private func context(_ edit: (inout EvolutionContext) -> Void = { _ in }) -> EvolutionContext {
    var context = EvolutionContext()
    edit(&context)
    return context
}

final class EvolutionGateRuleTests: XCTestCase {
    private func gate(_ species: Int, closed: EvolutionContext, opens: EvolutionContext,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        let rule = try XCTUnwrap(EvolutionRules.rule(for: species), "no rule for \(species)", file: file, line: line)
        XCTAssertFalse(rule.isOpen(in: closed), "\(species) should be closed", file: file, line: line)
        XCTAssertTrue(rule.isOpen(in: opens), "\(species) should open", file: file, line: line)
    }

    func testFriendshipStepsOpenAtTheirPetCount() throws {
        for (species, pets) in [(143, 30), (25, 40), (542, 40), (428, 30)] {
            try gate(species, closed: context { $0.progress.pets = pets - 1 }, opens: context { $0.progress.pets = pets })
        }
    }

    func testFriendshipWithATimeOfDayNeedsBothAndEspeonUmbreonSplitByTime() throws {
        try gate(315, closed: context { $0.progress.pets = 30; $0.period = .night },
                 opens: context { $0.progress.pets = 30; $0.period = .day })
        try gate(315, closed: context { $0.progress.pets = 29; $0.period = .day },
                 opens: context { $0.progress.pets = 30; $0.period = .day })
        try gate(197, closed: context { $0.progress.pets = 30; $0.period = .day },
                 opens: context { $0.progress.pets = 30; $0.period = .night })
    }

    func testKnownMoveStepsUseTheLearnsetAndFallBackOnLevelWhenTheMoveIsNotListed() throws {
        try gate(122, closed: context { $0.learnableMoves = ["mimic"]; $0.level = 80 },
                 opens: context { $0.learnableMoves = ["mimic"]; $0.knownMoves = ["mimic"] })
        try gate(122, closed: context { $0.level = 24 }, opens: context { $0.level = 25 })
        try gate(700, closed: context { $0.progress.pets = 30; $0.learnableMoves = ["charm"] },
                 opens: context { $0.progress.pets = 30; $0.learnableMoves = ["charm"]; $0.knownMoves = ["charm"] })
        try gate(700, closed: context { $0.knownMoves = ["charm"] }, opens: context { $0.progress.pets = 30; $0.knownMoves = ["charm"] })
    }

    func testPartyStepsNeedTheRightFriend() throws {
        try gate(226, closed: context { $0.friendLines = [129]; $0.friendCount = 1 },
                 opens: context { $0.friendLines = [223, 224]; $0.friendCount = 1 })
        try gate(675, closed: context { $0.friendTypes = ["fire"]; $0.friendCount = 1 },
                 opens: context { $0.friendTypes = ["fire", "dark"]; $0.friendCount = 1 })
        try gate(964, closed: context(), opens: context { $0.friendCount = 1 })
    }

    func testGestureAndItemStepsNeedTheirOwnEvent() throws {
        try gate(687, closed: context(), opens: context { $0.progress.flipped = true })
        try gate(869, closed: context { $0.progress.spun = true }, opens: context { $0.progress.spun = true; $0.heldItem = .strawberrySweet })
        try gate(113, closed: context { $0.heldItem = .ovalStone; $0.period = .night },
                 opens: context { $0.heldItem = .ovalStone; $0.period = .day })
        try gate(461, closed: context { $0.heldItem = .razorFang; $0.period = .night },
                 opens: context { $0.heldItem = .razorClaw; $0.period = .night })
        try gate(892, closed: context(), opens: context { $0.progress.tower = "darkness" })
        try gate(892, closed: context(), opens: context { $0.bag = [.scrollOfWaters: 1] })
    }

    func testBattleAndRainStepsOpenByTheirTallyOrByStayingLongEnough() throws {
        try gate(865, closed: context { $0.progress.won = 2 }, opens: context { $0.progress.won = 3 })
        try gate(865, closed: context { $0.stageXP = 199; $0.stageThreshold = 100 },
                 opens: context { $0.stageXP = 200; $0.stageThreshold = 100 })
        try gate(867, closed: context { $0.progress.won = 9 }, opens: context { $0.progress.lost = 1 })
        try gate(706, closed: context(), opens: context { $0.progress.rained = true })
        try gate(979, closed: context { $0.progress.played = 19 }, opens: context { $0.progress.played = 20 })
    }

    func testSpendingAndCandyStepsCountFromTheStartOfTheForm() throws {
        try gate(1000, closed: context { $0.spentTokens = 1_500_000_000; $0.progress.spentBaseline = 1_000_000_000 },
                 opens: context { $0.spentTokens = 2_000_000_000; $0.progress.spentBaseline = 1_000_000_000 })
        try gate(809, closed: context { $0.progress.candies = 4 }, opens: context { $0.progress.candies = 5 })
    }

    func testStepsWithoutAGateAreAlwaysOpen() {
        for species in [106, 266, 292, 849, 925] {
            XCTAssertTrue(EvolutionRules.rule(for: species)?.isOpen(in: context()) == true, "\(species)")
        }
        XCTAssertNotNil(EvolutionRules.openPath(into: 3, in: context()), "a species without a rule is open")
    }

    func testBattleLedgerCountsEachBattleOnce() {
        var progress = EvolutionProgress()
        progress.record(battle: "a", result: .won)
        progress.record(battle: "a", result: .won)
        progress.record(battle: "b", result: .lost)
        XCTAssertEqual([progress.won, progress.lost, progress.played], [1, 1, 2])
        let next = progress.nextForm(spentBaseline: 7)
        XCTAssertEqual([next.won, next.played, next.spentBaseline], [0, 0, 7])
        XCTAssertEqual(next.seenBattles, ["a", "b"])
    }

    func testProgressDecodesFromAnOlderSaveWithoutTheField() throws {
        let decoded = try JSONDecoder().decode(EvolutionProgress.self, from: Data(#"{"pets":"x","won":2}"#.utf8))
        XCTAssertEqual(decoded.won, 2)
        XCTAssertEqual(decoded.pets, 0)
        let mon = try JSONDecoder().decode(MonState.self, from: Data(
            #"{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":1}"#.utf8))
        XCTAssertEqual(mon.evolution, EvolutionProgress())
    }
}

@MainActor
final class EvolutionGateStoreTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func store(tree: EvoNode, clock: GateClock = GateClock(), state: CompanionState? = nil,
                       inventory: [ItemKind: Int] = [:], seed: UInt64 = 1) throws -> CompanionStore {
        var state = state ?? CompanionState()
        state.installBaselineSet = true
        for (kind, count) in inventory { state.inventory[kind.rawValue] = count }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evo-gate-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "evo-gate-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: GateProvider(tree: tree), clock: { clock.now }, fileURL: file,
                              rng: SeededRNG(seed: seed), dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func loadLine(_ s: CompanionStore) async {
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        for _ in 0..<100 where s.currentLine == nil { await Task.yield() }
    }

    private func savedMon(base: Int, plan: [Int], nature: PokemonNature? = nil, ivs: (Int, Int)? = nil) -> CompanionState {
        var profile = PokemonProfile.generate(seed: 7)
        if let ivs { profile.ivs.attack = ivs.0; profile.ivs.defense = ivs.1 }
        var state = CompanionState()
        state.active = MonState(baseID: base, pathIDs: [base], plannedPathIDs: plan, stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: plan.count, nature: nature, profile: profile)
        return state
    }

    func testFriendshipStepWaitsForPetsThenEvolvesAndKeepsTheExtraXP() async throws {
        let clock = GateClock()
        let s = try store(tree: node(446, [node(143)]), clock: clock)
        await s.hatch(baseID: 446)
        s.applyUsage(s.tokensToNext + 5)
        XCTAssertEqual(s.currentSpeciesID, 446, "no pets yet")
        for _ in 0..<29 { clock.now.addTimeInterval(11); s.recordPet() }
        XCTAssertEqual(s.currentSpeciesID, 446)
        XCTAssertEqual(s.state.active?.evolution.pets, 29)
        clock.now.addTimeInterval(11)
        s.recordPet()
        XCTAssertEqual(s.currentSpeciesID, 143)
        XCTAssertEqual(s.state.active?.usedAtStage, 5, "the XP gathered while waiting carries over")
        XCTAssertEqual(s.state.active?.evolution.pets, 0, "the next form starts clean")
    }

    func testPettingFasterThanTheCooldownCountsOnce() async throws {
        let clock = GateClock()
        let s = try store(tree: node(446, [node(143)]), clock: clock)
        await s.hatch(baseID: 446)
        s.recordPet()
        clock.now.addTimeInterval(3)
        s.recordPet()
        XCTAssertEqual(s.state.active?.evolution.pets, 1)
    }

    func testMantyneNeedsARemoraidFriendAndEvolvesWhenOneJoins() async throws {
        let remoraid = DexEntry(baseID: 223, finalID: 224, chainOrder: [223, 224], rarity: .common, caughtAt: Date())
        let lonely = try store(tree: node(458, [node(226)]))
        await lonely.hatch(baseID: 458)
        lonely.applyUsage(lonely.tokensToNext)
        XCTAssertEqual(lonely.currentSpeciesID, 458)

        var withDex = CompanionState()
        withDex.dex = [remoraid]
        let s = try store(tree: node(458, [node(226)]), state: withDex)
        await s.hatch(baseID: 458)
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 458, "owning one is not enough — it has to be a friend")
        XCTAssertTrue(s.addFriend(entryID: remoraid.id))
        XCTAssertEqual(s.currentSpeciesID, 226)
        XCTAssertEqual(s.state.active?.pathIDs, [458, 226])
    }

    func testHeldItemAndTimeOfDayBothGateChanseyAndTheItemIsUsedUp() async throws {
        let clock = GateClock()
        clock.set(hour: 23)
        let s = try store(tree: node(440, [node(113)]), clock: clock, inventory: [.ovalStone: 1])
        await s.hatch(baseID: 440)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        s.applyUsage(s.tokensToNext)
        XCTAssertTrue(s.equip(.ovalStone, to: id))
        XCTAssertEqual(s.currentSpeciesID, 440, "night")
        clock.set(hour: 12)
        s.reevaluateEvolution()
        XCTAssertEqual(s.currentSpeciesID, 113)
        XCTAssertNil(s.heldItem(of: id), "the Oval Stone is consumed")
        XCTAssertEqual(s.itemCount(.ovalStone), 0)
    }

    func testTimeOfDayAloneOpensTheGateOnTheNextTickWithoutNewUsage() async throws {
        let clock = GateClock()
        clock.set(hour: 23)
        let s = try store(tree: node(406, [node(315)]), clock: clock)
        await s.hatch(baseID: 406)
        for _ in 0..<30 { clock.now.addTimeInterval(11); s.recordPet() }
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 406, "Roselia only by day")
        clock.set(hour: 12)
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.currentSpeciesID, 315)
    }

    func testTyrogueTakesTheBranchTheStatsPointAtWhateverTheOldPlanSaid() async throws {
        let tyrogue = node(236, [node(106), node(107), node(237)])
        let cases: [(PokemonNature, (Int, Int), Int)] = [
            (.hardy, (31, 0), 106), (.hardy, (0, 31), 107), (.hardy, (9, 9), 237), (.lonely, (0, 0), 106),
        ]
        for (nature, ivs, expected) in cases {
            let s = try store(tree: tyrogue, state: savedMon(base: 236, plan: [236, 237], nature: nature, ivs: ivs))
            await loadLine(s)
            s.applyUsage(s.tokensToNext)
            XCTAssertEqual(s.currentSpeciesID, expected, "\(nature) \(ivs)")
        }
    }

    func testOldEeveeSaveKeepsItsSylveonPlanAndOnlyGainsTheGate() async throws {
        let eevee = node(133, [node(134), node(196), node(197), node(700)])
        let s = try store(tree: eevee, state: savedMon(base: 133, plan: [133, 700]))
        await loadLine(s)
        XCTAssertEqual(s.state.active?.plannedPathIDs, [133, 700])
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 133, "Sylveon now asks for friendship and a Fairy move")
        XCTAssertEqual(s.state.active?.plannedPathIDs, [133, 700], "the plan is not rewritten")
        let pending = try XCTUnwrap(s.pendingEvolutionGate())
        XCTAssertEqual(pending.rule.species, 700)
    }

    func testOldInkaySaveKeepsItsMalamarPlanUntilTheFlip() async throws {
        let s = try store(tree: node(686, [node(687)]), state: savedMon(base: 686, plan: [686, 687]))
        await loadLine(s)
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 686)
        XCTAssertEqual(s.state.active?.plannedPathIDs, [686, 687])
        s.recordFlip()
        XCTAssertEqual(s.currentSpeciesID, 687)
        XCTAssertFalse(s.state.active?.evolution.flipped ?? true, "the next form starts clean")
    }

    func testItemOnlyFormIsReachedByItsItemNotByGrowth() async throws {
        let clock = GateClock()
        clock.set(hour: 12)
        let tree = node(217, [node(901, item: "peat-block")])
        let s = try store(tree: tree, clock: clock, inventory: [.peatBlock: 1])
        await s.hatch(baseID: 217)
        XCTAssertEqual(s.state.active?.plannedPathIDs, [217], "growth alone never plans Ursaluna")
        XCTAssertEqual(s.useEvolutionStone(.peatBlock), .notReady, "a Peat Block works only at night")
        XCTAssertEqual(s.itemCount(.peatBlock), 1)
        clock.set(hour: 23)
        XCTAssertEqual(s.useEvolutionStone(.peatBlock), .evolved)
        XCTAssertEqual(s.currentSpeciesID, 901)
        XCTAssertEqual(s.itemCount(.peatBlock), 0)
    }

    func testFormWithAnItemOnlyChildGraduatesAsItselfWhenNoItemWasUsed() async throws {
        let s = try store(tree: node(217, [node(901, item: "peat-block")]))
        await s.hatch(baseID: 217)
        s.applyUsage(s.tokensToNext)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.last?.finalID, 217)
    }

    func testSpeciesWithoutARuleEvolveByGrowthAsBefore() async throws {
        let s = try store(tree: node(1, [node(2, [node(3)])]))
        await s.hatch(baseID: 1)
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 2)
    }
}
