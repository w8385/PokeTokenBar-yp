import XCTest
@testable import PokeTokenBar

private let urshifuMethods = [
    EvoMethod(trigger: "tower-of-darkness"), EvoMethod(trigger: "tower-of-waters"),
    EvoMethod(trigger: "use-item", item: "scroll-of-darkness"), EvoMethod(trigger: "use-item", item: "scroll-of-waters"),
]
private let kubfu = EvoNode(speciesID: 891, children: [EvoNode(speciesID: 892, children: [], methods: urshifuMethods)])
private let singleStrike = PokemonForm("single-strike")
private let rapidStrike = PokemonForm("rapid-strike")

private struct KubfuProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 891, tree: kubfu, rarity: .legendary, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class UrshifuFormTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func store(_ state: CompanionState) throws -> CompanionStore {
        try store(data: JSONEncoder().encode(state))
    }

    private func store(data: Data) throws -> CompanionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("urshifu-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        try data.write(to: file)
        let suite = "urshifu-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: KubfuProvider(), fileURL: file, rng: SeededRNG(seed: 1),
                              dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func hatchedKubfu(_ inventory: [ItemKind: Int] = [:]) async throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        for (kind, count) in inventory { state.inventory[kind.rawValue] = count }
        let s = try store(state)
        await s.hatch(baseID: 891)
        XCTAssertEqual(s.currentSpeciesID, 891)
        return s
    }

    private func assertUrshifu(_ s: CompanionStore, _ form: PokemonForm, pokemonID: Int, types: [String],
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.currentSpeciesID, 892, file: file, line: line)
        XCTAssertEqual(s.currentForm, form, file: file, line: line)
        XCTAssertEqual(PartyBuilder.party(from: s.state).first?.pokemonID, pokemonID, file: file, line: line)
        let battleTypes = FormBattleData.of(speciesID: 892, form: s.currentForm)?.types ?? ["fighting", "dark"]
        XCTAssertEqual(battleTypes, types, file: file, line: line)
        XCTAssertEqual(PokemonForm.staticAssetName(speciesID: 892, form: s.currentForm), String(pokemonID),
                       file: file, line: line)
    }

    // MARK: Evolving

    func testTheScrollOfWatersGivesRapidStrikeUrshifu() async throws {
        let s = try await hatchedKubfu([.scrollOfWaters: 1])
        XCTAssertEqual(s.useEvolutionStone(.scrollOfWaters), .evolved)
        assertUrshifu(s, rapidStrike, pokemonID: 10191, types: ["fighting", "water"])
        XCTAssertEqual(s.itemCount(.scrollOfWaters), 0)
    }

    func testTheScrollOfDarknessGivesSingleStrikeUrshifu() async throws {
        let s = try await hatchedKubfu([.scrollOfDarkness: 1])
        XCTAssertEqual(s.useEvolutionStone(.scrollOfDarkness), .evolved)
        assertUrshifu(s, singleStrike, pokemonID: 892, types: ["fighting", "dark"])
    }

    func testAScrollInTheBagPicksTheStyleWhenGrowthOpensTheStep() async throws {
        let s = try await hatchedKubfu([.scrollOfWaters: 1])
        s.applyUsage(s.tokensToNext)
        assertUrshifu(s, rapidStrike, pokemonID: 10191, types: ["fighting", "water"])
        XCTAssertEqual(s.itemCount(.scrollOfWaters), 0)
    }

    func testTheTowerChosenPicksTheStyle() async throws {
        for (tower, form, pokemonID, types) in [("waters", rapidStrike, 10191, ["fighting", "water"]),
                                                ("darkness", singleStrike, 892, ["fighting", "dark"])] {
            let s = try await hatchedKubfu()
            s.applyUsage(s.tokensToNext)
            XCTAssertEqual(s.currentSpeciesID, 891, "no tower yet")
            s.chooseTower(tower)
            assertUrshifu(s, form, pokemonID: pokemonID, types: types)
        }
    }

    func testTheScrollUsedWinsOverAFormTheKubfuAlreadyCarried() async throws {
        var state = CompanionState()
        state.installBaselineSet = true
        state.inventory[ItemKind.scrollOfDarkness.rawValue] = 1
        state.active = MonState(baseID: 891, pathIDs: [891], plannedPathIDs: [891, 892], stageIndex: 0, usedAtStage: 0,
                                rarity: .legendary, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 3, instanceID: "k"), form: rapidStrike)
        let s = try store(state)
        try await waitUntil("the line to load") {
            if s.currentLine != nil { return true }
            s.update(todayTokensByProvider: [:], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: false)
            return false
        }
        XCTAssertEqual(s.useEvolutionStone(.scrollOfDarkness), .evolved)
        assertUrshifu(s, singleStrike, pokemonID: 892, types: ["fighting", "dark"])
    }

    func testARaisedGraduateKubfuTakesTheTowerItsTrainerChose() async throws {
        let s = try await hatchedKubfu()
        let id = try XCTUnwrap(s.state.active?.profile?.instanceID)
        s.applyUsage(s.tokensToNext)
        XCTAssertTrue(s.skipEvolutionAndGraduate())
        XCTAssertTrue(s.raise(entryID: id))
        await s.checkRaisedGraduateEvolution()
        s.chooseTower("waters")
        let entry = try XCTUnwrap(s.state.dex.first { $0.id == id })
        XCTAssertEqual(entry.finalID, 892)
        XCTAssertEqual(PokemonForm.resolved(speciesID: 892, form: entry.form), rapidStrike)
        XCTAssertEqual(PartyBuilder.member(speciesID: 892, form: entry.form, shiny: false, profile: nil).pokemonID, 10191)
    }

    func testAKubfuEggDrawsNoFormSoItsStyleWaitsForTheEvolution() throws {
        let s = try store(CompanionState())
        XCTAssertNil(s.rollLineForm(baseID: 891))
    }

    // MARK: Repairing saves from before the style was kept

    private func oldSave(inventory: [String: Int], active: [Int]? = [891, 892],
                         graduates: [[Int]] = [], boxed: [Int]? = nil) throws -> Data {
        var state = CompanionState()
        state.installBaselineSet = true
        state.inventory = inventory
        if let active {
            state.active = MonState(baseID: 891, pathIDs: active, plannedPathIDs: active,
                                    stageIndex: active.count - 1, usedAtStage: 0, rarity: .legendary,
                                    totalForms: active.count, profile: PokemonProfile.generate(seed: 3, instanceID: "a"))
        }
        if let boxed {
            let profile = PokemonProfile.generate(seed: 4, instanceID: "box")
            let mon = MonState(baseID: 891, pathIDs: boxed, plannedPathIDs: boxed, stageIndex: boxed.count - 1,
                               usedAtStage: 0, rarity: .legendary, totalForms: boxed.count, profile: profile)
            state.storedLines["box"] = StoredLine(mon: mon, spentAtStore: 0)
            state.dex.append(DexEntry(id: "box", baseID: 891, finalID: boxed.last!, chainOrder: boxed,
                                      rarity: .legendary, caughtAt: Date(timeIntervalSince1970: 0), profile: profile,
                                      releasedAt: Date(timeIntervalSince1970: 0)))
        }
        for (index, chain) in graduates.enumerated() {
            state.dex.append(DexEntry(id: "g\(index)", baseID: 891, finalID: chain.last!, chainOrder: chain,
                                      rarity: .legendary, caughtAt: Date(timeIntervalSince1970: 0)))
        }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object["urshifuStylesRepaired"] = nil
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testAnOldSaveWhoseOnlyScrollSpentWasTheScrollOfWatersMakesItsUrshifuRapidStrike() throws {
        let s = try store(data: oldSave(inventory: ["scrollOfWaters": 0]))
        XCTAssertEqual(s.state.active?.form, rapidStrike)
        XCTAssertTrue(s.state.urshifuStylesRepaired)
    }

    func testAnOldSaveRepairsAGraduateUrshifuToo() throws {
        let s = try store(data: oldSave(inventory: ["scrollOfWaters": 0], active: nil, graduates: [[891, 892]]))
        XCTAssertEqual(s.state.dex.first?.form, rapidStrike)
    }

    func testAnOldSaveRepairsAnUrshifuInTheBoxAndItsDexRow() throws {
        let s = try store(data: oldSave(inventory: ["scrollOfWaters": 0], active: nil, boxed: [891, 892]))
        XCTAssertEqual(s.state.storedLines["box"]?.mon.form, rapidStrike)
        XCTAssertEqual(s.state.dex.first { $0.id == "box" }?.form, rapidStrike)
    }

    func testAnOldSaveLeavesUrshifuAloneWhenTheRecordDoesNotSettleItsStyle() throws {
        let unsettled: [(String, [String: Int], [Int]?, [[Int]])] = [
            ("never bought a scroll", [:], [891, 892], []),
            ("a Scroll of Waters still in the bag", ["scrollOfWaters": 1], [891, 892], []),
            ("a Scroll of Darkness was owned too", ["scrollOfWaters": 0, "scrollOfDarkness": 0], [891, 892], []),
            ("two Urshifu for one record", ["scrollOfWaters": 0], [891, 892], [[891, 892]]),
            ("the Kubfu has not evolved", ["scrollOfWaters": 0], [891], []),
        ]
        for (reason, inventory, active, graduates) in unsettled {
            let s = try store(data: oldSave(inventory: inventory, active: active, graduates: graduates))
            XCTAssertEqual(PokemonForm.resolved(speciesID: 892, form: s.state.active?.form ?? s.state.dex.first?.form),
                           singleStrike, reason)
            XCTAssertTrue(s.state.urshifuStylesRepaired, reason)
        }
    }

    func testANewSaveNeverRewritesAnUrshifuItsTrainerChose() throws {
        var state = CompanionState()
        state.installBaselineSet = true
        state.inventory = ["scrollOfWaters": 0]
        state.active = MonState(baseID: 891, pathIDs: [891, 892], plannedPathIDs: [891, 892], stageIndex: 1,
                                usedAtStage: 0, rarity: .legendary, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 3, instanceID: "a"), form: singleStrike)
        let s = try store(state)
        XCTAssertEqual(s.state.active?.form, singleStrike)
    }
}
