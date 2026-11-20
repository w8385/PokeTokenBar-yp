import Foundation
import XCTest
@testable import PokeTokenBar

private struct LineupProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class RemoteLineupTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    private let leftovers = ItemKind.leftovers.rawValue
    private let scarf = ItemKind.choiceScarf.rawValue
    private let thunderbolt = MachineMove.inventoryKey(85)

    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    // MARK: Applying

    func testALineupSetsTheSlotsMovesAndItemsAndTheUploadCarriesThem() throws {
        let rig = try rig()
        let reason = apply(rig, [member("c", 94, moves: [85, 247], machine: [85], item: leftovers),
                                 member("a", 6), member("b", 25, item: scarf)])

        XCTAssertNil(reason)
        XCTAssertEqual(rig.battle.slots.map(\.instanceID), ["c", "a", "b"])
        XCTAssertEqual(rig.battle.moveChoices["c"], MoveChoice(pokemonID: 94, moves: [85, 247], machine: [85]))
        XCTAssertNil(rig.battle.moveChoices["a"])
        XCTAssertEqual(rig.store.state.heldItems, ["c": leftovers, "b": scarf])
        XCTAssertEqual(rig.store.state.inventory[leftovers], 0)
        XCTAssertEqual(rig.store.state.inventory[scarf], 0)

        let party = BattleEntry.party(state: rig.store.state, slots: rig.battle.slots,
                                      moveChoices: rig.battle.moveChoices, rentalSpeciesID: 4)
        XCTAssertEqual(party.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(party[0].moves, [85, 247])
        XCTAssertEqual(party[0].machine, [85])
        XCTAssertEqual(party[0].itemKey, leftovers)
        XCTAssertEqual(party[0].itemName, "먹다남은음식")
        XCTAssertEqual(party[0].heldItem, "leftovers")
        XCTAssertNil(party[1].itemKey)
    }

    func testAnItemTakenOffGoesBackToTheBag() throws {
        let rig = try rig()
        XCTAssertNil(apply(rig, [member("a", 6)]))
        XCTAssertEqual(rig.store.state.heldItems, [:])
        XCTAssertEqual(rig.store.state.inventory[scarf], 1)
        XCTAssertEqual(rig.store.state.inventory[leftovers], 1)
    }

    func testAMemberLeavingTheLineupKeepsItsItem() throws {
        let rig = try rig()
        XCTAssertNil(apply(rig, [member("b", 25)]))
        XCTAssertEqual(rig.store.state.heldItems, ["a": scarf])
    }

    // MARK: Cancelling with nothing changed

    func testAGoneIndividualCancelsAndChangesNothing() throws {
        let rig = try rig()
        let before = rig.store.state
        let reason = apply(rig, [member("a", 6), member("b", 25, item: leftovers), member("released", 94)])
        assertUnchanged(rig, before, reason: reason, expected: RemoteLineup.Reason.gone)
    }

    func testAMissingItemCancelsAndChangesNothing() throws {
        let rig = try rig(inventory: [:])
        let before = rig.store.state
        let reason = apply(rig, [member("a", 6), member("b", 25, item: leftovers)])
        assertUnchanged(rig, before, reason: reason, expected: RemoteLineup.Reason.noItem)
    }

    func testAnItemThePokemonCannotHoldCancels() throws {
        let rig = try rig(inventory: [ItemKind.rareCandy.rawValue: 3])
        XCTAssertEqual(apply(rig, [member("b", 25, item: ItemKind.rareCandy.rawValue)]), RemoteLineup.Reason.noItem)
    }

    func testTwoOfASpeciesCancelWithTheSpeciesClause() throws {
        let rig = try rig()
        let before = rig.store.state
        let reason = apply(rig, [member("b", 25), member("d", 25, item: leftovers)])
        assertUnchanged(rig, before, reason: reason, expected: RemoteLineup.Reason.speciesClause)
    }

    func testTwoHoldersOfOneItemCancelWithTheItemClause() throws {
        let rig = try rig(inventory: [scarf: 1])
        let before = rig.store.state
        let reason = apply(rig, [member("a", 6, item: scarf), member("b", 25, item: scarf)])
        assertUnchanged(rig, before, reason: reason, expected: RemoteLineup.Reason.itemClause)
    }

    func testAnEvolvedIndividualCancels() throws {
        let rig = try rig()
        XCTAssertEqual(apply(rig, [member("b", 26)]), RemoteLineup.Reason.evolved)
    }

    func testAnIndividualInATradeCancels() throws {
        let rig = try rig()
        rig.store.lockForTrade("b")
        XCTAssertEqual(apply(rig, [member("b", 25)]), RemoteLineup.Reason.tradeLocked)
    }

    func testATMMoveWithoutItsTMCancels() throws {
        let rig = try rig(inventory: [leftovers: 1])
        XCTAssertEqual(apply(rig, [member("b", 25, moves: [85], machine: [85])]), RemoteLineup.Reason.noMachine)
    }

    func testAPayloadItCannotReadCancels() throws {
        let rig = try rig()
        let reason = RemoteLineup.apply(Data(#"{"members":[]}"#.utf8), store: rig.store, battleEntry: rig.battle)
        XCTAssertEqual(reason, RemoteLineup.Reason.invalid)
    }

    // MARK: Idempotency

    func testAnOpAppliedBeforeARestartIsNotAppliedAgain() throws {
        let rig = try rig()
        let op = RemoteOp(id: 1, kind: RemoteLineup.kind,
                          payload: payload([member("b", 25, item: scarf), member("a", 6)]))
        rig.store.applyRemoteOps([op], appliers: RemoteOpAppliers.all(battleEntry: rig.battle))
        XCTAssertEqual(rig.store.state.remoteOpResults, [RemoteOpResult(id: 1)])

        let store = try openStore(at: rig.url)
        let battle = BattleEntryStore(defaults: try XCTUnwrap(UserDefaults(suiteName: rig.suite)))
        store.applyRemoteOps([op], appliers: RemoteOpAppliers.all(battleEntry: battle))

        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1)])
        XCTAssertEqual(store.state.heldItems, ["b": scarf])
        XCTAssertEqual(store.state.inventory[scarf], 0)
        XCTAssertEqual(battle.slots.map(\.instanceID), ["b", "a"])
    }

    // MARK: Pool members

    func testThePoolCarriesEachEntrysBattleMemberInTheBotsKeys() throws {
        let rig = try rig()
        let choices = ["d": MoveChoice(pokemonID: 25, moves: [85, 98], machine: [85])]
        let pool = rig.store.tradePool(fightingIDs: [], moveChoices: choices)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: TradePool.encode(pool)) as? [[String: Any]])
        let pikachu = try XCTUnwrap(wire.first { $0["id"] as? String == "d" }?["member"] as? [String: Any])

        XCTAssertEqual(pikachu["pokemon_id"] as? Int, 25)
        XCTAssertEqual(pikachu["moves"] as? [Int], [85, 98])
        XCTAssertEqual(pikachu["machine"] as? [Int], [85])
        let scarfHolder = try XCTUnwrap(wire.first { $0["id"] as? String == "a" }?["member"] as? [String: Any])
        XCTAssertEqual(scarfHolder["item_key"] as? String, scarf)
        XCTAssertEqual(scarfHolder["held_item"] as? String, "choice-scarf")
    }

    func testTheBagMarksWhatAPokemonCanHold() throws {
        let rig = try rig(inventory: [leftovers: 1, ItemKind.rareCandy.rawValue: 2])
        let lines = Dictionary(uniqueKeysWithValues: rig.store.remoteBag.map { ($0.key, $0) })
        XCTAssertEqual(lines[leftovers]?.equip, true)
        XCTAssertEqual(lines[leftovers]?.heldItem, "leftovers")
        XCTAssertNil(lines[ItemKind.rareCandy.rawValue]?.equip)
    }

    // MARK: Helpers

    private struct Rig {
        let store: CompanionStore
        let battle: BattleEntryStore
        let url: URL
        let suite: String
    }

    /// Charizard `a` holds a Choice Scarf; Pikachu `b` and `d`, Gengar `c` hold nothing. The bag has Leftovers and
    /// the Thunderbolt TM unless `inventory` says otherwise.
    private func rig(inventory: [String: Int]? = nil) throws -> Rig {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .ko
        var profile = PokemonProfile.generate(seed: 7, instanceID: "raised")
        profile.level = 42
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: profile)
        state.dex = [entry(6, id: "a"), entry(25, id: "b"), entry(94, id: "c"), entry(25, id: "d")]
        state.heldItems = ["a": scarf]
        state.inventory = inventory ?? [leftovers: 1, thunderbolt: 1]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lineup-\(UUID().uuidString).json")
        paths.append(url)
        try JSONEncoder().encode(state).write(to: url)
        let suite = "lineup-\(UUID().uuidString)"
        suites.append(suite)
        let battle = BattleEntryStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        battle.add("a")
        return Rig(store: try openStore(at: url), battle: battle, url: url, suite: suite)
    }

    private func openStore(at url: URL) throws -> CompanionStore {
        let suite = "lineup-store-\(UUID().uuidString)"
        suites.append(suite)
        return CompanionStore(provider: LineupProvider(), fileURL: url, rng: SeededRNG(seed: 1),
                              dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func entry(_ species: Int, id: String) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 7, instanceID: id)
        profile.level = 30
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common, caughtAt: nil,
                             isShiny: false, profile: profile, names: [species: ["ko": id, "en": id]])
        entry.id = id
        return entry
    }

    private func member(_ id: String, _ pokemonID: Int, moves: [Int] = [], machine: [Int] = [],
                        item: String? = nil) -> [String: Any] {
        ["id": id, "pokemon_id": pokemonID, "name": id, "moves": moves, "machine": machine, "item": item ?? NSNull()]
    }

    private func payload(_ members: [[String: Any]]) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["members": members])) ?? Data()
    }

    private func apply(_ rig: Rig, _ members: [[String: Any]]) -> String? {
        RemoteLineup.apply(payload(members), store: rig.store, battleEntry: rig.battle)
    }

    private func assertUnchanged(_ rig: Rig, _ before: CompanionState, reason: String?, expected: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(reason, expected, file: file, line: line)
        XCTAssertEqual(rig.store.state.heldItems, before.heldItems, file: file, line: line)
        XCTAssertEqual(rig.store.state.inventory, before.inventory, file: file, line: line)
        XCTAssertEqual(rig.battle.slots.map(\.instanceID), ["a"], file: file, line: line)
        XCTAssertTrue(rig.battle.moveChoices.isEmpty, file: file, line: line)
    }
}
