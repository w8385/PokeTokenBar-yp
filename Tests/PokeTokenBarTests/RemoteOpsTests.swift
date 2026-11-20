import Foundation
import XCTest
@testable import PokeTokenBar

private final class RemoteOpsBot: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _uploads: [[String: Any]] = []
    private var _acks: [[String: Any]] = []
    var opsStatus = 200
    var ops = #"[]"#
    var ackStatus = 200

    var calls: [String] { lock.withLock { _calls } }
    var uploads: [[String: Any]] { lock.withLock { _uploads } }
    var acks: [[String: Any]] { lock.withLock { _acks } }

    func reply(_ request: URLRequest) -> (Data, Int) {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return lock.withLock {
            _calls.append("\(method) \(path)")
            switch (method, path) {
            case ("GET", "/v1/ops"): return (Data(#"{"ok":true,"ops":\#(ops)}"#.utf8), opsStatus)
            case ("POST", "/v1/ops/ack"):
                _acks.append(body ?? [:])
                return (Data(#"{"ok":true}"#.utf8), ackStatus)
            case ("POST", "/v1/party"):
                _uploads.append(body ?? [:])
                return (Data(#"{"ok":true}"#.utf8), 200)
            default: return (Data("{}".utf8), 404)
            }
        }
    }
}

private struct NoLines: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Counts every apply, so a second apply of the same op shows; `test_gone` is always cancelled.
@MainActor
private final class Applied {
    var count = 0

    var appliers: [String: RemoteOpApplier] {
        ["test_count": { [self] _, _ in
            count += 1
            return nil
        },
         "test_gone": { _, _ in "target_gone" }]
    }
}

@MainActor
final class RemoteOpsTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []

    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    // MARK: Sync order

    func testOpsAreFetchedAppliedUploadedThenAcknowledged() async throws {
        let store = try makeStore(at: saveURL())
        let applied = Applied()
        let bot = RemoteOpsBot()
        bot.ops = "[\(op(1, "test_count")), \(op(2, "test_gone")), \(op(3, "nope"))]"

        try await uploader(bot, sync: sync(store, applied)).tick()

        XCTAssertEqual(bot.calls, ["GET /v1/ops", "POST /v1/party", "POST /v1/ops/ack"])
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(bot.uploads.first?["applied_op_id"] as? Int, 3)
        XCTAssertEqual(bot.uploads.first?["remote_ops"] as? Int, 1)
        let ack = try XCTUnwrap(bot.acks.first)
        XCTAssertEqual(ack["applied"] as? [Int], [1])
        let cancelled = try XCTUnwrap(ack["cancelled"] as? [[String: Any]])
        XCTAssertEqual(cancelled.map { $0["id"] as? Int }, [2, 3])
        XCTAssertEqual(cancelled.map { $0["reason"] as? String }, ["target_gone", RemoteOpReason.unsupported])
        XCTAssertEqual(store.state.remoteOpResults, [])
    }

    func testAnUnknownKindIsCancelledAsUnsupportedAndTheRestStillApply() throws {
        let store = try makeStore(at: saveURL())
        let applied = Applied()
        store.applyRemoteOps([RemoteOp(id: 2, kind: "test_count", payload: Data()),
                              RemoteOp(id: 1, kind: "shop_buy_from_the_future", payload: Data())],
                             appliers: applied.appliers)

        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1, reason: RemoteOpReason.unsupported),
                                                     RemoteOpResult(id: 2)])
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(store.state.remoteOpsLastID, 2)
    }

    func testTheShippedRegistryCancelsEveryKindAsUnsupported() throws {
        let store = try makeStore(at: saveURL())
        store.applyRemoteOps([RemoteOp(id: 1, kind: "test_count", payload: Data())])
        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1, reason: RemoteOpReason.unsupported)])
    }

    func testARefusedAckKeepsTheResultsForTheNextSync() async throws {
        let store = try makeStore(at: saveURL())
        let applied = Applied()
        let bot = RemoteOpsBot()
        bot.ops = "[\(op(1, "test_count"))]"
        bot.ackStatus = 500
        let uploader = try uploader(bot, sync: sync(store, applied))

        await uploader.tick()
        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1)])

        bot.ackStatus = 200
        await uploader.tick()
        XCTAssertEqual(bot.acks.count, 2)
        XCTAssertEqual(store.state.remoteOpResults, [])
        XCTAssertEqual(applied.count, 1)
    }

    func testNothingIsAcknowledgedBeforeAnUploadCarriesIt() async throws {
        let store = try makeStore(at: saveURL())
        let bot = RemoteOpsBot()
        bot.ops = "[\(op(1, "test_count"))]"
        let uploader = try uploader(bot, sync: sync(store, Applied()), party: [])

        await uploader.tick()

        XCTAssertEqual(bot.calls, ["GET /v1/ops"])
        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1)])
    }

    // MARK: Idempotency

    func testAnOpAppliedBeforeARestartIsNotAppliedAgainAndItsResultIsAcknowledged() async throws {
        let url = saveURL()
        let applied = Applied()
        let bot = RemoteOpsBot()
        bot.ops = "[\(op(1, "test_count")), \(op(2, "test_gone"))]"
        bot.ackStatus = 500
        let first = try makeStore(at: url)
        try await uploader(bot, sync: sync(first, applied)).tick()
        XCTAssertEqual(applied.count, 1)

        let restarted = try openStore(at: url)
        XCTAssertEqual(restarted.state.remoteOpsLastID, 2)
        bot.ackStatus = 200
        try await uploader(bot, sync: sync(restarted, applied)).tick()

        XCTAssertEqual(applied.count, 1)
        let ack = try XCTUnwrap(bot.acks.last)
        XCTAssertEqual(ack["applied"] as? [Int], [1])
        XCTAssertEqual((ack["cancelled"] as? [[String: Any]])?.first?["reason"] as? String, "target_gone")
        XCTAssertEqual(try openStore(at: url).state.remoteOpResults, [])
    }

    func testAnOldSaveDecodesWithNoRemoteOps() throws {
        let data = try JSONEncoder().encode(CompanionState())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "remoteOpsLastID"))
        XCTAssertNotNil(object.removeValue(forKey: "remoteOpResults"))
        let state = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(state.remoteOpsLastID, 0)
        XCTAssertEqual(state.remoteOpResults, [])
    }

    // MARK: Old bots and apps

    func testABotWithoutOpsIsLeftAloneUntilTheServerChanges() async throws {
        let store = try makeStore(at: saveURL())
        let bot = RemoteOpsBot()
        bot.opsStatus = 404
        let uploader = try uploader(bot, sync: sync(store, Applied()))
        let start = Date(timeIntervalSince1970: 5_000)

        await uploader.tick(now: start)
        await uploader.tick(now: start.addingTimeInterval(600))
        XCTAssertEqual(bot.calls.filter { $0 == "GET /v1/ops" }.count, 1)
        XCTAssertEqual(bot.uploads.count, 2)
        XCTAssertTrue(bot.acks.isEmpty)

        uploader.serverURL = "http://example.local:8791"
        await uploader.tick(now: start.addingTimeInterval(700))
        XCTAssertEqual(bot.calls.filter { $0 == "GET /v1/ops" }.count, 2)
    }

    func testAnUploaderWithoutRemoteOpsSendsNoneOfItsFields() async throws {
        let bot = RemoteOpsBot()
        try await uploader(bot, sync: nil).tick()

        XCTAssertFalse(bot.calls.contains("GET /v1/ops"))
        let upload = try XCTUnwrap(bot.uploads.first)
        for key in ["remote_ops", "applied_op_id", "wallet", "bag", "shop"] { XCTAssertNil(upload[key], key) }
    }

    // MARK: Upload fields

    func testTheRemoteFieldsEncodeWithTheBotsKeysAndInventoryKeysVerbatim() throws {
        let store = try makeStore(at: saveURL()) { state in
            state.inventory[ItemKind.rareCandy.rawValue] = 3
            state.inventory[MegaStone.all[0].inventoryKey] = 1
            state.inventory[MachineMove.inventoryKey(85)] = 1
        }
        let party = [PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)]
        let data = try PartyPayload(appVersion: "t", party: party, dex: nil, appliedOpID: 7,
                                    snapshot: store.remoteSnapshot).encoded(wallet: 1_234)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["remote_ops"] as? Int, 1)
        XCTAssertEqual(json["applied_op_id"] as? Int, 7)
        XCTAssertEqual(json["wallet"] as? Int, 1_234)
        let bag = try XCTUnwrap(json["bag"] as? [[String: Any]])
        XCTAssertEqual(bag.map { $0["key"] as? String },
                       [ItemKind.rareCandy.rawValue, MegaStone.all[0].inventoryKey, MachineMove.inventoryKey(85)])
        XCTAssertEqual(bag.first?["name"] as? String, "이상한사탕")
        XCTAssertEqual(bag.first?["count"] as? Int, 3)
        XCTAssertEqual(bag.last?["name"] as? String, "기술머신 10만볼트")
        let shop = try XCTUnwrap(json["shop"] as? [[String: Any]])
        XCTAssertEqual(Set(shop.first.map { Array($0.keys) } ?? []), ["key", "name", "price", "category", "single"])
        XCTAssertFalse(shop.contains { $0["key"] as? String == MegaStone.all[0].inventoryKey })
        XCTAssertFalse(shop.contains { $0["key"] as? String == MachineMove.inventoryKey(85) })
        XCTAssertTrue(shop.contains { $0["key"] as? String == MachineMove.inventoryKey(87) })
    }

    func testTheShopUsesTheAppsPricesAndDropsWhatIsSoldOut() throws {
        let store = try makeStore(at: saveURL()) { $0.inventory[ItemKind.shinyCharm.rawValue] = 1 }
        let shop = store.remoteShop
        XCTAssertEqual(shop.first { $0.key == ItemKind.rareCandy.rawValue }?.price, store.price(of: .rareCandy))
        XCTAssertTrue(store.isSoldOut(.shinyCharm))
        XCTAssertNil(shop.first { $0.key == ItemKind.shinyCharm.rawValue })
        XCTAssertEqual(shop.first { $0.key == ScoutPool.national.inventoryKey }?.price, store.scoutPrice)
        XCTAssertEqual(Set(shop.map(\.key)).count, shop.count)
    }

    func testTheShopListsOnlyItemsTheShopScreenSells() throws {
        let store = try makeStore(at: saveURL())
        var onScreen = Set(store.shopEntries(in: nil).compactMap { entry -> String? in
            if case .item(let kind) = entry { return kind.rawValue }
            return nil
        })
        onScreen.formUnion(store.shopBattleSections.flatMap(\.kinds).map(\.rawValue))
        onScreen.formUnion(store.shopEvolutionItems.map(\.rawValue))
        onScreen.formUnion(store.megaStoneShopEntries.compactMap { entry -> String? in
            switch entry {
            case .item(let kind): return kind.rawValue
            case .megaStone(let stone): return stone.inventoryKey
            case .egg: return nil
            }
        })
        onScreen.formUnion(store.machineShopMoves().map { MachineMove.inventoryKey($0.id) })
        onScreen.formUnion(ScoutPool.all.map(\.inventoryKey))

        let listed = Set(store.remoteShop.map(\.key))
        XCTAssertTrue(listed.isSubset(of: onScreen), "\(listed.subtracting(onScreen).sorted())")
        let priced = ItemKind.allCases.filter { store.price(of: $0) != nil && !store.isSoldOut($0) }.map(\.rawValue)
        XCTAssertEqual(onScreen.intersection(priced), listed.intersection(priced))
    }

    func testTheWalletDoesNotMakeAnUnchangedPartyResendBeforeFiveMinutes() async throws {
        let wallet = Applied()
        let sync = RemoteOpsSync(apply: { _ in }, lastID: { 0 }, results: { [] }, acknowledged: { _ in },
                                 snapshot: { RemoteSnapshot(wallet: wallet.count, bag: [], shop: []) })
        let bot = RemoteOpsBot()
        let uploader = try uploader(bot, sync: sync)
        let start = Date(timeIntervalSince1970: 5_000)

        await uploader.tick(now: start)
        wallet.count = 500
        await uploader.tick(now: start.addingTimeInterval(60))
        XCTAssertEqual(bot.uploads.count, 1)

        await uploader.tick(now: start.addingTimeInterval(300))
        XCTAssertEqual(bot.uploads.map { $0["wallet"] as? Int }, [0, 500])
    }

    func testAFullPoolWithTheLargestBagAndShopFitsTheBotsBodyLimit() throws {
        let full = try makeStore(at: saveURL()) { state in
            for kind in ItemKind.allCases { state.inventory[kind.rawValue] = 99 }
            for stone in MegaStone.all { state.inventory[stone.inventoryKey] = 9 }
            for move in MachineCatalog.moves { state.inventory[MachineMove.inventoryKey(move.id)] = 1 }
            for pool in ScoutPool.all { state.inventory[pool.inventoryKey] = 9 }
        }
        let empty = try makeStore(at: saveURL())
        let snapshot = RemoteSnapshot(wallet: .max, bag: full.remoteBag, shop: empty.remoteShop)
        let party = Array(repeating: PartyMember(pokemonID: 25, level: 100, shiny: true, ivs: nil,
                                                 moves: [1, 2, 3, 4]), count: 6)
        let body = try PartyPayload(appVersion: "3.0.0", party: party, dex: DexSummary(full), appliedOpID: .max,
                                    snapshot: snapshot).encoded(wallet: snapshot.wallet)

        XCTAssertNotNil((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["dex"])
        XCTAssertGreaterThan(snapshot.bag.count, MachineCatalog.moves.count)
        XCTAssertGreaterThan(snapshot.shop.count, MachineCatalog.moves.count)
        XCTAssertLessThanOrEqual(body.count + TradePool.maxBytes, try botConstant("MAX_BODY_BYTES", in: "upload_server.py"))
    }

    // MARK: Helpers

    private func saveURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("remote-ops-\(UUID().uuidString).json")
        paths.append(url)
        return url
    }

    private func makeStore(at url: URL, _ edit: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .ko
        edit(&state)
        try JSONEncoder().encode(state).write(to: url)
        return try openStore(at: url)
    }

    private func openStore(at url: URL) throws -> CompanionStore {
        let suite = "remote-ops-\(UUID().uuidString)"
        suites.append(suite)
        return CompanionStore(provider: NoLines(), fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func uploader(_ bot: RemoteOpsBot, sync: RemoteOpsSync?,
                          party: [PartyMember] = [PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)])
        throws -> PartyUploader {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("remote-ops-\(UUID().uuidString)")
        paths.append(directory)
        let suite = "remote-ops-\(UUID().uuidString)"
        suites.append(suite)
        let tokenStore = PartyTokenStore(fileURL: directory.appendingPathComponent("token"))
        try tokenStore.save("tok")
        let uploader = PartyUploader(tokenStore: tokenStore, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)),
                                     appVersion: "test", exchange: { bot.reply($0) }, fetch: { bot.reply($0) },
                                     partySource: { party }, remoteOps: sync)
        uploader.serverURL = "http://example.local:8790"
        return uploader
    }

    private func sync(_ store: CompanionStore, _ applied: Applied) -> RemoteOpsSync {
        let appliers = applied.appliers
        return RemoteOpsSync(apply: { [weak store] ops in store?.applyRemoteOps(ops, appliers: appliers) },
                             lastID: { [weak store] in store?.state.remoteOpsLastID ?? 0 },
                             results: { [weak store] in store?.state.remoteOpResults ?? [] },
                             acknowledged: { [weak store] ids in store?.acknowledgeRemoteOps(ids) },
                             snapshot: { [weak store] in
                                 store?.remoteSnapshot ?? RemoteSnapshot(wallet: 0, bag: [], shop: [])
                             })
    }

    private func op(_ id: Int, _ kind: String) -> String {
        #"{"id":\#(id),"kind":"\#(kind)","payload":{},"created_at":"x"}"#
    }

    private func botConstant(_ name: String, in file: String) throws -> Int {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("bot/ypoke/\(file)"), encoding: .utf8)
        let line = try XCTUnwrap(source.split(separator: "\n").first { $0.hasPrefix("\(name) = ") })
        return line.dropFirst(name.count + 3).split(separator: "*")
            .map { Int($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "")) ?? 0 }
            .reduce(1, *)
    }
}
