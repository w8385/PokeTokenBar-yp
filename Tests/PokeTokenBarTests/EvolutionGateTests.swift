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
    func set(_ period: DayPeriod) {
        now = Calendar.current.date(bySettingHour: 12, minute: period == .day ? 5 : 15, second: 0, of: Date())!
    }
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
        try gate(1000, closed: context { $0.spentTokens = 210_000_000; $0.progress.spentBaseline = 200_000_000 },
                 opens: context { $0.spentTokens = 220_000_000; $0.progress.spentBaseline = 200_000_000 })
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
        XCTAssertEqual(decoded.graduateXP, 0)
        let mon = try JSONDecoder().decode(MonState.self, from: Data(
            #"{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":1}"#.utf8))
        XCTAssertEqual(mon.evolution, EvolutionProgress())
        XCTAssertNil(mon.evolution.stuckNotified)
    }

    func testStuckMarkerSurvivesASaveAndResetsWithTheNextForm() throws {
        var progress = EvolutionProgress()
        progress.stuckNotified = "358"
        progress.graduateXP = 9
        let back = try JSONDecoder().decode(EvolutionProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(back.stuckNotified, "358")
        XCTAssertEqual(back.graduateXP, 9)
        XCTAssertNil(progress.nextForm(spentBaseline: 0).stuckNotified)
        XCTAssertEqual(progress.nextForm(spentBaseline: 0).graduateXP, 0)
    }

    func testBlockSplitsTheClockFromConditions() throws {
        let chimecho = try XCTUnwrap(EvolutionRules.rule(for: 358))
        XCTAssertEqual(chimecho.block(in: context { $0.progress.pets = 40; $0.period = .day }), .clock(.night))
        XCTAssertEqual(chimecho.block(in: context { $0.progress.pets = 0; $0.period = .day }), .conditions([.pets(40)]))
        XCTAssertEqual(chimecho.block(in: context { $0.progress.pets = 0; $0.period = .night }), .conditions([.pets(40)]))
        XCTAssertEqual(chimecho.block(in: context { $0.progress.pets = 40; $0.period = .night }), .open)
    }

    func testUnmetRequirementsNameThePathNearestToOpen() throws {
        let chansey = try XCTUnwrap(EvolutionRules.rule(for: 113))
        let none = context { $0.period = .night }
        XCTAssertEqual(chansey.unmetRequirements(in: none), [.holds(.ovalStone), .time(.day)])
        let held = context { $0.period = .night; $0.heldItem = .ovalStone }
        XCTAssertEqual(chansey.unmetRequirements(in: held), [.time(.day)])
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
        clock.set(.night)
        let s = try store(tree: node(440, [node(113)]), clock: clock, inventory: [.ovalStone: 1])
        await s.hatch(baseID: 440)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        s.applyUsage(s.tokensToNext)
        XCTAssertTrue(s.equip(.ovalStone, to: id))
        XCTAssertEqual(s.currentSpeciesID, 440, "night")
        clock.set(.day)
        s.reevaluateEvolution()
        XCTAssertEqual(s.currentSpeciesID, 113)
        XCTAssertNil(s.heldItem(of: id), "the Oval Stone is consumed")
        XCTAssertEqual(s.itemCount(.ovalStone), 0)
    }

    func testTimeOfDayAloneOpensTheGateOnTheNextTickWithoutNewUsage() async throws {
        let clock = GateClock()
        let s = try store(tree: node(406, [node(315)]), clock: clock)
        await s.hatch(baseID: 406)
        for _ in 0..<30 { clock.now.addTimeInterval(11); s.recordPet() }
        clock.set(.night)
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 406, "Roselia only by day")
        clock.set(.day)
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
        clock.set(.day)
        let tree = node(217, [node(901, item: "peat-block")])
        let s = try store(tree: tree, clock: clock, inventory: [.peatBlock: 1])
        await s.hatch(baseID: 217)
        XCTAssertEqual(s.state.active?.plannedPathIDs, [217], "growth alone never plans Ursaluna")
        XCTAssertEqual(s.useEvolutionStone(.peatBlock), .notReady, "a Peat Block works only at night")
        XCTAssertEqual(s.itemCount(.peatBlock), 1)
        clock.set(.night)
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

    private func battle(_ at: Date, win: Bool = true) -> BattleInfo.RecentBattle {
        BattleInfo.RecentBattle(opponentName: "o", result: win ? "win" : "loss",
                                at: ISO8601DateFormatter().string(from: at))
    }

    func testBattlesBeforeTheFirstReadAreNotCreditedAndLaterOnesCountOnce() async throws {
        let clock = GateClock()
        let s = try store(tree: node(83, [node(865)]), clock: clock, state: savedMon(base: 83, plan: [83, 865]))
        await loadLine(s)
        s.applyUsage(s.tokensToNext)
        let old = (0..<5).map { battle(clock.now.addingTimeInterval(-Double(3600 + $0 * 60))) }
        s.syncBattles(old)
        XCTAssertEqual(s.state.active?.evolution.played, 0)
        XCTAssertEqual(s.currentSpeciesID, 83)
        let fresh = (1...3).map { battle(clock.now.addingTimeInterval(Double($0 * 60))) }
        s.syncBattles(Array(fresh.prefix(2)) + old)
        XCTAssertEqual(s.state.active?.evolution.won, 2)
        XCTAssertEqual(s.currentSpeciesID, 83)
        s.syncBattles(Array(fresh.prefix(2)))
        XCTAssertEqual(s.state.active?.evolution.won, 2, "re-reading the same battles adds nothing")
        s.syncBattles(fresh)
        XCTAssertEqual(s.currentSpeciesID, 865)
        XCTAssertEqual(s.state.active?.evolution.played, 0, "the next form starts clean")
    }

    func testLossesCountOnlyTowardLossGates() async throws {
        let clock = GateClock()
        let s = try store(tree: node(540, [node(867)]), clock: clock, state: savedMon(base: 540, plan: [540, 867]))
        await loadLine(s)
        s.syncBattles([])
        s.applyUsage(s.tokensToNext)
        s.syncBattles([battle(clock.now.addingTimeInterval(60))])
        XCTAssertEqual(s.currentSpeciesID, 540, "867 asks for a loss")
        s.syncBattles([battle(clock.now.addingTimeInterval(120), win: false)])
        XCTAssertEqual(s.currentSpeciesID, 867)
    }

    func testBlazingBurnIsATokenRainAndSlowerBurnIsNot() async throws {
        let s = try store(tree: node(705, [node(706)]))
        await s.hatch(baseID: 705)
        s.applyUsage(s.tokensToNext)
        for tier in [BurnTier.idle, .normal, .fast] {
            s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: tier,
                     limitWarning: false, hasUsageData: true)
        }
        XCTAssertEqual(s.currentSpeciesID, 705)
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .blazing,
                 limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.currentSpeciesID, 706)
    }

    func testEveryClickIsAPetEvenWithNoTimePassing() async throws {
        let s = try store(tree: node(446, [node(143)]))
        await s.hatch(baseID: 446)
        for _ in 0..<4 { s.growByClick() }
        XCTAssertEqual(s.state.active?.evolution.pets, 4)
    }

    func testEvolvingNincadaAlsoRegistersAShedinjaThatIsNeverPlanned() async throws {
        for seed in 1...6 as ClosedRange<UInt64> {
            let s = try store(tree: node(290, [node(291), node(292)]), seed: seed)
            await s.hatch(baseID: 290)
            XCTAssertEqual(s.state.active?.plannedPathIDs, [290, 291], "seed \(seed)")
            s.applyUsage(s.tokensToNext)
            XCTAssertEqual(s.currentSpeciesID, 291)
            let shedinja = try XCTUnwrap(s.state.dex.first { $0.finalID == 292 })
            XCTAssertEqual(shedinja.chainOrder, [290, 292])
            XCTAssertNotNil(shedinja.profile)
            XCTAssertTrue(s.state.collectedFinals.contains("290:292"))
        }
    }

    func testGesturesAreOfferedOnlyWhileTheWaitingStepAsksForThem() async throws {
        let s = try store(tree: node(686, [node(687)]), state: savedMon(base: 686, plan: [686, 687]))
        await loadLine(s)
        XCTAssertEqual(s.evolutionGestures, [.flip])
        s.recordFlip()
        XCTAssertEqual(s.evolutionGestures, [])
        let plain = try store(tree: node(1, [node(2)]))
        await plain.hatch(baseID: 1)
        XCTAssertEqual(plain.evolutionGestures, [])
    }

    func testSpeciesWithoutARuleEvolveByGrowthAsBefore() async throws {
        let s = try store(tree: node(1, [node(2, [node(3)])]))
        await s.hatch(baseID: 1)
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 2)
    }

    // MARK: Day/night on the wall clock, and the stuck-evolution notification

    private func at(minute: Int) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: minute, second: 0, of: Date())!
    }

    func testNightOnlyEvolutionReadyByDayEvolvesAfterTheClockPassesTenMinutes() async throws {
        let clock = GateClock()
        clock.now = at(minute: 5)
        let s = try store(tree: node(433, [node(358)]), clock: clock)
        await s.hatch(baseID: 433)
        for _ in 0..<40 { clock.now.addTimeInterval(1); s.recordPet(); clock.now.addTimeInterval(10) }
        clock.now = at(minute: 5)
        s.applyUsage(s.tokensToNext)
        s.checkEvolutionGate()
        XCTAssertEqual(s.currentSpeciesID, 433, "Chimecho only at night")
        clock.now = at(minute: 10).addingTimeInterval(1)
        s.checkEvolutionGate()
        XCTAssertEqual(s.currentSpeciesID, 358)
    }

    private func stuckChimecho(_ clock: GateClock) async throws -> CompanionStore {
        let s = try store(tree: node(433, [node(358)]), clock: clock)
        await s.hatch(baseID: 433)
        for _ in 0..<40 { clock.now.addTimeInterval(11); s.recordPet() }
        clock.now = at(minute: 5)
        return s
    }

    func testStuckEvolutionNotifiesOnceAndNamesTheWait() async throws {
        let clock = GateClock()
        let s = try await stuckChimecho(clock)
        let before = s.latestEvent?.seq ?? 0
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.latestEvent?.seq, before + 1)
        XCTAssertTrue(s.latestEvent?.text.contains("5") == true, "five minutes to night: \(s.latestEvent?.text ?? "")")
        XCTAssertNotNil(s.state.active?.evolution.stuckNotified)
        s.applyUsage(0)
        clock.now = at(minute: 8)
        s.checkEvolutionGate()
        XCTAssertEqual(s.latestEvent?.seq, before + 1, "same reason, no second notification")
    }

    func testStuckNotificationFollowsTheReasonNotThePeriod() async throws {
        let clock = GateClock()
        clock.set(.night)
        let s = try store(tree: node(440, [node(113)]), clock: clock, inventory: [.ovalStone: 1])
        await s.hatch(baseID: 440)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        let before = s.latestEvent?.seq ?? 0
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.latestEvent?.seq, before + 1, "needs the stone and day")
        clock.now = clock.now.addingTimeInterval(DayPeriod.length)
        s.checkEvolutionGate()
        XCTAssertEqual(s.currentSpeciesID, 440)
        XCTAssertEqual(s.latestEvent?.seq, before + 1, "the period flipped but the stone is still missing")
        clock.now = clock.now.addingTimeInterval(DayPeriod.length)
        XCTAssertTrue(s.equip(.ovalStone, to: id))
        XCTAssertEqual(s.currentSpeciesID, 440)
        XCTAssertEqual(s.latestEvent?.seq, before + 2, "now only the day is missing")
    }

    func testNoStuckNotificationWhenTheFormCanEvolveNow() async throws {
        let clock = GateClock()
        clock.set(.day)
        let s = try store(tree: node(440, [node(113)]), clock: clock, inventory: [.ovalStone: 1])
        await s.hatch(baseID: 440)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        XCTAssertTrue(s.equip(.ovalStone, to: id))
        let before = s.latestEvent?.seq ?? 0
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 113)
        XCTAssertEqual(s.latestEvent?.seq, before + 1, "only the evolution itself")
        XCTAssertNil(s.state.active?.evolution.stuckNotified)
    }
}
