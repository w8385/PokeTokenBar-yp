import XCTest
@testable import PokeTokenBar

private func node(_ id: Int, _ children: [EvoNode] = [], item: String? = nil) -> EvoNode {
    EvoNode(speciesID: id, children: children,
            methods: item.map { [EvoMethod(trigger: "use-item", item: $0)] } ?? [EvoMethod(trigger: "level-up")])
}

private struct SpendProvider: PokeProviding {
    let tree: EvoNode
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: tree.speciesID, tree: tree, rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private final class SpendClock: @unchecked Sendable {
    var now = Calendar.current.date(bySettingHour: 12, minute: 5, second: 0, of: Date())!
}

@MainActor
final class EvolutionItemSpendTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private let feebas = node(349, [node(350)])

    private func saveFile(_ data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evo-spend-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        try data.write(to: file)
        return file
    }

    private func store(tree: EvoNode, file: URL, clock: SpendClock = SpendClock()) throws -> CompanionStore {
        let suite = "evo-spend-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: SpendProvider(tree: tree), clock: { clock.now }, fileURL: file,
                              rng: SeededRNG(seed: 1), dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func store(tree: EvoNode, clock: SpendClock = SpendClock(), inventory: [ItemKind: Int]) throws
        -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        for (kind, count) in inventory { state.inventory[kind.rawValue] = count }
        return try store(tree: tree, file: saveFile(JSONEncoder().encode(state)), clock: clock)
    }

    private func pet(_ s: CompanionStore, _ clock: SpendClock, times: Int) {
        for _ in 0..<times { clock.now.addTimeInterval(11); s.recordPet() }
    }

    private func feebasReadyForMilotic(holding item: ItemKind, _ clock: SpendClock) async throws
        -> (CompanionStore, String) {
        let s = try store(tree: feebas, clock: clock, inventory: [item: 1])
        await s.hatch(baseID: 349)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        XCTAssertTrue(s.equip(item, to: id))
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 349, "no pets yet")
        return (s, id)
    }

    // MARK: Evolving

    func testFeebasHoldingAPrismScaleUsesItUpWhenPetsOpenMilotic() async throws {
        let clock = SpendClock()
        let (s, id) = try await feebasReadyForMilotic(holding: .prismScale, clock)
        pet(s, clock, times: 60)
        XCTAssertEqual(s.currentSpeciesID, 350)
        XCTAssertNil(s.heldItem(of: id))
        XCTAssertEqual(s.itemCount(.prismScale), 0)
    }

    func testFeebasHoldingLeftoversKeepsThemThroughMilotic() async throws {
        let clock = SpendClock()
        let (s, id) = try await feebasReadyForMilotic(holding: .leftovers, clock)
        pet(s, clock, times: 60)
        XCTAssertEqual(s.currentSpeciesID, 350)
        XCTAssertEqual(s.heldItem(of: id), .leftovers)
        XCTAssertEqual(s.itemCount(.leftovers), 0)
    }

    func testARaisedGraduateFeebasUsesUpThePrismScale() async throws {
        let clock = SpendClock()
        let (s, id) = try await feebasReadyForMilotic(holding: .prismScale, clock)
        XCTAssertTrue(s.skipEvolutionAndGraduate())
        XCTAssertTrue(s.raise(entryID: id))
        await s.checkRaisedGraduateEvolution()
        XCTAssertEqual(s.heldItem(of: id), .prismScale)
        pet(s, clock, times: 60)
        XCTAssertEqual(s.state.dex.first { $0.id == id }?.finalID, 350)
        XCTAssertNil(s.heldItem(of: id))
        XCTAssertEqual(s.itemCount(.prismScale), 0)
    }

    func testSlowpokeUsingAGalaricaWreathUsesUpTheKingsRockItHolds() async throws {
        let s = try store(tree: node(79, [node(80), node(199, item: "galarica-wreath")]),
                          inventory: [.kingsRock: 1, .galaricaWreath: 1])
        await s.hatch(baseID: 79)
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        XCTAssertTrue(s.equip(.kingsRock, to: id))
        XCTAssertEqual(s.useEvolutionStone(.galaricaWreath), .evolved)
        XCTAssertEqual(s.currentSpeciesID, 199)
        XCTAssertNil(s.heldItem(of: id))
        XCTAssertEqual(s.itemCount(.kingsRock), 0)
        XCTAssertEqual(s.itemCount(.galaricaWreath), 0)
    }

    func testAnOldOnixPlannedThroughSteelixUsesUpTheMetalCoatWhenItGrowsThere() async throws {
        let onix = EvoNode(speciesID: 95, children: [
            EvoNode(speciesID: 208, children: [], methods: [EvoMethod(trigger: "trade", item: nil, heldItem: "metal-coat")]),
        ])
        var state = CompanionState()
        state.installBaselineSet = true
        state.active = MonState(baseID: 95, pathIDs: [95], plannedPathIDs: [95, 208], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "o"))
        state.heldItems["o"] = ItemKind.metalCoat.rawValue
        let s = try store(tree: onix, file: saveFile(JSONEncoder().encode(state)))
        try await waitUntil("the line to load") {
            if s.currentLine != nil { return true }
            s.update(todayTokensByProvider: [:], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: false)
            return false
        }
        s.applyUsage(s.tokensToNext)
        XCTAssertEqual(s.currentSpeciesID, 208)
        XCTAssertNil(s.heldItem(of: "o"))
        XCTAssertEqual(s.itemCount(.metalCoat), 0)
    }

    // MARK: Rules

    func testOnlyMiloticAndSlowkingOpenByAWayOtherThanTheItemTheyName() {
        let differing = EvolutionRules.table.filter { rule in
            !rule.heldItemsUsed.isEmpty && rule.paths.contains { path in
                !path.contains { if case .holds(let kind) = $0 { rule.heldItemsUsed.contains(kind) } else { false } }
            }
        }
        XCTAssertEqual(Set(differing.map(\.species)), [199, 350])
    }

    func testEveryItemNamingStepHasAParent() {
        for rule in EvolutionRules.table where !rule.heldItemsUsed.isEmpty {
            XCTAssertNotNil(rule.from, "#\(rule.species)")
        }
    }

    func testTradeOnlyStepsThatNameAnItemAreTheFourteenHeldItemTrades() {
        let tradeOnly = EvolutionRules.table.filter { !$0.heldItemsUsed.isEmpty && $0.paths.isEmpty }
        XCTAssertEqual(Set(tradeOnly.map(\.species)),
                       [186, 208, 212, 230, 233, 367, 368, 464, 466, 467, 474, 477, 683, 685])
    }

    func testNoStepNamesTheEverstone() {
        XCTAssertFalse(EvolutionRules.table.contains { $0.heldItemsUsed.contains(.everstone) })
    }

    // MARK: Leftovers in an old save

    private func oldSave(holding held: [String: ItemKind], dex: [DexEntry], prismScales: Int = 0) throws -> URL {
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = dex
        state.heldItems = held.mapValues(\.rawValue)
        state.inventory[ItemKind.prismScale.rawValue] = prismScales
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["leftoverEvolutionItemsReturned"] = nil
        return try saveFile(JSONSerialization.data(withJSONObject: json))
    }

    private func entry(_ id: String, _ chain: [Int]) -> DexEntry {
        DexEntry(id: id, baseID: chain[0], finalID: chain[chain.count - 1], chainOrder: chain, rarity: .common,
                 caughtAt: Date())
    }

    func testAMiloticKeepingItsPrismScaleGetsItBackInTheBagOnce() throws {
        let file = try oldSave(holding: ["m": .prismScale], dex: [entry("m", [349, 350])], prismScales: 2)
        let s = try store(tree: feebas, file: file)
        XCTAssertNil(s.heldItem(of: "m"))
        XCTAssertEqual(s.itemCount(.prismScale), 3)
        s.save()

        let again = try store(tree: feebas, file: file)
        XCTAssertNil(again.heldItem(of: "m"))
        XCTAssertEqual(again.itemCount(.prismScale), 3)
    }

    func testTheReturnRunsOnceSoALaterEquipStays() throws {
        let file = try oldSave(holding: [:], dex: [entry("m", [349, 350])], prismScales: 1)
        let s = try store(tree: feebas, file: file)
        XCTAssertTrue(s.equip(.prismScale, to: "m"))
        s.save()
        XCTAssertEqual(try store(tree: feebas, file: file).heldItem(of: "m"), .prismScale)
    }

    func testOnlyAnEvolutionItemWithNoUseLeftGoesBack() throws {
        let file = try oldSave(holding: ["leftovers": .leftovers, "feebas": .prismScale, "slowking": .kingsRock,
                                         "seadra": .dragonScale, "horsea": .dragonScale, "pikachu": .prismScale],
                               dex: [entry("leftovers", [349, 350]), entry("feebas", [349]),
                                     entry("slowking", [79, 199]), entry("seadra", [116, 117]),
                                     entry("horsea", [116]), entry("pikachu", [172, 25])])
        let s = try store(tree: feebas, file: file)
        XCTAssertEqual(s.heldItem(of: "leftovers"), .leftovers, "not an evolution item")
        XCTAssertEqual(s.heldItem(of: "feebas"), .prismScale, "its next form names it")
        XCTAssertEqual(s.heldItem(of: "slowking"), .kingsRock, "it has a battle use")
        XCTAssertEqual(s.heldItem(of: "seadra"), .dragonScale, "Kingdra names it")
        XCTAssertEqual(s.heldItem(of: "horsea"), .dragonScale, "it has not passed the step yet")
        XCTAssertEqual(s.heldItem(of: "pikachu"), .prismScale, "it never took a step that names it")
        XCTAssertEqual(s.itemCount(.prismScale), 0)
    }
}
