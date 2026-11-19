import XCTest
@testable import PokeTokenBar

private struct StoredLineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [
            EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                rarity: .common,
                names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"], 6: ["en": "Charizard"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// A shop or scout egg sends the line Pokémon to the Box as it is, and raising it again picks up where it stopped.
@MainActor
final class EggKeepsPetTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    nonisolated(unsafe) private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let lineID = "line"
    private static let graduateID = "grad"

    private func lineState() -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .en
        state.claimedTodayTokensByProvider = ["test": 0]
        state.lastDate = "d1"
        state.usedSinceInstall = 90_000_000_000
        var profile = PokemonProfile.generate(seed: 4, instanceID: Self.lineID)
        profile.level = 20
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 777, rarity: .common,
                                totalForms: 3, profile: profile)
        state.active!.evolution.spentBaseline = 10
        state.spentTokens = 100
        state.heldItems[Self.lineID] = ItemKind.focusSash.rawValue
        var gradProfile = PokemonProfile.generate(seed: 11, instanceID: Self.graduateID)
        gradProfile.level = 50
        state.dex = [DexEntry(id: Self.graduateID, baseID: 25, finalID: 25, chainOrder: [25], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_000), isShiny: false, nature: .adamant,
                              profile: gradProfile, names: [25: ["en": "Pikachu"]])]
        state.collectedFinals = ["25:25"]
        return state
    }

    private func makeStore(_ state: CompanionState) throws -> CompanionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("egg-keeps-pet-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "egg-keeps-pet-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return CompanionStore(provider: StoredLineProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try XCTUnwrap(String(data: encoder.encode(value), encoding: .utf8))
    }

    /// Buys a plain egg and hatches it, so a new line is being raised and the old one waits in the Box.
    private func storeTheLineAndHatch(_ store: CompanionStore) async throws {
        XCTAssertTrue(store.buyEgg(nil))
        await store.hatch(baseID: 4)
        XCTAssertNotNil(store.state.active)
    }

    // MARK: storing

    func testBuyingAnEggSendsTheLineToTheBoxWithItsProgress() throws {
        let store = try makeStore(lineState())
        let before = try json(store.state.active)
        let collected = store.state.collectedFinals
        XCTAssertTrue(store.buyEgg(nil))

        XCTAssertTrue(store.isEgg)
        XCTAssertEqual(try json(store.state.storedLines[Self.lineID]?.mon), before)
        XCTAssertEqual(store.state.storedLines[Self.lineID]?.spentAtStore, store.state.spentTokens)
        XCTAssertEqual(store.state.heldItems[Self.lineID], ItemKind.focusSash.rawValue)
        XCTAssertEqual(store.state.collectedFinals, collected)
        let record = try XCTUnwrap(store.state.dex.first { $0.id == Self.lineID })
        XCTAssertTrue(record.isReleased)
        XCTAssertEqual(record.chainOrder, [4, 5])

        let individual = try XCTUnwrap(store.boxIndividual(id: Self.lineID))
        XCTAssertEqual(individual.role, .stored)
        XCTAssertEqual(individual.speciesID, 5)
        XCTAssertEqual(individual.level, 20)
        XCTAssertEqual(store.boxID(of: record), Self.lineID)
    }

    func testAScoutPickSendsTheLineToTheBoxToo() throws {
        var state = lineState()
        let pool = ScoutPool.region(.kanto)
        state.inventory[pool.inventoryKey] = 1
        state.scoutDraws[pool.key] = Array(1...10)
        let store = try makeStore(state)
        let before = try json(store.state.active)
        XCTAssertTrue(store.pickScout(pool, speciesID: 7))
        XCTAssertEqual(store.state.pendingHatchID, 7)
        XCTAssertEqual(try json(store.state.storedLines[Self.lineID]?.mon), before)
        XCTAssertEqual(store.boxIndividual(id: Self.lineID)?.role, .stored)
    }

    func testAStoredLineCannotBeTradedOrFought() throws {
        let store = try makeStore(lineState())
        XCTAssertTrue(store.buyEgg(nil))
        let individual = try XCTUnwrap(store.boxIndividual(id: Self.lineID))
        XCTAssertEqual(store.tradeRefusal(for: individual.entry, fightingIDs: []), .unavailable)
        XCTAssertFalse(store.isTradableNow(individual, fightingIDs: []))
        XCTAssertNil(store.battleCandidate(for: individual.entry))
    }

    // MARK: raising again

    func testRaisingAStoredLineAgainResumesItExactlyAndStoresTheNewOne() async throws {
        let store = try makeStore(lineState())
        let before = try json(store.state.active)
        try await storeTheLineAndHatch(store)
        let hatchedID = try XCTUnwrap(store.state.active?.profile?.instanceID)

        XCTAssertTrue(store.canRaise(entryID: Self.lineID))
        XCTAssertTrue(store.raise(entryID: Self.lineID))
        XCTAssertEqual(try json(store.state.active), before)
        XCTAssertNil(store.state.storedLines[Self.lineID])
        XCTAssertFalse(store.state.dex.contains { $0.id == Self.lineID })
        XCTAssertEqual(store.boxIndividual(id: Self.lineID)?.role, .raising)
        XCTAssertEqual(store.boxIndividual(id: hatchedID)?.role, .stored)
    }

    func testSpendingWhileStoredDoesNotCountTowardEvolution() async throws {
        let store = try makeStore(lineState())
        try await storeTheLineAndHatch(store)
        let spentAtStore = try XCTUnwrap(store.state.storedLines[Self.lineID]?.spentAtStore)
        XCTAssertTrue(store.buy(.rareCandy))
        let spentWhileStored = store.state.spentTokens - spentAtStore
        XCTAssertGreaterThan(spentWhileStored, 0)
        store.raise(entryID: Self.lineID)
        XCTAssertEqual(store.state.active?.evolution.spentBaseline, 10 + spentWhileStored)
    }

    func testBattlesWhileStoredDoNotCountTowardEvolution() async throws {
        var state = lineState()
        state.active!.evolution.battleCursor = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore(state)
        try await storeTheLineAndHatch(store)
        now = Date(timeIntervalSince1970: 1_900_000_000)
        store.raise(entryID: Self.lineID)
        XCTAssertEqual(store.state.active?.evolution.battleCursor, now)
    }

    func testRaisingAStoredLineWaitsForTheEggAndKeepsIt() throws {
        let store = try makeStore(lineState())
        XCTAssertTrue(store.buyEgg(.rare))
        XCTAssertFalse(store.canRaise(entryID: Self.lineID))
        XCTAssertFalse(store.raise(entryID: Self.lineID))
        XCTAssertEqual(store.state.eggTier, .rare)
        XCTAssertNotNil(store.state.storedLines[Self.lineID])
    }

    func testRaisingAStoredLineWhileAGraduateIsRaisedResumesTheParkedLineFirst() async throws {
        let store = try makeStore(lineState())
        try await storeTheLineAndHatch(store)
        let hatched = try XCTUnwrap(store.state.active)
        let hatchedID = try XCTUnwrap(hatched.profile?.instanceID)
        XCTAssertTrue(store.raise(entryID: Self.graduateID))
        XCTAssertTrue(store.isLineParked)

        XCTAssertTrue(store.raise(entryID: Self.lineID))
        XCTAssertNil(store.state.raisedEntryID)
        XCTAssertNil(store.state.parkedSpentTokens)
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.lineID)
        let stored = try XCTUnwrap(store.state.storedLines[hatchedID]?.mon)
        XCTAssertEqual(stored.usedAtStage, hatched.usedAtStage)
        XCTAssertEqual(stored.pathIDs, hatched.pathIDs)
        XCTAssertEqual(stored.evolution.spentBaseline, hatched.evolution.spentBaseline)
        XCTAssertEqual(store.boxIndividual(id: Self.graduateID)?.role, .graduated)
    }

    func testStoringTheSameLineTwiceLeavesOnePokedexRecordForIt() async throws {
        let store = try makeStore(lineState())
        try await storeTheLineAndHatch(store)
        store.raise(entryID: Self.lineID)
        XCTAssertTrue(store.buyEgg(nil))
        XCTAssertEqual(store.state.dex.filter { $0.id == Self.lineID }.count, 1)
        let ids = store.boxIndividuals.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    // MARK: save

    func testAnOldSaveLoadsAndACorruptStoredLineDropsOnlyItself() throws {
        var state = lineState()
        state.storedLines = ["a": StoredLine(mon: state.active!, spentAtStore: 5),
                             "b": StoredLine(mon: state.active!, spentAtStore: 6)]
        let data = try JSONEncoder().encode(state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: data).storedLines["b"]?.spentAtStore, 6)

        var stored = try XCTUnwrap(json["storedLines"] as? [String: Any])
        stored["a"] = ["mon": 5]
        json["storedLines"] = stored
        let corrupt = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(Array(corrupt.storedLines.keys), ["b"])

        json["storedLines"] = nil
        let old = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.storedLines.isEmpty)
        XCTAssertNotNil(old.active)
    }

    func testSanitizeClampsAStoredLineLikeTheActiveOne() throws {
        var state = lineState()
        var mon = try XCTUnwrap(state.active)
        mon.stageIndex = 40
        mon.usedAtStage = -9
        state.storedLines = ["a": StoredLine(mon: mon, spentAtStore: -3)]
        let clean = try XCTUnwrap(SaveTransfer.sanitized(state).storedLines["a"])
        XCTAssertEqual(clean.mon.stageIndex, 2)
        XCTAssertEqual(clean.mon.usedAtStage, 0)
        XCTAssertEqual(clean.spentAtStore, 0)
    }

    // MARK: copy

    func testTheEggCopySaysTheBoxNotRelease() {
        XCTAssertTrue(L(.ko).eggDescription(nil).contains("박스"))
        XCTAssertTrue(L(.en).eggDescription(.rare).contains("Box"))
        XCTAssertTrue(L(.en).eggConfirm("Charmeleon", "Rare Egg").contains("Box"))
        XCTAssertTrue(L(.ko).scoutPickConfirm("리자드", "꼬부기").contains("박스"))
    }
}
