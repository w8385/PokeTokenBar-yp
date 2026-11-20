import XCTest
@testable import PokeTokenBar

/// The items NPC teams hold, read from the bot's team data and item picker.
enum BotItemSource {
    /// The `ypoke.items` tables `foe_items.py` can pick from, by the effect key their entries run in `items.json`.
    static let tableKeys = [
        "TYPE_BOOST_ITEMS": ["type-boost"], "RESIST_BERRIES": ["resist-berry"], "PLATES": ["plate"],
        "WEATHER_ROCKS": ["weather-rock"], "OGERPON_MASKS": ["ogerpon-mask"], "ORIGIN_BOOSTS": ["origin-boost"],
        "ORB_AILMENTS": ["status-orb"], "SPECIES_ITEMS": ["origin-boost", "species-stat", "species-crit"],
    ]

    static func read(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(path), encoding: .utf8)
    }

    /// Every item an NPC can hold: the held item of each fixed team row in `gym_data.py`, and every item
    /// `foe_items.py` (which picks the items of the generated gym, Elite Four and org teams) refers to, a
    /// constant (`items.LEFTOVERS` is "leftovers") or a table.
    static func npcHeldItems() throws -> Set<String> {
        let teams = try read("bot/ypoke/gym_data.py")
        var slugs = Set(teams.matches(of: /\(\d+, "([a-z0-9-]+)", \(/).map { String($0.1) })
        let picker = try read("bot/ypoke/foe_items.py")
        for name in Set(picker.matches(of: /\bitems\.([A-Z][A-Z0-9_]*)\b/).map { String($0.1) }) {
            if let keys = tableKeys[name] {
                for key in keys {
                    let table = try BattleData.items(running: key)
                    XCTAssertFalse(table.isEmpty, "no item runs \(key)")
                    slugs.formUnion(table)
                }
            } else {
                slugs.insert(name.lowercased().replacingOccurrences(of: "_", with: "-"))
            }
        }
        return slugs
    }
}

@MainActor
final class NPCHeldItemsTests: XCTestCase {
    private struct NoProvider: PokeProviding {
        func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
        func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    }

    private func shopEntries() -> Set<ShopEntry> {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("npc-items-\(UUID()).json")
        let store = CompanionStore(provider: NoProvider(), fileURL: file)
        return Set(store.shopEntries + store.megaStoneShopEntries + store.shopEvolutionItems.map(ShopEntry.item))
    }

    /// The shop entry an uploaded slug comes from, or nil when the app has no such item.
    private func entry(for slug: String) -> ShopEntry? {
        if let kind = ItemKind.allCases.first(where: { $0.heldItemSlug == slug }) { return .item(kind) }
        return MegaStone.stone(slug: slug).map(ShopEntry.megaStone)
    }

    func testEveryItemAnNPCHoldsIsSoldInTheShopAndKnownToTheBot() throws {
        try assertSoldAndKnown(BotItemSource.npcHeldItems(), sold: shopEntries())
    }

    func testTheCheckFailsForAnNPCItemTheShopStopsSelling() throws {
        let sold = shopEntries().subtracting([.item(.focusSash)])
        try expectFailure(saying: "the Shop does not sell focus-sash") {
            try assertSoldAndKnown(BotItemSource.npcHeldItems(), sold: sold)
        }
    }

    func testTheCheckFailsForAnItemTheBotLacks() throws {
        try expectFailure(saying: "the bot has no item everstone") {
            try assertSoldAndKnown(["everstone"], sold: shopEntries())
        }
    }

    func testTheCheckFailsForAnItemTheAppLacks() throws {
        try expectFailure(saying: "the app has no item destiny-knot") {
            try assertSoldAndKnown(["destiny-knot"], sold: shopEntries(), known: ["destiny-knot"])
        }
    }

    private func expectFailure(saying message: String, _ body: () throws -> Void) throws {
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { $0.compactDescription.contains(message) }
        try XCTExpectFailure("the check must name \(message)", options: options, failingBlock: body)
    }

    func testTheParserReadsLiteralRowsConstantsAndTheTypeBoostTable() throws {
        let slugs = try BotItemSource.npcHeldItems()
        XCTAssertTrue(slugs.contains("dragoninite"), "a champion row's literal item")
        XCTAssertTrue(slugs.contains("eviolite"), "a constant the picker names")
        XCTAssertTrue(slugs.contains("charcoal"), "a type-boost item")
        XCTAssertTrue(slugs.contains("fairy-feather"), "a type-boost item")
        XCTAssertTrue(slugs.contains("stellar-crystal"), "a constant with an underscore")
        for slug in ["rusted-sword", "rusted-shield", "ultranecrozium-z", "floettite"] {
            XCTAssertTrue(slugs.contains(slug), "an Ace row's item \(slug)")
        }
    }

    private func assertSoldAndKnown(_ slugs: Set<String>, sold: Set<ShopEntry>, known: Set<String>? = nil) throws {
        let known = try known ?? BattleData.knownItems()
        for slug in slugs.sorted() {
            XCTAssertTrue(known.contains(slug), "the bot has no item \(slug)")
            guard let entry = entry(for: slug) else {
                XCTFail("the app has no item \(slug)")
                continue
            }
            XCTAssertTrue(sold.contains(entry), "the Shop does not sell \(slug)")
            if case .item(let kind) = entry, kind.category == .heldItem {
                XCTAssertEqual(kind.shopPrice, HeldItem.price, slug)
            }
        }
    }
}
