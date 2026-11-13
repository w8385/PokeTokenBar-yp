import XCTest
@testable import PokeTokenBar

private struct OneLineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.badServerResponse) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

private final class MutableClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

/// A Pokémon in an open trade carries its held item to the other player, so that item must not be able to leave
/// the sender by any other road before the trade ends.
@MainActor
final class TradeItemLockTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func makeStore(clock: @escaping () -> Date = Date.init,
                           _ configure: (inout CompanionState) -> Void) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .ko
        configure(&state)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-lock-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "trade-lock-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: OneLineProvider(), clock: clock, fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func entry(id: String, base: Int = 95, caught: TimeInterval = 100) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 11, instanceID: id)
        profile.level = 50
        return DexEntry(id: id, baseID: base, finalID: base, chainOrder: [base], rarity: .common,
                        caughtAt: Date(timeIntervalSince1970: caught), isShiny: false, nature: .adamant,
                        profile: profile, names: [base: ["ko": "x", "en": "x"]], originalTrainer: nil)
    }

    /// What the bot sends: the other side's entry and, unless `reportItem` is nil, the item that left with `give`.
    private func delivery(give: String, receiving wire: DexEntry, gave: String?? = .some(nil)) throws -> TradeDelivery {
        let item = TradePoolEntry(id: wire.id, pokemonID: wire.finalID, level: 50, shiny: false, name: "n", entry: wire)
        var json: [String: Any] = [
            "trade_id": "t-\(UUID())", "give_id": give, "from_name": "Sam",
            "receive": try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)),
        ]
        if let gave { json["give_held_item"] = gave.map { $0 as Any } ?? NSNull() }
        let body = try JSONSerialization.data(withJSONObject: ["ok": true, "trades": ["deliveries": [json]]])
        return try XCTUnwrap(TradeSyncReply.decode(body).deliveries.first)
    }

    private let coat = ItemKind.metalCoat

    // MARK: the lock

    func testALockedIndividualKeepsItsItemSlotAndUnlockingFreesIt() throws {
        let store = try makeStore { state in
            state.dex = [entry(id: "mine")]
            state.heldItems["mine"] = coat.rawValue
            state.inventory[ItemKind.kingsRock.rawValue] = 1
        }
        store.setTradeLocked(["mine"])
        XCTAssertFalse(store.unequip(from: "mine"))
        XCTAssertFalse(store.equip(.kingsRock, to: "mine"))
        XCTAssertEqual(store.heldItem(of: "mine"), coat)
        XCTAssertEqual(store.itemCount(coat), 0)
        XCTAssertEqual(store.itemCount(.kingsRock), 1)

        store.setTradeLocked([])
        XCTAssertTrue(store.unequip(from: "mine"))
        XCTAssertEqual(store.itemCount(coat), 1)
    }

    func testAnUnlistedIndividualIsNotLockedAndOnlyTheListedOneIs() throws {
        let store = try makeStore { state in
            state.dex = [entry(id: "listed"), entry(id: "other")]
            state.heldItems["other"] = coat.rawValue
        }
        store.setTradeLocked(["listed"])
        XCTAssertTrue(store.unequip(from: "other"))
    }

    func testAnOfferJustSentLocksBeforeTheNextSyncAndALapsedBotLetsGoAfterTheOfferLifetime() throws {
        let clock = MutableClock()
        let store = try makeStore(clock: { clock.now }) { state in
            state.dex = [entry(id: "mine")]
            state.heldItems["mine"] = coat.rawValue
        }
        store.lockForTrade("mine")
        XCTAssertTrue(store.isTradeLocked("mine"))
        clock.now.addTimeInterval(23 * 3600)
        XCTAssertTrue(store.isTradeLocked("mine"))
        clock.now.addTimeInterval(2 * 3600)
        XCTAssertFalse(store.isTradeLocked("mine"))
        XCTAssertTrue(store.unequip(from: "mine"))
    }

    func testTheLinkingCordCannotUseUpTheItemOfAListedIndividual() async throws {
        let store = try makeStore { state in
            state.dex = [entry(id: "mine")]
            state.heldItems["mine"] = coat.rawValue
            state.inventory[ItemKind.linkingCord.rawValue] = 1
        }
        store.lockForTrade("mine")
        let result = await store.useLinkingCord(on: "mine")
        XCTAssertEqual(result, .listed)
        XCTAssertEqual(store.heldItem(of: "mine"), coat)
        XCTAssertEqual(store.itemCount(.linkingCord), 1)
    }

    // MARK: settling the item the trade carried

    /// The reported defect: list with the item on, take it off, complete. Exactly one copy must remain.
    func testItemTakenOffAfterListingExistsOnceWhenTheBotDroppedItFromTheDelivery() throws {
        let sender = try makeStore { state in
            state.dex = [entry(id: "mine")]
            state.heldItems["mine"] = coat.rawValue
        }
        let listed = TradePool.build(state: sender.state, fightingIDs: [], name: { _ in "n" })
        XCTAssertEqual(listed.first?.entry.tradeHeldItem, coat.rawValue)
        sender.setTradeLocked([])
        XCTAssertTrue(sender.unequip(from: "mine"))

        let receiver = try makeStore { $0.dex = [] }
        var wire = try XCTUnwrap(listed.first).entry
        wire.tradeHeldItem = nil
        receiver.applyTrades([try delivery(give: "x", receiving: wire)])
        sender.applyTrades([try delivery(give: "mine", receiving: entry(id: "back", base: 25), gave: .some(nil))])

        let senderCopies = sender.itemCount(coat) + (sender.heldItem(of: "mine") == coat ? 1 : 0)
        let receiverCopies = receiver.itemCount(coat) + (receiver.state.dex.first?.tradeHeldItem == coat.rawValue ? 1 : 0)
        XCTAssertEqual(senderCopies + receiverCopies, 1)
    }

    /// The race the bot's refresh cannot see: unequipped, but the pool with the item still went out.
    func testItemTakenOffBeforeTheBotSawItIsRemovedFromTheBagOfTheSender() throws {
        let sender = try makeStore { state in
            state.dex = [entry(id: "mine")]
            state.inventory[coat.rawValue] = 1
        }
        sender.applyTrades([try delivery(give: "mine", receiving: entry(id: "back", base: 25), gave: .some(coat.rawValue))])
        XCTAssertEqual(sender.itemCount(coat), 0)
        XCTAssertNil(sender.heldItem(of: "mine"))
    }

    func testItemStillHeldLeavesWithThePokemonAndNothingIsTakenFromTheBag() throws {
        let sender = try makeStore { state in
            state.dex = [entry(id: "mine")]
            state.heldItems["mine"] = coat.rawValue
            state.inventory[coat.rawValue] = 1
        }
        sender.applyTrades([try delivery(give: "mine", receiving: entry(id: "back", base: 25), gave: .some(coat.rawValue))])
        XCTAssertNil(sender.heldItem(of: "mine"))
        XCTAssertEqual(sender.itemCount(coat), 1)
    }

    func testASwappedItemIsReturnedAndOnlyTheTravelledOneIsTaken() throws {
        let sender = try makeStore { state in
            state.dex = [entry(id: "mine")]
            state.heldItems["mine"] = ItemKind.kingsRock.rawValue
            state.inventory[coat.rawValue] = 1
        }
        sender.applyTrades([try delivery(give: "mine", receiving: entry(id: "back", base: 25), gave: .some(coat.rawValue))])
        XCTAssertEqual(sender.itemCount(coat), 0)
        XCTAssertEqual(sender.itemCount(.kingsRock), 1)
    }

    func testATravelledItemAlreadyUsedElsewhereLeavesTheBagAtZero() throws {
        let sender = try makeStore { state in
            state.dex = [entry(id: "mine"), entry(id: "other")]
            state.heldItems["other"] = coat.rawValue
        }
        sender.applyTrades([try delivery(give: "mine", receiving: entry(id: "back", base: 25), gave: .some(coat.rawValue))])
        XCTAssertEqual(sender.itemCount(coat), 0)
        XCTAssertEqual(sender.heldItem(of: "other"), coat)
    }

    func testATradeItemPutOnAfterTheSnapshotIsKeptNotDestroyed() throws {
        let sender = try makeStore { state in
            state.dex = [entry(id: "mine")]
            state.heldItems["mine"] = coat.rawValue
        }
        sender.applyTrades([try delivery(give: "mine", receiving: entry(id: "back", base: 25), gave: .some(nil))])
        XCTAssertEqual(sender.itemCount(coat), 1)
    }

    func testAnOlderBotThatDoesNotReportTheItemKeepsTheOldBehaviour() throws {
        let sender = try makeStore { state in
            state.dex = [entry(id: "mine")]
            state.heldItems["mine"] = coat.rawValue
        }
        let old = try delivery(give: "mine", receiving: entry(id: "back", base: 25), gave: nil)
        XCTAssertFalse(old.reportsGiveHeldItem)
        sender.applyTrades([old])
        XCTAssertNil(sender.heldItem(of: "mine"))
        XCTAssertEqual(sender.itemCount(coat), 0)
    }

    func testATradedAwayFriendLeavesTheFriendSlots() throws {
        let sender = try makeStore { state in
            state.dex = [entry(id: "mine"), entry(id: "pal")]
            state.friendEntryIDs = ["mine", "pal"]
        }
        sender.applyTrades([try delivery(give: "mine", receiving: entry(id: "back", base: 25))])
        XCTAssertEqual(sender.state.friendEntryIDs, ["pal"])
    }

    // MARK: wire

    func testReplyCarriesLockedIDsAndAnOlderBotMeansNone() throws {
        let with = Data(#"{"ok":true,"trades":{"deliveries":[],"locked_ids":["a","b"]}}"#.utf8)
        XCTAssertEqual(TradeSyncReply.decode(with).lockedIDs, ["a", "b"])
        let without = Data(#"{"ok":true,"trades":{"deliveries":[]}}"#.utf8)
        XCTAssertTrue(TradeSyncReply.decode(without).lockedIDs.isEmpty)
    }

    func testThePoolKeyTheBotRewritesIsTheKeyTheAppEncodes() throws {
        var wire = entry(id: "e")
        wire.tradeHeldItem = coat.rawValue
        let item = TradePoolEntry(id: "e", pokemonID: 95, level: 50, shiny: false, name: "n", entry: wire)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        let inner = try XCTUnwrap(object["entry"] as? [String: Any])
        XCTAssertEqual(inner["tradeHeldItem"] as? String, coat.rawValue)
    }

    // MARK: uploader

    private func uploader(counter: Counter, locked: Counter, body: String, offerStatus: Int = 200) throws -> PartyUploader {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-lock-up-\(UUID())")
        let tokenStore = PartyTokenStore(fileURL: dir.appendingPathComponent("token"))
        try tokenStore.save("secret-token")
        let suite = "trade-lock-up-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set("http://127.0.0.1:1", forKey: PartyUploader.serverURLDefaultsKey)
        let trades = TradeSync(pool: { [] }, apply: { $0.map(\.tradeID) },
                               setLocked: { ids in locked.add("set:" + ids.sorted().joined(separator: ",")) },
                               lock: { locked.add("lock:" + $0) })
        return PartyUploader(tokenStore: tokenStore, defaults: defaults, appVersion: "t",
                             exchange: { _ in (Data(), 200) },
                             fetch: { request in
                                 counter.add("\(request.httpMethod ?? "GET") \(request.url?.path ?? "")")
                                 if request.url?.path == "/v1/trades", request.httpMethod == "POST" {
                                     return (Data(), offerStatus)
                                 }
                                 return (Data(body.utf8), 200)
                             },
                             partySource: { [PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)] },
                             trades: trades)
    }

    func testEverySyncReplacesTheLockedSetEvenWithNoDeliveries() async throws {
        let calls = Counter(), locked = Counter()
        let up = try uploader(counter: calls, locked: locked,
                              body: #"{"ok":true,"trades":{"deliveries":[],"locked_ids":["a"]}}"#)
        await up.tick()
        XCTAssertEqual(locked.all, ["set:a"])
    }

    func testASentOfferLocksItsIndividualAtOnce() async throws {
        let calls = Counter(), locked = Counter()
        let up = try uploader(counter: calls, locked: locked, body: #"{"ok":true}"#)
        let result = await up.proposeTrade(to: "c", give: "mine")
        XCTAssertEqual(result, .sent)
        XCTAssertEqual(locked.all, ["lock:mine"])
    }

    func testARefusedOfferLocksNothing() async throws {
        let calls = Counter(), locked = Counter()
        let up = try uploader(counter: calls, locked: locked, body: #"{"ok":true}"#, offerStatus: 400)
        _ = await up.proposeTrade(to: "c", give: "mine")
        XCTAssertTrue(locked.all.isEmpty)
    }
}
