import XCTest
@testable import PokeTokenBar

/// The one place that spells out prices. Other tests read the constants, so a price change touches
/// one source line and one line here.
@MainActor
final class ShopPriceTableTests: XCTestCase {
    func testPrices() {
        let table: [(String, Int, Int)] = [
            ("rare candy", RareCandy.price, 10_000_000),
            ("mint", Mint.price, 2_000_000),
            ("evolution stone", EvolutionStone.price, 20_000_000),
            ("held item", HeldItem.price, 60_000_000),
            ("shiny charm", ShinyCharm.price, 60_000_000),
            ("exp. share, first", ExpShare.prices[0], 60_000_000),
            ("exp. share, second", ExpShare.prices[1], 120_000_000),
            ("mega stone", MegaStone.price, 120_000_000),
            ("egg", FreshEgg.price(guaranteeing: nil), 20_000_000),
            ("uncommon egg", FreshEgg.price(guaranteeing: .uncommon), 50_000_000),
            ("rare egg", FreshEgg.price(guaranteeing: .rare), 80_000_000),
            ("scout ticket", ScoutTicket.price, 60_000_000),
            ("TM, power under 70", PokemonBalance.machinePrice(power: 60, isWeather: false), 4_000_000),
            ("TM, power 70 to 99", PokemonBalance.machinePrice(power: 90, isWeather: false), 8_000_000),
            ("TM, power 100 and up", PokemonBalance.machinePrice(power: 100, isWeather: false), 12_000_000),
            ("TM, weather", PokemonBalance.machinePrice(power: 0, isWeather: true), 12_000_000),
            ("Gimmighoul spend gate", Self.gimmighoulSpend, 20_000_000),
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

    func testTheSpendGateNeedsItsAmount() {
        var context = EvolutionContext()
        context.spentTokens = Self.gimmighoulSpend - 1
        XCTAssertEqual(EvolutionRequirement.spent(Self.gimmighoulSpend).progress(in: context).need, Self.gimmighoulSpend)
        XCTAssertFalse(EvolutionRequirement.spent(Self.gimmighoulSpend).isMet(in: context))
        context.spentTokens = Self.gimmighoulSpend
        XCTAssertTrue(EvolutionRequirement.spent(Self.gimmighoulSpend).isMet(in: context))
    }

    func testTheSpendGateLabelShowsTheAmount() {
        let text = L(.en).evolutionRequirementText(.spent(Self.gimmighoulSpend), speciesName: { "#\($0)" })
        XCTAssertTrue(text.contains(TokenFormatter.compact(Self.gimmighoulSpend)), text)
    }
}
