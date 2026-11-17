import XCTest
@testable import PokeTokenBar

/// Reads the bot's Python item tables so the app's item list can be checked against them.
enum BotItemSource {
    static func read(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(path), encoding: .utf8)
    }

    /// The keys of `ITEM_NAMES` in `bot/ypoke/items.py`, string literals and module constants alike.
    static func itemNames() throws -> Set<String> {
        try names(of: "ITEM_NAMES", in: read("bot/ypoke/items.py"))
    }

    /// The keys of `MEGA_STONES` in `bot/ypoke/mega_stones.py`.
    static func megaStones() throws -> Set<String> {
        try names(of: "MEGA_STONES", in: read("bot/ypoke/mega_stones.py"))
    }

    /// Every item an NPC can hold: the held item of each fixed team row in `gym_data.py`, and every item
    /// `foe_items.py` (which picks the items of the generated gym, Elite Four and org teams) refers to.
    static func npcHeldItems() throws -> Set<String> {
        let teams = try read("bot/ypoke/gym_data.py")
        var slugs = Set(teams.matches(of: /\(\d+, "([a-z0-9-]+)", \(/).map { String($0.1) })
        let items = try read("bot/ypoke/items.py")
        let picker = try read("bot/ypoke/foe_items.py")
        for name in Set(picker.matches(of: /\bitems\.([A-Z][A-Z0-9_]*)\b/).map { String($0.1) }) {
            slugs.formUnion(try names(of: name, in: items))
        }
        return slugs
    }

    /// The item slugs a top-level `name = ...` statement holds: a string constant, a dict's keys, or a
    /// collection's members. Module constants inside resolve to their strings.
    private static func names(of name: String, in source: String) throws -> Set<String> {
        let constants = Dictionary(source.matches(of: /(?m)^([A-Z][A-Z0-9_]*) = "([a-z0-9-]+)"$/)
            .map { (String($0.1), String($0.2)) }, uniquingKeysWith: { first, _ in first })
        if let slug = constants[name] { return [slug] }
        let head = try XCTUnwrap(source.firstMatch(of: try Regex("(?m)^\(name)(?::[^=]*)? = ")), "no \(name)")
        let rest = source[head.range.upperBound...]
        let statement = rest[..<(rest.firstMatch(of: /\n(?=\S)/)?.range.lowerBound ?? rest.endIndex)]
        let isDict = statement.hasPrefix("{")
        var slugs = Set<String>()
        let pattern = isDict ? /(?:"([a-z0-9-]+)"|\b([A-Z][A-Z0-9_]*))\s*:/ : /(?:"([a-z0-9-]+)"|\b([A-Z][A-Z0-9_]*))\b/
        for match in statement.matches(of: pattern) {
            if let literal = match.1 {
                slugs.insert(String(literal))
            } else if let constant = match.2 {
                slugs.insert(try XCTUnwrap(constants[String(constant)], "unknown constant \(constant)"))
            }
        }
        XCTAssertFalse(slugs.isEmpty, "\(name) holds no item")
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
        try expectFailure(saying: "the app has no item booster-energy") {
            try assertSoldAndKnown(["booster-energy"], sold: shopEntries(), known: ["booster-energy"])
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
        XCTAssertTrue(slugs.contains("charcoal"), "a TYPE_BOOST_ITEMS key that is a constant")
        XCTAssertTrue(slugs.contains("fairy-feather"), "a TYPE_BOOST_ITEMS key that is a literal")
        for slug in ["rusted-sword", "rusted-shield", "ultranecrozium-z", "floettite"] {
            XCTAssertTrue(slugs.contains(slug), "an Ace row's item \(slug)")
        }
    }

    private func assertSoldAndKnown(_ slugs: Set<String>, sold: Set<ShopEntry>, known: Set<String>? = nil) throws {
        let known = try known ?? BotItemSource.itemNames().union(BotItemSource.megaStones())
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
