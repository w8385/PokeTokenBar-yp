import XCTest
@testable import PokeTokenBar

private struct NoLines: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class TradePoolCapacityTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    func testEveryPokemonOfA300PokemonBoxGoesInThePoolUnderTheBotsBodyLimit() throws {
        var state = CompanionState()
        state.dex = box(300)
        let pool = TradePool.build(state: state, fightingIDs: [], name: { _ in "이브이" })
        let party = [PartyBuilder.member(speciesID: 133, form: nil, shiny: false, profile: state.dex[0].profile)]
        let body = try PartyPayload(appVersion: "3.0.0", party: party).encoded(tradePool: pool)

        XCTAssertEqual(pool.count, 300)
        XCTAssertEqual(pool.last?.id, "box-0000")
        XCTAssertGreaterThan(body.count, 64 * 1024)
        XCTAssertLessThanOrEqual(body.count, try botConstant("MAX_BODY_BYTES", in: "upload_server.py"))
    }

    func testTheBotKeepsEveryEntryAndByteTheAppCanSend() throws {
        XCTAssertGreaterThanOrEqual(try botConstant("MAX_POOL", in: "trades.py"), TradePool.maxEntries)
        XCTAssertGreaterThanOrEqual(try botConstant("MAX_ENTRY_BYTES", in: "trades.py"), TradePool.maxEntryBytes)
        XCTAssertGreaterThanOrEqual(try botConstant("MAX_BODY_BYTES", in: "upload_server.py"),
                                    TradePool.maxBytes + 64 * 1024)
    }

    func testOnlyPokemonInThePoolOfferThePostButtonAndTheRestSayWhy() throws {
        let store = try makeStore { $0.dex = self.box(TradePool.maxEntries + 1) }
        let oldest = try XCTUnwrap(store.state.dex.first)
        let newest = try XCTUnwrap(store.state.dex.last)
        let sent = Set(store.tradePool(fightingIDs: []).map(\.id))

        XCTAssertEqual(store.tradeRefusal(for: oldest, fightingIDs: []), .poolFull)
        XCTAssertNil(store.tradeRefusal(for: newest, fightingIDs: []))
        XCTAssertFalse(MiracleTradeModel.showsPostButton(
            availability: .available, offer: nil, refusal: store.tradeRefusal(for: oldest, fightingIDs: [])))
        XCTAssertEqual(sent.count, TradePool.maxEntries)
        XCTAssertFalse(sent.contains(oldest.id))
        XCTAssertEqual(Set(store.tradableEntries(fightingIDs: []).map(\.id)), sent)
        XCTAssertEqual(Set(store.filteredBoxIndividuals(tradableOnly: true).map(\.id)), sent)
        XCTAssertTrue(store.l.tradeRefusalText(.poolFull).contains(String(TradePool.maxEntries)))
    }

    func testTheLargestRecordASaveCanHoldFitsThePerEntryCap() throws {
        let store = try makeStore { state in
            let id = String(repeating: "i", count: 64)
            var entry = self.box(1)[0]
            entry.id = id
            entry.chainOrder = [133, 133, 133]
            entry.nature = .naughty
            entry.prayers = PrayerRecord(count: Int.max)
            entry.profile?.instanceID = id
            entry.profile?.seed = .max
            entry.profile?.growthTokens = .max
            entry.profile?.abilityName = String(repeating: "a", count: 40)
            entry.profile?.mirrorHerb = true
            entry.profile?.moves = (1...9).map {
                PokemonKnownMove(name: String(repeating: "m", count: 200) + "\($0)", learnedAtLevel: 100)
            }
            state.dex = [entry]
            state.heldItems[id] = ItemKind.metalCoat.rawValue
        }
        let item = try XCTUnwrap(TradePool.build(state: store.state, fightingIDs: [],
                                                 name: { _ in String(repeating: "가", count: 60) }).first)

        XCTAssertNil(store.tradeRefusal(for: store.state.dex[0], fightingIDs: []))
        XCTAssertLessThanOrEqual(try TradePool.encode([item]).count - 2, TradePool.maxEntryBytes)
    }

    func testTheWireEntryDropsWhatTheReceiverReplacesAndStillArrives() throws {
        var state = CompanionState()
        state.dex = box(1)
        state.dex[0].originalTrainer = "Sam"
        let item = try XCTUnwrap(TradePool.build(state: state, fightingIDs: [], name: { _ in "n" }).first)
        let decoded = try JSONDecoder().decode(TradePoolEntry.self, from: TradePool.encode([item]).dropFirst().dropLast()).entry

        XCTAssertNil(item.entry.caughtAt)
        XCTAssertNil(item.entry.originalTrainer)
        XCTAssertEqual(item.entry.profile?.instanceID, "")
        XCTAssertNotNil(decoded.profile, "an older app must still decode the profile")
        let arrived = try XCTUnwrap(CompanionStore.receivedEntry(item.entry, from: "Kim", now: Date(timeIntervalSince1970: 9)))
        XCTAssertEqual(arrived.profile?.instanceID, arrived.id)
        XCTAssertEqual(arrived.profile?.ivs, state.dex[0].profile?.ivs)
        XCTAssertEqual(arrived.originalTrainer, "Kim")
    }

    // MARK: Helpers

    private func box(_ count: Int) -> [DexEntry] {
        (0..<count).map { index in
            let id = String(format: "box-%04d", index)
            var profile = PokemonProfile.generate(seed: UInt64(index + 1), instanceID: id)
            profile.level = 1 + index % 100
            profile.moves = ["quick-attack", "bite", "double-edge", "last-resort"]
                .enumerated().map { PokemonKnownMove(name: $1, learnedAtLevel: 40 + $0) }
            profile.abilityName = "adaptability"
            return DexEntry(id: id, baseID: 133, finalID: 133, chainOrder: [133], rarity: .rare,
                            caughtAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index)), nature: .jolly,
                            profile: profile)
        }
    }

    /// An integer constant of `bot/ypoke/<file>`, written as a product like `5 * 1024 * 1024`.
    private func botConstant(_ name: String, in file: String) throws -> Int {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("bot/ypoke/\(file)")
        let line = try XCTUnwrap(try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").first { $0.hasPrefix("\(name) = ") })
        return try line.dropFirst(name.count + 3).split(separator: "*")
            .map { try XCTUnwrap(Int($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: ""))) }
            .reduce(1, *)
    }

    private func makeStore(_ configure: (inout CompanionState) -> Void) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .ko
        configure(&state)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-pool-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "trade-pool-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: NoLines(), fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }
}
