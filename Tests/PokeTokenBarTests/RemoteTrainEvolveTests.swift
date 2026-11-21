import XCTest
@testable import PokeTokenBar

private let levelUp = [EvoMethod(trigger: "level-up", item: nil)]

private let roggenrola = EvoNode(speciesID: 524, children: [
    EvoNode(speciesID: 525, children: [EvoNode(speciesID: 526, children: [], methods: [EvoMethod(trigger: "trade")])],
            methods: levelUp),
])
private let roggenrolaWithoutTrade = EvoNode(speciesID: 524, children: [
    EvoNode(speciesID: 525, children: [], methods: levelUp),
])
private let onix = EvoNode(speciesID: 95, children: [
    EvoNode(speciesID: 208, children: [], methods: [EvoMethod(trigger: "trade", heldItem: "metal-coat")]),
])
private let karrablast = EvoNode(speciesID: 588, children: [
    EvoNode(speciesID: 589, children: [], methods: [EvoMethod(trigger: "trade", tradeSpecies: "shelmet")]),
])

/// Evolution lines from `trees`. While `holding`, each line request waits for `release()`.
private actor LineProvider: PokeProviding, PokemonDetailProviding {
    private let trees: [Int: EvoNode]
    private var holding: Bool
    private var held: [CheckedContinuation<Void, Never>] = []
    private(set) var waiting = 0

    init(trees: [Int: EvoNode], holding: Bool = false) {
        self.trees = trees
        self.holding = holding
    }

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        if holding {
            waiting += 1
            await withCheckedContinuation { held.append($0) }
        }
        guard let tree = trees[baseSpeciesID] else { throw URLError(.notConnectedToInternet) }
        return EvoLine(baseID: baseSpeciesID, tree: tree, rarity: .common, names: [:])
    }

    func release() {
        holding = false
        held.forEach { $0.resume() }
        held = []
    }

    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class RemoteTrainEvolveTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []

    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    // MARK: What the upload offers

    func testTheCordTargetIsTheTradeStepOfTheEvolutionLine() async throws {
        let store = try makeStore(LineProvider(trees: [:])) { state in
            state.dex = [Self.boldore, Self.entry("onix", base: 95, final: 95), Self.entry("bare", base: 95, final: 95),
                         Self.entry("karra", base: 588, final: 588), Self.entry("shel", base: 616, final: 616)]
            state.heldItems["onix"] = ItemKind.metalCoat.rawValue
            state.friendEntryIDs = ["shel"]
        }
        let partners: Set<Int> = [616]
        for (id, tree, held) in [("bold", roggenrola, nil), ("onix", onix, ItemKind.metalCoat), ("bare", onix, nil),
                                 ("karra", karrablast, nil)] as [(String, EvoNode, ItemKind?)] {
            let entry = try XCTUnwrap(store.state.dex.first { $0.id == id })
            let step = tree.node(withID: entry.finalID)?.tradeEvolution(heldItem: held, partners: partners)
            XCTAssertEqual(RemoteTrain.cordEvolution(of: id, store: store)?.pokemonID, step?.speciesID, id)
        }
        XCTAssertEqual(RemoteTrain.cordEvolution(of: "onix", store: store)?.heldItem, "metal-coat")
        XCTAssertNil(RemoteTrain.cordEvolution(of: "bold", store: store)?.heldItem)
    }

    func testEveryTradeStepNamesTheSpeciesItGrowsFrom() {
        let unnamed = EvolutionRules.table.filter { $0.trade != nil && $0.from == nil }.map(\.species)
        XCTAssertEqual(unnamed, [])
    }

    func testNoHintForTheRaisedOneOrOneInATradeOrHoldingAnEverstone() async throws {
        let store = try makeStore(LineProvider(trees: [:])) { state in
            state.dex = [Self.boldore, Self.entry("raised", base: 524, final: 525),
                         Self.entry("listed", base: 524, final: 525), Self.entry("stone", base: 524, final: 525)]
            state.raisedEntryID = "raised"
            state.heldItems["stone"] = ItemKind.everstone.rawValue
        }
        store.lockForTrade("listed")
        XCTAssertEqual(RemoteTrain.evolutions(store: store), ["bold": RemoteEvolution(item: "linkingCord", pokemonID: 526)])
    }

    // MARK: Applying the op

    func testAnEvolveOpSpendsOneCordAndASecondSyncChangesNothing() async throws {
        let store = try makeStore(LineProvider(trees: [524: roggenrola])) { state in
            state.dex = [Self.boldore]
            state.inventory[ItemKind.linkingCord.rawValue] = 2
        }
        let sync = try sync(store)
        let ops = [evolveOp(1)]

        await sync.apply(ops)
        await sync.apply(ops)

        XCTAssertEqual(store.state.dex.first?.finalID, 526)
        XCTAssertEqual(store.itemCount(.linkingCord), 1)
        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1)])
    }

    func testTwoSyncsAtOnceEvolveOnceAndRecordTheEvolution() async throws {
        let provider = LineProvider(trees: [524: roggenrola], holding: true)
        let store = try makeStore(provider) { state in
            state.dex = [Self.boldore]
            state.inventory[ItemKind.linkingCord.rawValue] = 2
        }
        let sync = try sync(store)
        let ops = [evolveOp(1)]

        let first = Task { await sync.apply(ops) }
        let second = Task { await sync.apply(ops) }
        try await waitUntil("the first sync to wait for the evolution line") { await provider.waiting == 1 }
        await provider.release()
        await first.value
        await second.value

        XCTAssertEqual(store.state.dex.first?.finalID, 526)
        XCTAssertEqual(store.itemCount(.linkingCord), 1)
        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1)])
    }

    func testACordBoughtInSlackBeforeTheEvolveOpIsThereWhenItApplies() async throws {
        let store = try makeStore(LineProvider(trees: [524: roggenrola])) { state in
            state.dex = [Self.boldore]
            state.usedSinceInstall = 3_000_000_000
        }
        let price = try XCTUnwrap(store.remoteShop.first { $0.key == ItemKind.linkingCord.rawValue }?.price)
        let buy = try JSONSerialization.data(withJSONObject: ["key": "linkingCord", "count": 1, "price": price])

        try await sync(store).apply([evolveOp(2), RemoteOp(id: 1, kind: RemoteBuy.kind, payload: buy)])

        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1), RemoteOpResult(id: 2)])
        XCTAssertEqual(store.state.dex.first?.finalID, 526)
        XCTAssertEqual(store.itemCount(.linkingCord), 0)
    }

    func testAHeldItemStepUsesTheItemUp() async throws {
        let store = try makeStore(LineProvider(trees: [95: onix])) { state in
            state.dex = [Self.entry("onix", base: 95, final: 95)]
            state.heldItems["onix"] = ItemKind.metalCoat.rawValue
            state.inventory[ItemKind.linkingCord.rawValue] = 1
        }
        try await sync(store).apply([evolveOp(1, id: "onix", from: 95, to: 208)])
        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1)])
        XCTAssertNil(store.state.heldItems["onix"])
    }

    // MARK: Refusals, with nothing spent

    func testEachRefusalKeepsTheCordAndThePokemon() async throws {
        let cases: [(String, [Int: EvoNode], (inout CompanionState) -> Void, [String: Any], String)] = [
            ("no cord", [524: roggenrola], { $0.inventory = [:] }, [:], RemoteTrain.Reason.noItem),
            ("another target", [524: roggenrola], { _ in }, ["to_pokemon_id": 527], RemoteTrain.Reason.notApplicable),
            ("raised", [524: roggenrola], { $0.raisedEntryID = "bold" }, [:], RemoteTrain.Reason.notApplicable),
            ("evolved since", [524: roggenrola], { _ in }, ["pokemon_id": 524], RemoteTrain.Reason.evolved),
            ("everstone", [524: roggenrola], { $0.heldItems["bold"] = ItemKind.everstone.rawValue }, [:],
             RemoteTrain.Reason.everstone),
            ("line not loaded", [:], { _ in }, [:], RemoteTrain.Reason.noData),
            ("line without the trade", [524: roggenrolaWithoutTrade], { _ in }, [:], RemoteTrain.Reason.wrongTarget),
            ("another item", [524: roggenrola], { _ in }, ["item": "rareCandy"], RemoteTrain.Reason.invalid),
        ]
        for (name, trees, edit, change, reason) in cases {
            let store = try makeStore(LineProvider(trees: trees)) { state in
                state.dex = [Self.boldore]
                state.inventory[ItemKind.linkingCord.rawValue] = 1
                edit(&state)
            }
            let before = store.itemCount(.linkingCord)
            let refusal = await RemoteTrain.evolve(payload(change), store: store)
            XCTAssertEqual(refusal, reason, name)
            XCTAssertEqual(store.itemCount(.linkingCord), before, name)
            XCTAssertEqual(store.state.dex.first?.finalID, 525, name)
        }
    }

    func testAPokemonInATradeIsRefusedAsTradeLocked() async throws {
        let store = try makeStore(LineProvider(trees: [524: roggenrola])) { state in
            state.dex = [Self.boldore]
            state.inventory[ItemKind.linkingCord.rawValue] = 1
        }
        store.lockForTrade("bold")
        let refusal = await RemoteTrain.evolve(payload(), store: store)
        XCTAssertEqual(refusal, RemoteTrain.Reason.tradeLocked)
        XCTAssertEqual(store.itemCount(.linkingCord), 1)
    }

    func testEveryCordResultHasAReasonTheBotWords() throws {
        let codes: [CompanionStore.CordUseResult: String?] = [
            .evolved: nil, .wrongTarget: "wrong_target", .notReady: "not_ready", .everstone: "everstone",
            .listed: "trade_locked", .unavailable: "no_data",
        ]
        for (result, code) in codes { XCTAssertEqual(RemoteTrain.reason(result), code, "\(result)") }
        let source = try String(contentsOf: Self.botFile, encoding: .utf8)
        for code in codes.values.compactMap({ $0 }) {
            XCTAssertTrue(source.contains(#"= "\#(code)""#), "bot/ypoke/remote_train.py has no reason \(code)")
        }
    }

    // MARK: Helpers

    private static let botFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("bot/ypoke/remote_train.py")

    private static let boldore = entry("bold", base: 524, final: 525)

    private static func entry(_ id: String, base: Int, final: Int) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 11, instanceID: id)
        profile.level = 40
        return DexEntry(id: id, baseID: base, finalID: final, chainOrder: base == final ? [base] : [base, final],
                        rarity: .common, caughtAt: Date(timeIntervalSince1970: 100), isShiny: false, nature: .adamant,
                        profile: profile, names: [final: ["ko": "x", "en": "x"]], originalTrainer: nil)
    }

    private func payload(_ change: [String: Any] = [:]) -> Data {
        let base: [String: Any] = ["action": "evolve", "id": "bold", "pokemon_id": 525, "name": "암트르",
                                   "item": "linkingCord", "to_pokemon_id": 526]
        return (try? JSONSerialization.data(withJSONObject: base.merging(change) { $1 })) ?? Data()
    }

    private func evolveOp(_ opID: Int, id: String = "bold", from: Int = 525, to: Int = 526) -> RemoteOp {
        RemoteOp(id: opID, kind: RemoteTrain.kind, payload: payload(["id": id, "pokemon_id": from, "to_pokemon_id": to]))
    }

    private func sync(_ store: CompanionStore) throws -> RemoteOpsSync {
        let suite = "remote-evolve-battle-\(UUID().uuidString)"
        suites.append(suite)
        return RemoteOpsSync(store: store, battleEntry: BattleEntryStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite))))
    }

    private func makeStore(_ provider: LineProvider, _ configure: (inout CompanionState) -> Void) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .ko
        configure(&state)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("remote-evolve-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "remote-evolve-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: provider, fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }
}
