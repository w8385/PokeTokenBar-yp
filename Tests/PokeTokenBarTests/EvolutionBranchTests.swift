import XCTest
@testable import PokeTokenBar

private let item = "use-item"
private func stone(_ id: Int, _ name: String, extra: [EvoMethod] = []) -> EvoNode {
    EvoNode(speciesID: id, children: [], methods: extra + [EvoMethod(trigger: item, item: name)])
}
private func levelUp(_ id: Int, time: String? = nil) -> EvoNode {
    EvoNode(speciesID: id, children: [], methods: [EvoMethod(trigger: "level-up", item: nil, timeOfDay: time)])
}

private struct BranchProvider: PokeProviding {
    let tree: EvoNode
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: tree.speciesID, tree: tree, rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private final class ClockBox: @unchecked Sendable {
    var now = Date()
    func set(hour: Int) {
        now = Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: Date())!
    }
}

private let eevee = EvoNode(speciesID: 133, children: [
    stone(134, "water-stone"), stone(135, "thunder-stone"), stone(136, "fire-stone"),
    levelUp(196, time: "day"), levelUp(197, time: "night"),
    stone(470, "leaf-stone", extra: [EvoMethod(trigger: "level-up")]),
    stone(471, "ice-stone", extra: [EvoMethod(trigger: "level-up")]),
    levelUp(700),
])

@MainActor
final class EvolutionBranchTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func store(tree: EvoNode, clock: ClockBox = ClockBox(), stones: [ItemKind: Int] = [:],
                       tokens: Int = 0, seed: UInt64 = 1) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = tokens
        for (kind, count) in stones { state.inventory[kind.rawValue] = count }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evo-branch-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "evo-branch-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: BranchProvider(tree: tree), clock: { clock.now }, fileURL: file,
                              rng: SeededRNG(seed: seed), dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    func testWaterStoneEvolvesEeveeIntoVaporeon() async throws {
        let s = try store(tree: eevee, stones: [.waterStone: 2])
        await s.hatch(baseID: 133)
        let xp = s.state.active?.usedAtStage
        XCTAssertEqual(s.useEvolutionStone(.waterStone), .evolved)
        XCTAssertEqual(s.currentSpeciesID, 134)
        XCTAssertEqual(s.state.active?.pathIDs, [133, 134])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [133, 134])
        XCTAssertEqual(s.state.active?.usedAtStage, xp)
        XCTAssertEqual(s.itemCount(.waterStone), 1)
    }

    func testEachStoneTakesItsOwnBranch() async throws {
        let expected: [ItemKind: Int] = [.waterStone: 134, .thunderStone: 135, .fireStone: 136,
                                         .leafStone: 470, .iceStone: 471]
        for (kind, species) in expected {
            let s = try store(tree: eevee, stones: [kind: 1])
            await s.hatch(baseID: 133)
            XCTAssertEqual(s.useEvolutionStone(kind), .evolved, "\(kind)")
            XCTAssertEqual(s.currentSpeciesID, species, "\(kind)")
        }
    }

    func testWrongStoneDoesNothingAndStaysInBag() async throws {
        let s = try store(tree: eevee, stones: [.moonStone: 1])
        await s.hatch(baseID: 133)
        XCTAssertFalse(s.stoneFits(.moonStone))
        XCTAssertEqual(s.useEvolutionStone(.moonStone), .wrongStone)
        XCTAssertEqual(s.currentSpeciesID, 133)
        XCTAssertEqual(s.state.active?.stageIndex, 0)
        XCTAssertEqual(s.itemCount(.moonStone), 1)
    }

    func testStoneOnFinalFormOrWithoutStoneIsRefused() async throws {
        let s = try store(tree: eevee, stones: [.waterStone: 1])
        await s.hatch(baseID: 133)
        XCTAssertEqual(s.useEvolutionStone(.fireStone), .unavailable, "재고 없음")
        XCTAssertEqual(s.useEvolutionStone(.waterStone), .evolved)
        let t = try store(tree: EvoNode(speciesID: 133, children: [levelUp(2)]), stones: [.waterStone: 1])
        await t.hatch(baseID: 133)
        t.applyUsage(t.tokensToNext)
        XCTAssertEqual(t.useEvolutionStone(.waterStone), .wrongStone, "이미 진화한 뒤엔 맞는 갈래 없음")
        XCTAssertEqual(t.itemCount(.waterStone), 1)
    }

    func testEeveeLevelUpAtNightBecomesUmbreonAndByDayEspeon() async throws {
        let twoWay = EvoNode(speciesID: 133, children: [levelUp(196, time: "day"), levelUp(197, time: "night")])
        for seed in 1...8 as ClosedRange<UInt64> {
            for (hour, species) in [(23, 197), (3, 197), (12, 196), (6, 196), (17, 196), (18, 197)] {
                let clock = ClockBox()
                let s = try store(tree: twoWay, clock: clock, seed: seed)
                await s.hatch(baseID: 133)
                for _ in 0..<30 { clock.now.addTimeInterval(11); s.recordPet() }
                clock.set(hour: hour)
                s.applyUsage(s.tokensToNext)
                XCTAssertEqual(s.currentSpeciesID, species, "seed \(seed) hour \(hour)")
                XCTAssertEqual(s.state.active?.plannedPathIDs, [133, species])
            }
        }
    }

    func testBranchWithoutTimeConditionKeepsPlannedChoice() async throws {
        let tyrogue = EvoNode(speciesID: 236, children: [levelUp(106), levelUp(107), levelUp(237)])
        for seed in 1...8 as ClosedRange<UInt64> {
            let s = try store(tree: tyrogue, seed: seed)
            await s.hatch(baseID: 236)
            let planned = try XCTUnwrap(s.state.active?.plannedPathIDs[1])
            s.applyUsage(s.tokensToNext)
            XCTAssertEqual(s.currentSpeciesID, planned, "seed \(seed)")
        }
    }

    func testLinearStoneEvolutionWorksAndSunStoneIsGloomsOtherBranch() async throws {
        let pikachu = EvoNode(speciesID: 25, children: [stone(26, "thunder-stone")])
        let p = try store(tree: pikachu, stones: [.thunderStone: 1, .moonStone: 1])
        await p.hatch(baseID: 25)
        XCTAssertEqual(p.useEvolutionStone(.moonStone), .wrongStone)
        XCTAssertEqual(p.useEvolutionStone(.thunderStone), .evolved)
        XCTAssertEqual(p.currentSpeciesID, 26)

        let gloom = EvoNode(speciesID: 44, children: [stone(45, "leaf-stone"), stone(182, "sun-stone")])
        let g = try store(tree: gloom, stones: [.sunStone: 1])
        await g.hatch(baseID: 44)
        XCTAssertEqual(g.useEvolutionStone(.sunStone), .evolved)
        XCTAssertEqual(g.currentSpeciesID, 182)
    }

    func testStonesAreSoldInTheirOwnSectionAndCostOneBillion() throws {
        let s = try store(tree: eevee, tokens: 3_000_000_000)
        XCTAssertEqual(s.evolutionStoneItems.filter { $0.evolutionItemName?.hasSuffix("-stone") == true }.count, 10)
        XCTAssertEqual(s.shopEvolutionItems.count, s.evolutionStoneItems.count + 4)
        XCTAssertFalse(s.purchasableItems.contains(.waterStone))
        XCTAssertEqual(s.price(of: .waterStone), 1_000_000_000)
        XCTAssertTrue(s.buy(.waterStone, count: 2))
        XCTAssertEqual(s.itemCount(.waterStone), 2)
        XCTAssertEqual(s.availableTokens, 1_000_000_000)
    }

    func testChainDetailsParseTriggerItemAndTimeOfDay() throws {
        let json = """
        [{"trigger":{"name":"use-item","url":null},"item":{"name":"water-stone","url":null},"time_of_day":""},
         {"trigger":{"name":"level-up","url":null},"item":null,"time_of_day":"night","min_happiness":160}]
        """
        let details = try JSONDecoder().decode([EvolutionDetailDTO].self, from: Data(json.utf8))
        XCTAssertEqual(PokeAPIClient.methods(from: details), [
            EvoMethod(trigger: "use-item", item: "water-stone", timeOfDay: nil),
            EvoMethod(trigger: "level-up", item: nil, timeOfDay: "night")])
        XCTAssertEqual(PokeAPIClient.methods(from: nil), [])
    }

    func testDayPeriodBoundaries() {
        let cal = Calendar.current
        func period(_ hour: Int) -> DayPeriod {
            DayPeriod.at(cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!)
        }
        XCTAssertEqual(period(5), .night)
        XCTAssertEqual(period(6), .day)
        XCTAssertEqual(period(17), .day)
        XCTAssertEqual(period(18), .night)
    }
}
