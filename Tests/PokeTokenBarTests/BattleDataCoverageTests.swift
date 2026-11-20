import XCTest
@testable import PokeTokenBar

/// The battle rule data in `data/battle/` that the bot runs and the app's tests read.
enum BattleData {
    static let kinds = ["items", "abilities", "moves"]

    struct Entry: Decodable {
        let effect: Effect
    }

    /// An entry's `effect`: a key, a list of keys that may hold "todo", "todo", or `{"inert": "<reason>"}`.
    struct Effect: Decodable, Equatable {
        let keys: [String]
        let isTodo: Bool
        let inertReason: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let inert = try? container.decode([String: String].self) {
                guard inert.count == 1, let reason = inert["inert"], !reason.isEmpty else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "malformed inert \(inert)")
                }
                keys = []
                isTodo = false
                inertReason = reason
                return
            }
            let single = try? container.decode(String.self)
            let listed = try single.map { [$0] } ?? container.decode([String].self)
            keys = listed.filter { $0 != "todo" }
            isTodo = listed.contains("todo")
            inertReason = nil
            guard !keys.isEmpty || single == "todo", !listed.contains("") else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "malformed effect \(listed)")
            }
        }
    }

    struct Counts: Codable, Equatable {
        var implemented = 0
        var inert = 0
        var todo = 0
    }

    struct KindBaseline: Decodable {
        let counts: Counts
        let todo: [String]
    }

    static func entries(_ kind: String) throws -> [String: Entry] {
        try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: url("\(kind).json")))
    }

    static func baseline() throws -> [String: KindBaseline] {
        try JSONDecoder().decode([String: KindBaseline].self, from: Data(contentsOf: url("coverage-baseline.json")))
    }

    /// Every item slug the bot runs an effect key for.
    static func knownItems() throws -> Set<String> {
        Set(try entries("items").filter { !$0.value.effect.keys.isEmpty }.keys)
    }

    /// Items with a battle effect no shop item uploads. Mega Stones have their own shelf, and the Mirror Herb is sold
    /// as a training item that is used up.
    static func unsoldItems(_ entries: [String: Entry]) -> [String] {
        let sold = Set(ItemKind.allCases.filter { $0.shopPrice != nil }.compactMap(\.heldItemSlug))
        return entries.filter { slug, entry in
            !entry.effect.keys.isEmpty && !entry.effect.keys.contains("mega-stone") && slug != "mirror-herb"
                && !sold.contains(slug)
        }.keys.sorted()
    }

    /// The item slugs that run `key`.
    static func items(running key: String) throws -> Set<String> {
        Set(try entries("items").filter { $0.value.effect.keys.contains(key) }.keys)
    }

    static func counts(_ entries: [String: Entry]) -> Counts {
        var counts = Counts()
        for entry in entries.values {
            if entry.effect.inertReason != nil {
                counts.inert += 1
            } else if entry.effect.isTodo {
                counts.todo += 1
            } else {
                counts.implemented += 1
            }
        }
        return counts
    }

    /// Why `entries` break the ratchet against `baseline`: a todo entry the baseline lacks, a baseline id that is no
    /// longer todo, or counts that differ.
    static func ratchetErrors(kind: String, entries: [String: Entry], baseline: KindBaseline) -> [String] {
        let todo = Set(entries.filter { $0.value.effect.isTodo }.keys)
        let listed = Set(baseline.todo)
        var errors = todo.subtracting(listed).sorted().map { "\(kind) \($0): todo but not in the baseline" }
        errors += listed.subtracting(todo).sorted().map { "\(kind) \($0): in the baseline but no longer todo" }
        if counts(entries) != baseline.counts {
            errors.append("\(kind): counts \(counts(entries)) differ from the baseline \(baseline.counts)")
        }
        return errors
    }

    private static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/battle/\(name)")
    }
}

final class BattleDataCoverageTests: XCTestCase {
    func testEveryEntryIsClassifiedAndTheTodoListOnlyShrinks() throws {
        let baseline = try BattleData.baseline()
        XCTAssertEqual(Set(baseline.keys), Set(BattleData.kinds))
        for kind in BattleData.kinds {
            let entries = try BattleData.entries(kind)
            let base = try XCTUnwrap(baseline[kind])
            print("\(kind): \(BattleData.counts(entries))")
            XCTAssertEqual(BattleData.ratchetErrors(kind: kind, entries: entries, baseline: base), [])
        }
    }

    func testTheAppCountsWhatTheBotTestCounts() throws {
        let baseline = try BattleData.baseline()
        let items = try BattleData.entries("items")
        XCTAssertEqual(BattleData.counts(items), baseline["items"]?.counts)
        let partial = items.values.filter { $0.effect.isTodo && !$0.effect.keys.isEmpty }.count
        XCTAssertEqual(try BattleData.knownItems().count, BattleData.counts(items).implemented + partial)
        XCTAssertGreaterThan(BattleData.counts(try BattleData.entries("moves")).implemented, 0)
    }

    func testANewTodoEntryFailsTheRatchet() throws {
        var entries = try BattleData.entries("items")
        entries["leftovers"] = try decoded(#"{"effect": "todo"}"#)
        let errors = try BattleData.ratchetErrors(kind: "items", entries: entries, baseline: XCTUnwrap(BattleData.baseline()["items"]))
        XCTAssertTrue(errors.contains("items leftovers: todo but not in the baseline"), "\(errors)")
    }

    func testABaselineIDThatIsNoLongerTodoFailsTheRatchet() throws {
        var entries = try BattleData.entries("abilities")
        let stale = try XCTUnwrap(entries.keys.min())
        let baseline = try BattleData.KindBaseline(counts: XCTUnwrap(BattleData.baseline()["abilities"]).counts, todo: [stale])
        entries[stale] = try decoded(#"{"effect": {"inert": "test"}}"#)
        let errors = BattleData.ratchetErrors(kind: "abilities", entries: entries, baseline: baseline)
        XCTAssertTrue(errors.contains("abilities \(stale): in the baseline but no longer todo"), "\(errors)")
    }

    func testAnEffectDecodesAsAKeyAListOrAnInertReason() throws {
        XCTAssertEqual(try decoded(#"{"effect": "leftovers"}"#).effect.keys, ["leftovers"])
        let partial = try decoded(#"{"effect": ["rocky-helmet", "todo"]}"#).effect
        XCTAssertEqual(partial.keys, ["rocky-helmet"])
        XCTAssertTrue(partial.isTodo)
        XCTAssertEqual(try decoded(#"{"effect": {"inert": "doubles only"}}"#).effect.inertReason, "doubles only")
        for malformed in [#"[]"#, #"["todo"]"#, #"{"inert": ""}"#, #"{"other": "x"}"#, #"5"#, #""""#] {
            XCTAssertThrowsError(try decoded(#"{"effect": \#(malformed)}"#), malformed)
        }
    }

    func testTheShopSellsEveryHeldItemWithABattleEffect() throws {
        XCTAssertEqual(BattleData.unsoldItems(try BattleData.entries("items")), [])
    }

    func testAnItemTheShopLacksFailsTheShopCheck() throws {
        var entries = try BattleData.entries("items")
        entries["test-orb"] = try decoded(#"{"effect": "leftovers"}"#)
        entries["test-stone"] = try decoded(#"{"effect": "mega-stone"}"#)
        XCTAssertEqual(BattleData.unsoldItems(entries), ["test-orb"])
    }

    private func decoded(_ json: String) throws -> BattleData.Entry {
        try JSONDecoder().decode(BattleData.Entry.self, from: Data(json.utf8))
    }
}
