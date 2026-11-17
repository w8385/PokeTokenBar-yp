import XCTest
@testable import PokeTokenBar

/// The one place that spells out base prices. Other tests read the constants, so a price change touches
/// one source line and one line here.
@MainActor
final class ShopPriceTableTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    func testBasePricesAtDifficultyOne() {
        let table: [(String, Int, Int)] = [
            ("rare candy", RareCandy.price, 100_000_000),
            ("mint", Mint.price, 20_000_000),
            ("evolution stone", EvolutionStone.price, 200_000_000),
            ("held item", HeldItem.price, 600_000_000),
            ("shiny charm", ShinyCharm.price, 600_000_000),
            ("exp. share, first", ExpShare.prices[0], 600_000_000),
            ("exp. share, second", ExpShare.prices[1], 1_200_000_000),
            ("mega stone", MegaStone.price, 1_200_000_000),
            ("egg", FreshEgg.price(guaranteeing: nil), 200_000_000),
            ("uncommon egg", FreshEgg.price(guaranteeing: .uncommon), 500_000_000),
            ("rare egg", FreshEgg.price(guaranteeing: .rare), 800_000_000),
            ("scout ticket", ScoutTicket.price, 600_000_000),
            ("TM, power under 70", PokemonBalance.machinePrice(power: 60, isWeather: false), 40_000_000),
            ("TM, power 70 to 99", PokemonBalance.machinePrice(power: 90, isWeather: false), 80_000_000),
            ("TM, power 100 and up", PokemonBalance.machinePrice(power: 100, isWeather: false), 120_000_000),
            ("TM, weather", PokemonBalance.machinePrice(power: 0, isWeather: true), 120_000_000),
            ("Gimmighoul spend gate", Self.gimmighoulSpend, 200_000_000),
        ]
        for (name, actual, expected) in table {
            XCTAssertEqual(actual, expected, name)
        }
    }

    // MARK: Gimmighoul's spend gate

    private static var gimmighoulSpend: Int {
        let requirements = EvolutionRules.rule(for: 1000)?.paths.flatMap { $0 } ?? []
        for case .spent(let n) in requirements { return n }
        return 0
    }

    func testTheSpendGateNeedsItsBaseTimesTheShopDifficulty() {
        var context = EvolutionContext()
        context.spentTokens = Self.gimmighoulSpend
        XCTAssertTrue(EvolutionRequirement.spent(Self.gimmighoulSpend).isMet(in: context))

        context.shopDifficulty = 2
        let progress = EvolutionRequirement.spent(Self.gimmighoulSpend).progress(in: context)
        XCTAssertEqual(progress.need, 2 * Self.gimmighoulSpend)
        XCTAssertFalse(EvolutionRequirement.spent(Self.gimmighoulSpend).isMet(in: context))
        context.spentTokens = 2 * Self.gimmighoulSpend
        XCTAssertTrue(EvolutionRequirement.spent(Self.gimmighoulSpend).isMet(in: context))
    }

    func testTheSpendGateLabelShowsTheScaledAmount() {
        let l = L(.en)
        let text = l.evolutionRequirementText(.spent(Self.gimmighoulSpend), speciesName: { "#\($0)" }, shopDifficulty: 2)
        XCTAssertTrue(text.contains(TokenFormatter.compact(2 * Self.gimmighoulSpend)), text)
        let base = l.evolutionRequirementText(.spent(Self.gimmighoulSpend), speciesName: { "#\($0)" },
                                              shopDifficulty: PokemonBalance.defaultDifficulty)
        XCTAssertTrue(base.contains(TokenFormatter.compact(Self.gimmighoulSpend)), base)
    }

    func testTheStoreHandsItsShopDifficultyToTheEvolutionContext() throws {
        var state = CompanionState()
        state.installBaselineSet = true
        state.lastDate = "d1"
        state.active = MonState(baseID: 999, pathIDs: [999, 1000], stageIndex: 0, usedAtStage: 0, rarity: .common,
                                totalForms: 2, profile: PokemonProfile.generate(seed: 1, instanceID: "gimmighoul"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("price-table-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "price-table-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: PokemonBalance.difficultyMigratedKey)
        let store = CompanionStore(provider: PriceTableNoProvider(), fileURL: url, rng: SeededRNG(seed: 1),
                                   dittoDisguiseRollingEnabled: false, defaults: defaults)
        store.setShopDifficulty(2)
        let mon = try XCTUnwrap(store.state.active)
        XCTAssertEqual(store.evolutionContext(for: mon).shopDifficulty, 2)
    }
}

private struct PriceTableNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}
