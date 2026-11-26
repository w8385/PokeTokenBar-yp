import XCTest
@testable import PokeTokenBar

private func step(_ id: Int, _ children: [EvoNode] = [], tradeHolding held: String? = nil,
                  alsoUsing item: String? = nil) -> EvoNode {
    var methods = [EvoMethod(trigger: "trade", item: nil, heldItem: held)]
    if let item { methods.append(EvoMethod(trigger: "use-item", item: item)) }
    return EvoNode(speciesID: id, children: children, methods: methods)
}

private func level(_ id: Int, _ children: [EvoNode] = []) -> EvoNode {
    EvoNode(speciesID: id, children: children, methods: [EvoMethod(trigger: "level-up", item: nil)])
}

/// The shape PokéAPI serves since it added the Legends: Arceus way into each trade step.
private let porygon = EvoNode(speciesID: 137, children: [
    step(233, [step(474, tradeHolding: "dubious-disc", alsoUsing: "dubious-disc")],
         tradeHolding: "up-grade", alsoUsing: "up-grade"),
])
private let machop = EvoNode(speciesID: 66, children: [level(67, [step(68, alsoUsing: "linking-cord")])])
private let gastly = EvoNode(speciesID: 92, children: [level(93, [step(94)])])
private let onix = EvoNode(speciesID: 95, children: [step(208, tradeHolding: "metal-coat", alsoUsing: "metal-coat")])

private struct LiveShapeProvider: PokeProviding {
    static let trees: [Int: EvoNode] = [137: porygon, 66: machop, 92: gastly, 95: onix]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        guard let tree = Self.trees[baseSpeciesID] else { throw URLError(.badServerResponse) }
        return EvoLine(baseID: baseSpeciesID, tree: tree, rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class TradeOnlyGrowthTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func makeStore(_ configure: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .en
        configure(&state)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-only-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "trade-only-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: LiveShapeProvider(), fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func growToEnd(_ store: CompanionStore) {
        for _ in 0..<6 where store.state.active != nil { store.applyUsage(store.tokensToNext) }
    }

    private func waitForLine(_ store: CompanionStore) async throws {
        try await waitUntil("the line to load") {
            if store.currentLine != nil { return true }
            store.update(todayTokensByProvider: [:], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                         limitWarning: false, hasUsageData: false)
            return false
        }
    }

    private func graduate(_ id: String, base: Int, chain: [Int]) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 9, instanceID: id)
        profile.level = 100
        return DexEntry(id: id, baseID: base, finalID: chain.last!, chainOrder: chain, rarity: .common,
                        caughtAt: Date(timeIntervalSince1970: 100), nature: .calm, profile: profile)
    }

    // MARK: The raised line

    func testAPorygonHatchedFromTheLiveLineGraduatesAsPorygon() async throws {
        let store = try makeStore()
        await store.hatch(baseID: 137)
        XCTAssertEqual(store.state.active?.plannedPathIDs, [137])
        growToEnd(store)
        XCTAssertEqual(store.state.dex.last?.finalID, 137)
        XCTAssertEqual(store.state.dex.last?.chainOrder, [137])
    }

    func testAMachopHatchedFromTheLiveLineGraduatesAsMachoke() async throws {
        let store = try makeStore()
        await store.hatch(baseID: 66)
        XCTAssertEqual(store.state.active?.plannedPathIDs, [66, 67])
        growToEnd(store)
        XCTAssertEqual(store.state.dex.last?.finalID, 67)
    }

    func testAGatedLineThatPlannedThroughATradeStepDropsItWhenItsLineLoads() async throws {
        let store = try makeStore { state in
            state.active = MonState(baseID: 137, pathIDs: [137], plannedPathIDs: [137, 233, 474], stageIndex: 0,
                                    usedAtStage: 0, rarity: .common, totalForms: 3,
                                    profile: PokemonProfile.generate(seed: 5, instanceID: "p"), tradeGated: true)
        }
        try await waitForLine(store)
        XCTAssertEqual(store.state.active?.plannedPathIDs, [137])
        growToEnd(store)
        XCTAssertEqual(store.state.dex.last?.finalID, 137)
    }

    func testEveryTradeOnlyRuleIsLeftOutOfGrowthWhateverElsePokeAPIListsForIt() throws {
        let tradeOnly = EvolutionRules.table.filter(\.isTradeOnly)
        XCTAssertEqual(tradeOnly.count, 24, "a new trade-only rule must be looked at")
        for rule in tradeOnly {
            let parent = try XCTUnwrap(rule.from, "#\(rule.species)")
            let tree = EvoNode(speciesID: parent, children: [step(rule.species, alsoUsing: "linking-cord")])
            XCTAssertEqual(tree.prunedTradeOnly().children.map(\.speciesID), [], "#\(rule.species)")
        }
    }

    // MARK: Graduates and the Box

    func testARaisedGraduateNeverGrowsThroughATradeStep() async throws {
        for (base, chain) in [(137, [137, 233]), (92, [92, 93])] {
            let id = "grad-\(base)"
            let store = try makeStore { $0.dex = [self.graduate(id, base: base, chain: chain)] }
            XCTAssertTrue(store.raise(entryID: id))
            await store.checkRaisedGraduateEvolution()
            XCTAssertEqual(store.state.dex.first { $0.id == id }?.finalID, chain.last, "#\(base)")
        }
    }

    func testAPorygon2HoldingAnExpShareInTheBoxGraduatesAsPorygon2() async throws {
        try await assertStoredLineGraduates(base: 137, at: [137, 233], planned: [137, 233, 474])
    }

    func testAnOnixPlannedThroughSteelixHoldingAnExpShareInTheBoxGraduatesAsOnix() async throws {
        try await assertStoredLineGraduates(base: 95, at: [95], planned: [95, 208])
    }

    private func assertStoredLineGraduates(base: Int, at reached: [Int], planned: [Int]) async throws {
        let id = "stored-\(base)"
        var profile = PokemonProfile.generate(seed: 7, instanceID: id)
        profile.level = 60
        var mon = MonState(baseID: base, pathIDs: reached, plannedPathIDs: planned, stageIndex: reached.count - 1,
                           usedAtStage: 0, rarity: .common, totalForms: planned.count, nature: .calm, profile: profile,
                           tradeGated: true)
        mon.usedAtStage = mon.phaseThreshold
        let store = try makeStore { state in
            state.storedLines[id] = StoredLine(mon: mon, spentAtStore: 0)
            state.dex = [DexEntry(id: id, baseID: base, finalID: reached.last!, chainOrder: reached, rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 50), profile: profile,
                                  releasedAt: Date(timeIntervalSince1970: 50))]
            state.expShareHolders = [id]
        }
        await store.checkExpShareEvolution()
        XCTAssertNil(store.state.storedLines[id])
        let record = try XCTUnwrap(store.state.dex.first { $0.id == id && !$0.isReleased })
        XCTAssertEqual(record.finalID, reached.last)
        XCTAssertEqual(record.chainOrder, reached)
    }

    // MARK: Repairing a save that already grew through one

    private let afterTheGate = CompanionState.tradeGateShippedAt.addingTimeInterval(86_400)

    private func oldSave(_ dex: [DexEntry], inventory: [ItemKind: Int] = [:],
                         _ configure: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        try makeStore { state in
            state.unearnedTradeStepsReverted = false
            state.dex = dex
            state.collectedFinals = Set(dex.map { "\($0.baseID):\($0.finalID)" })
            for (kind, count) in inventory { state.inventory[kind.rawValue] = count }
            configure(&state)
        }
    }

    private func graduate(_ id: String, _ chain: [Int], caughtAt: Date) -> DexEntry {
        var entry = graduate(id, base: chain[0], chain: chain)
        entry.caughtAt = caughtAt
        entry.profile?.abilityName = "adaptability"
        return entry
    }

    func testAPorygonZThatNeverHadADubiousDiscGoesBackToPorygon2Once() throws {
        let store = try oldSave([graduate("z", [137, 233, 474], caughtAt: afterTheGate)], inventory: [.upGrade: 0])
        let entry = try XCTUnwrap(store.state.dex.first)
        XCTAssertEqual(entry.finalID, 233)
        XCTAssertEqual(entry.chainOrder, [137, 233])
        XCTAssertNil(entry.profile?.abilityName)
        XCTAssertEqual(store.state.collectedFinals, ["137:233"])
        XCTAssertTrue(store.state.unearnedTradeStepsReverted)
    }

    func testAPorygonZWhoseSaveOwnedADubiousDiscStays() throws {
        let store = try oldSave([graduate("z", [137, 233, 474], caughtAt: afterTheGate)],
                                inventory: [.upGrade: 0, .dubiousDisc: 0])
        XCTAssertEqual(store.state.dex.first?.finalID, 474)
    }

    func testAPorygonThatNeverHadAnUpGradeGoesBackToPorygon() throws {
        let store = try oldSave([graduate("z", [137, 233, 474], caughtAt: afterTheGate)])
        XCTAssertEqual(store.state.dex.first?.chainOrder, [137])
    }

    func testAGraduateFromBeforeTheGateStays() throws {
        let before = CompanionState.tradeGateShippedAt.addingTimeInterval(-3_600)
        let store = try oldSave([graduate("k", [116, 117, 230], caughtAt: before)])
        XCTAssertEqual(store.state.dex.first?.finalID, 230)
    }

    func testAPlainTradeStepAndATradedInPokemonStay() throws {
        var received = graduate("t", [137, 233, 474], caughtAt: afterTheGate)
        received.originalTrainer = "trainer"
        let store = try oldSave([graduate("m", [66, 67, 68], caughtAt: afterTheGate), received])
        XCTAssertEqual(store.state.dex.map(\.finalID), [68, 474])
    }

    func testAPorygonZStillOwnedAnotherWayStaysCollected() throws {
        var received = graduate("t", [137, 233, 474], caughtAt: afterTheGate)
        received.originalTrainer = "trainer"
        let store = try oldSave([graduate("z", [137, 233, 474], caughtAt: afterTheGate), received])
        XCTAssertEqual(store.state.dex.map(\.finalID), [137, 474])
        XCTAssertEqual(store.state.collectedFinals, ["137:137", "137:474"])
    }

    func testAReleasedPorygonZStays() throws {
        var released = graduate("z", [137, 233, 474], caughtAt: afterTheGate)
        released.releasedAt = afterTheGate
        let store = try oldSave([released])
        XCTAssertEqual(store.state.dex.first?.finalID, 474)
    }

    private func porygonZ(gated: Bool?) -> MonState {
        MonState(baseID: 137, pathIDs: [137, 233, 474], stageIndex: 2, usedAtStage: 10, rarity: .common,
                 totalForms: 3, profile: PokemonProfile.generate(seed: 2, instanceID: "a"), tradeGated: gated)
    }

    func testARaisedGatedPorygonZGoesBackButAnUngatedOneStays() throws {
        let store = try oldSave([], inventory: [.upGrade: 0]) { state in
            state.active = self.porygonZ(gated: true)
            state.storedLines["s"] = StoredLine(mon: self.porygonZ(gated: nil), spentAtStore: 0)
        }
        let active = try XCTUnwrap(store.state.active)
        XCTAssertEqual(active.pathIDs, [137, 233])
        XCTAssertEqual(active.plannedPathIDs, [137, 233])
        XCTAssertEqual(active.currentID, 233)
        XCTAssertEqual(store.state.storedLines["s"]?.mon.currentID, 474)
    }

    func testAGatedPorygonZWaitingInTheBoxGoesBack() throws {
        let store = try oldSave([], inventory: [.upGrade: 0]) { state in
            state.storedLines["s"] = StoredLine(mon: self.porygonZ(gated: true), spentAtStore: 0)
        }
        let mon = try XCTUnwrap(store.state.storedLines["s"]?.mon)
        XCTAssertEqual(mon.reachedIDs, [137, 233])
        XCTAssertEqual(mon.totalForms, 2)
    }
}
