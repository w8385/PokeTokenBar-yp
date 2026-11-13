import XCTest
@testable import PokeTokenBar

private let levelUpMethod = [EvoMethod(trigger: "level-up", item: nil)]
private let tradeMethod = [EvoMethod(trigger: "trade", item: nil)]

private let gastly = EvoNode(speciesID: 92, children: [
    EvoNode(speciesID: 93, children: [EvoNode(speciesID: 94, children: [], methods: tradeMethod)],
            methods: levelUpMethod),
])
private let pikachu = EvoNode(speciesID: 25, children: [
    EvoNode(speciesID: 26, children: [], methods: [EvoMethod(trigger: "use-item", item: "thunder-stone")]),
])
private let onix = EvoNode(speciesID: 95, children: [
    EvoNode(speciesID: 208, children: [],
            methods: [EvoMethod(trigger: "trade", item: nil, heldItem: "metal-coat")]),
])

private let karrablast = EvoNode(speciesID: 588, children: [
    EvoNode(speciesID: 589, children: [], methods: [EvoMethod(trigger: "trade", item: nil, tradeSpecies: "shelmet")]),
])
private let shelmet = EvoNode(speciesID: 616, children: [
    EvoNode(speciesID: 617, children: [], methods: [EvoMethod(trigger: "trade", item: nil, tradeSpecies: "karrablast")]),
])

private struct TreeProvider: PokeProviding {
    let trees: [Int: EvoNode]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        guard let tree = trees[baseSpeciesID] else { throw URLError(.badServerResponse) }
        return EvoLine(baseID: baseSpeciesID, tree: tree, rarity: .common, names: [
            92: ["ko": "고오스", "en": "Gastly"], 93: ["ko": "고우스트", "en": "Haunter"],
            94: ["ko": "팬텀", "en": "Gengar"], 25: ["en": "Pikachu"], 26: ["en": "Raichu"],
        ])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class TradeEvolutionTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private let provider = TreeProvider(trees: [92: gastly, 25: pikachu, 95: onix, 588: karrablast, 616: shelmet])

    private func makeStore(_ configure: (inout CompanionState) -> Void = { _ in }, file: URL? = nil) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .ko
        configure(&state)
        let url: URL
        if let file {
            url = file
        } else {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-evo-\(UUID())")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            paths.append(dir)
            url = dir.appendingPathComponent("state.json")
            try JSONEncoder().encode(state).write(to: url)
        }
        let suite = "trade-evo-\(UUID())"
        suites.append(suite)
        return CompanionStore(provider: provider, fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false,
                              defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    private func entry(id: String, base: Int, final: Int, chain: [Int], level: Int = 50,
                       caught: TimeInterval = 100) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 11, instanceID: id)
        profile.level = level
        return DexEntry(id: id, baseID: base, finalID: final, chainOrder: chain, rarity: .common,
                        caughtAt: Date(timeIntervalSince1970: caught), isShiny: true, nature: .adamant,
                        profile: profile, names: [final: ["ko": "x", "en": "x"]], originalTrainer: nil)
    }

    private func delivery(tradeID: String, give: String, receiving wire: DexEntry, from: String = "Sam") throws -> TradeDelivery {
        let item = TradePoolEntry(id: wire.id, pokemonID: wire.finalID, level: wire.profile?.level ?? 1,
                                  shiny: wire.isShiny, name: "고우스트", entry: wire)
        let json: [String: Any] = [
            "trade_id": tradeID, "give_id": give, "from_name": from,
            "receive": try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)),
        ]
        let body = try JSONSerialization.data(withJSONObject: ["ok": true, "trades": ["deliveries": [json]]])
        return try XCTUnwrap(TradeSyncReply.decode(body).deliveries.first)
    }

    private func waitForLine(_ store: CompanionStore) async throws {
        for _ in 0..<200 where store.currentLine == nil {
            store.update(todayTokensByProvider: [:], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                         limitWarning: false, hasUsageData: false)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(store.currentLine)
    }

    private func growToEnd(_ store: CompanionStore) {
        for _ in 0..<6 where store.state.active != nil { store.applyUsage(store.tokensToNext) }
    }

    func testNewGastlyLineGraduatesAtHaunter() async throws {
        let store = try makeStore()
        await store.hatch(baseID: 92)
        XCTAssertEqual(store.state.active?.tradeGated, true)
        XCTAssertEqual(store.state.active?.totalForms, 2)
        growToEnd(store)
        XCTAssertNil(store.state.active)
        let graduated = try XCTUnwrap(store.state.dex.last)
        XCTAssertEqual(graduated.baseID, 92)
        XCTAssertEqual(graduated.finalID, 93)
        XCTAssertEqual(graduated.chainOrder, [92, 93])
    }

    func testGateSurvivesARelaunchAndTheLineReload() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-evo-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(CompanionState()).write(to: file)
        let first = try makeStore(file: file)
        await first.hatch(baseID: 92)
        XCTAssertEqual(first.state.active?.tradeGated, true)

        let second = try makeStore(file: file)
        try await waitForLine(second)
        XCTAssertEqual(second.state.active?.tradeGated, true)
        XCTAssertEqual(second.currentLine?.totalForms, 2)
        growToEnd(second)
        XCTAssertEqual(second.state.dex.last?.finalID, 93)
    }

    func testGrandfatheredCompanionStillReachesGengar() async throws {
        let store = try makeStore { state in
            state.active = MonState(baseID: 92, pathIDs: [92], stageIndex: 0, usedAtStage: 0,
                                    rarity: .common, totalForms: 3,
                                    profile: PokemonProfile.generate(seed: 5, instanceID: "old"))
        }
        try await waitForLine(store)
        XCTAssertNil(store.state.active?.tradeGated)
        XCTAssertEqual(store.currentLine?.totalForms, 3)
        growToEnd(store)
        XCTAssertEqual(store.state.dex.last?.finalID, 94)
    }

    func testNewOnixLineStopsBeforeTheHeldItemTrade() async throws {
        let store = try makeStore()
        await store.hatch(baseID: 95)
        XCTAssertEqual(store.state.active?.totalForms, 1)
        XCTAssertEqual(store.state.active?.plannedPathIDs, [95])
    }

    func testTradeGatedCompanionThatPlannedThroughSteelixKeepsItsPlan() async throws {
        let store = try makeStore { state in
            state.active = MonState(baseID: 95, pathIDs: [95], plannedPathIDs: [95, 208], stageIndex: 0,
                                    usedAtStage: 0, rarity: .common, totalForms: 2,
                                    profile: PokemonProfile.generate(seed: 5, instanceID: "o"), tradeGated: true)
        }
        try await waitForLine(store)
        XCTAssertEqual(store.currentLine?.totalForms, 2)
        growToEnd(store)
        XCTAssertEqual(store.state.dex.last?.finalID, 208)
    }

    func testTradedHaunterArrivesAsGengarWithItsProfile() async throws {
        let mine = entry(id: "mine", base: 25, final: 26, chain: [25, 26], caught: 10)
        let theirs = entry(id: "theirs", base: 92, final: 93, chain: [92, 93])
        let store = try makeStore { $0.dex = [mine] }
        let applied = store.applyTrades([try delivery(tradeID: "t1", give: "mine", receiving: theirs)])
        XCTAssertEqual(applied, ["t1"])
        await store.resolveTradeEvolutions()

        let arrived = try XCTUnwrap(store.state.dex.first { $0.releasedAt == nil })
        XCTAssertEqual(arrived.finalID, 94)
        XCTAssertEqual(arrived.chainOrder, [92, 93, 94])
        XCTAssertNotEqual(arrived.id, "theirs")
        XCTAssertEqual(arrived.profile?.instanceID, arrived.id)
        XCTAssertEqual(arrived.profile?.ivs, theirs.profile?.ivs)
        XCTAssertEqual(arrived.profile?.level, 50)
        XCTAssertEqual(arrived.nature, .adamant)
        XCTAssertTrue(arrived.isShiny)
        XCTAssertEqual(arrived.originalTrainer, "Sam")
        XCTAssertNil(arrived.tradeEvolutionPending)
        XCTAssertEqual(store.tradeArrival?.evolvedID, 94)

        let sent = try XCTUnwrap(store.state.dex.first { $0.id == "mine" })
        XCTAssertNotNil(sent.releasedAt)
        XCTAssertEqual(sent.tradedTo, "Sam")
        XCTAssertEqual(store.state.dex.filter { $0.releasedAt == nil }.count, 1)
    }

    func testTradeWithoutAnEvolutionJustArrives() async throws {
        let incoming = entry(id: "pika", base: 25, final: 26, chain: [25, 26])
        let store = try makeStore()
        store.applyTrades([try delivery(tradeID: "t1", give: "none", receiving: incoming)])
        await store.resolveTradeEvolutions()
        let arrived = try XCTUnwrap(store.state.dex.first)
        XCTAssertEqual(arrived.finalID, 26)
        XCTAssertNil(arrived.tradeEvolutionPending)
    }

    func testDoubleDeliveryAppliesOnceAndAcknowledgesBoth() async throws {
        let mine = entry(id: "mine", base: 25, final: 26, chain: [25, 26])
        let theirs = entry(id: "theirs", base: 92, final: 93, chain: [92, 93])
        let store = try makeStore { $0.dex = [mine] }
        let again = try delivery(tradeID: "t1", give: "mine", receiving: theirs)
        XCTAssertEqual(store.applyTrades([again]), ["t1"])
        XCTAssertEqual(store.applyTrades([again, again]), ["t1", "t1"])
        XCTAssertEqual(store.state.dex.count, 2)
        XCTAssertEqual(store.state.appliedTradeIDs, ["t1"])
    }

    func testAppliedTradeSurvivesARestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-evo-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        let mine = entry(id: "mine", base: 25, final: 26, chain: [25, 26])
        let theirs = entry(id: "theirs", base: 92, final: 93, chain: [92, 93])
        var seed = CompanionState()
        seed.dex = [mine]
        try JSONEncoder().encode(seed).write(to: file)
        let first = try makeStore(file: file)
        let incoming = try delivery(tradeID: "t1", give: "mine", receiving: theirs)
        first.applyTrades([incoming])

        let second = try makeStore(file: file)
        XCTAssertEqual(second.applyTrades([incoming]), ["t1"])
        XCTAssertEqual(second.state.dex.count, 2)
    }

    func testAnUnreadableDeliveryIsNotAcknowledged() async throws {
        let store = try makeStore()
        let unsupported = entry(id: "far", base: 9000, final: 9000, chain: [9000])
        XCTAssertEqual(store.applyTrades([try delivery(tradeID: "t9", give: "x", receiving: unsupported)]), [])
        XCTAssertTrue(store.state.dex.isEmpty)
    }

    func testLinkingCordEvolvesAGraduatedHaunter() async throws {
        let haunter = entry(id: "h", base: 92, final: 93, chain: [92, 93])
        let store = try makeStore { state in
            state.dex = [haunter]
            state.inventory[ItemKind.linkingCord.rawValue] = 2
        }
        XCTAssertEqual(store.itemCount(.linkingCord), 2)
        let result = await store.useLinkingCord(on: "h")
        XCTAssertEqual(result, .evolved)
        let evolved = try XCTUnwrap(store.state.dex.first)
        XCTAssertEqual(evolved.finalID, 94)
        XCTAssertEqual(evolved.chainOrder, [92, 93, 94])
        XCTAssertEqual(store.itemCount(.linkingCord), 1)
        XCTAssertNil(store.tradeArrival?.fromName)
        XCTAssertEqual(store.tradeArrival?.evolvedID, 94)
    }

    func testLinkingCordOnAWrongTargetKeepsTheCord() async throws {
        let raichu = entry(id: "p", base: 25, final: 26, chain: [25, 26])
        let pikachuOnly = entry(id: "q", base: 25, final: 25, chain: [25])
        let heldItem = entry(id: "o", base: 95, final: 95, chain: [95])
        let store = try makeStore { state in
            state.dex = [raichu, pikachuOnly, heldItem]
            state.inventory[ItemKind.linkingCord.rawValue] = 1
        }
        for id in ["p", "q"] {
            let result = await store.useLinkingCord(on: id)
            XCTAssertEqual(result, .wrongTarget, id)
        }
        let waiting = await store.useLinkingCord(on: "o")
        XCTAssertEqual(waiting, .notReady)
        XCTAssertEqual(store.itemCount(.linkingCord), 1)
        XCTAssertEqual(store.state.dex.map(\.finalID), [26, 25, 95])
    }

    func testLinkingCordWithoutOneInTheBagIsRefused() async throws {
        let store = try makeStore { $0.dex = [entry(id: "h", base: 92, final: 93, chain: [92, 93])] }
        let result = await store.useLinkingCord(on: "h")
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(store.state.dex.first?.finalID, 93)
    }

    func testCordIsSoldBesideTheStonesAtTheStonePrice() throws {
        let store = try makeStore { $0.usedSinceInstall = 3_000_000_000 }
        XCTAssertEqual(store.shopEvolutionItems,
                       store.evolutionStoneItems + [.linkingCord] + ItemKind.allCases.filter(\.isEvolutionHeld))
        XCTAssertFalse(store.purchasableItems.contains(.linkingCord))
        XCTAssertEqual(store.price(of: .linkingCord), EvolutionStone.price)
        XCTAssertTrue(store.buy(.linkingCord, count: 1))
        XCTAssertEqual(store.itemCount(.linkingCord), 1)
    }

    // MARK: trades that need a held item or a partner species

    private func equippedStore(base: Int, final: Int, chain: [Int], holding item: ItemKind?,
                               cords: Int = 1) throws -> CompanionStore {
        try makeStore { state in
            state.dex = [entry(id: "o", base: base, final: final, chain: chain)]
            state.inventory[ItemKind.linkingCord.rawValue] = cords
            if let item { state.heldItems["o"] = item.rawValue }
        }
    }

    func testCordWithTheRightItemEvolvesOnixAndUsesUpBoth() async throws {
        let store = try equippedStore(base: 95, final: 95, chain: [95], holding: .metalCoat)
        let result = await store.useLinkingCord(on: "o")
        XCTAssertEqual(result, .evolved)
        XCTAssertEqual(store.state.dex.first?.finalID, 208)
        XCTAssertEqual(store.itemCount(.linkingCord), 0)
        XCTAssertNil(store.heldItem(of: "o"))
        XCTAssertEqual(store.itemCount(.metalCoat), 0)
    }

    func testCordWithoutTheItemWaitsAndKeepsEverything() async throws {
        let bare = try equippedStore(base: 95, final: 95, chain: [95], holding: nil)
        let bareResult = await bare.useLinkingCord(on: "o")
        XCTAssertEqual(bareResult, .notReady)
        XCTAssertEqual(bare.state.dex.first?.finalID, 95)
        XCTAssertEqual(bare.itemCount(.linkingCord), 1)

        let wrong = try equippedStore(base: 95, final: 95, chain: [95], holding: .dragonScale)
        let wrongResult = await wrong.useLinkingCord(on: "o")
        XCTAssertEqual(wrongResult, .notReady)
        XCTAssertEqual(wrong.heldItem(of: "o"), .dragonScale)
        XCTAssertEqual(wrong.itemCount(.linkingCord), 1)
    }

    func testCordNeedsTheFriendSpeciesForAPartnerTrade() async throws {
        let withFriend = try makeStore { state in
            state.dex = [entry(id: "k", base: 588, final: 588, chain: [588]),
                         entry(id: "s", base: 616, final: 616, chain: [616])]
            state.friendEntryIDs = ["s"]
            state.inventory[ItemKind.linkingCord.rawValue] = 1
        }
        let evolved = await withFriend.useLinkingCord(on: "k")
        XCTAssertEqual(evolved, .evolved)
        XCTAssertEqual(withFriend.state.dex.first { $0.id == "k" }?.finalID, 589)
        XCTAssertEqual(withFriend.state.dex.first { $0.id == "s" }?.finalID, 616)

        let alone = try makeStore { state in
            state.dex = [entry(id: "k", base: 588, final: 588, chain: [588]),
                         entry(id: "s", base: 616, final: 616, chain: [616])]
            state.inventory[ItemKind.linkingCord.rawValue] = 1
        }
        let waiting = await alone.useLinkingCord(on: "k")
        XCTAssertEqual(waiting, .notReady)
        XCTAssertEqual(alone.itemCount(.linkingCord), 1)
    }

    func testRealTradeForTheRightPartnerSpeciesEvolvesTheArrival() async throws {
        let mine = entry(id: "mine", base: 616, final: 616, chain: [616], caught: 10)
        let store = try makeStore { $0.dex = [mine] }
        store.applyTrades([try delivery(tradeID: "t1", give: "mine",
                                        receiving: entry(id: "k", base: 588, final: 588, chain: [588]))])
        await store.resolveTradeEvolutions()
        let arrived = try XCTUnwrap(store.state.dex.first { $0.releasedAt == nil })
        XCTAssertEqual(arrived.finalID, 589)
        XCTAssertNil(arrived.tradePartnerID)
    }

    func testRealTradeForTheWrongSpeciesLeavesTheArrivalAsItIs() async throws {
        let mine = entry(id: "mine", base: 25, final: 26, chain: [25, 26], caught: 10)
        let store = try makeStore { $0.dex = [mine] }
        store.applyTrades([try delivery(tradeID: "t1", give: "mine",
                                        receiving: entry(id: "k", base: 588, final: 588, chain: [588]))])
        await store.resolveTradeEvolutions()
        XCTAssertEqual(store.state.dex.first { $0.releasedAt == nil }?.finalID, 588)
    }

    func testArrivalCarryingTheRightItemEvolvesAndTheItemIsUsedUp() async throws {
        var wire = entry(id: "o", base: 95, final: 95, chain: [95])
        wire.tradeHeldItem = ItemKind.metalCoat.rawValue
        let store = try makeStore()
        store.applyTrades([try delivery(tradeID: "t1", give: "none", receiving: wire)])
        await store.resolveTradeEvolutions()
        let arrived = try XCTUnwrap(store.state.dex.first)
        XCTAssertEqual(arrived.finalID, 208)
        XCTAssertNil(arrived.tradeHeldItem)
        XCTAssertEqual(store.itemCount(.metalCoat), 0)
    }

    func testArrivalCarryingAnUnusedItemCreditsItToTheBag() async throws {
        var wire = entry(id: "o", base: 95, final: 95, chain: [95])
        wire.tradeHeldItem = ItemKind.dragonScale.rawValue
        let store = try makeStore()
        store.applyTrades([try delivery(tradeID: "t1", give: "none", receiving: wire)])
        await store.resolveTradeEvolutions()
        XCTAssertEqual(store.state.dex.first?.finalID, 95)
        XCTAssertNil(store.state.dex.first?.tradeHeldItem)
        XCTAssertEqual(store.itemCount(.dragonScale), 1)
    }

    func testArrivalIgnoresAnItemThatIsNotATradeItem() async throws {
        var wire = entry(id: "o", base: 95, final: 95, chain: [95])
        wire.tradeHeldItem = ItemKind.rareCandy.rawValue
        let received = try XCTUnwrap(CompanionStore.receivedEntry(wire, from: "Sam", now: Date()))
        XCTAssertNil(received.tradeHeldItem)
        wire.tradePartnerID = 616
        XCTAssertNil(try XCTUnwrap(CompanionStore.receivedEntry(wire, from: "Sam", now: Date())).tradePartnerID)
    }

    func testTheSendersTradeItemLeavesWithThePokemonButOtherItemsReturn() async throws {
        let coat = try makeStore { state in
            state.dex = [entry(id: "mine", base: 95, final: 95, chain: [95], caught: 10)]
            state.heldItems["mine"] = ItemKind.metalCoat.rawValue
        }
        coat.applyTrades([try delivery(tradeID: "t1", give: "mine",
                                       receiving: entry(id: "x", base: 25, final: 26, chain: [25, 26]))])
        XCTAssertNil(coat.heldItem(of: "mine"))
        XCTAssertEqual(coat.itemCount(.metalCoat), 0)

        let sash = try makeStore { state in
            state.dex = [entry(id: "mine", base: 95, final: 95, chain: [95], caught: 10)]
            state.heldItems["mine"] = ItemKind.leftovers.rawValue
        }
        sash.applyTrades([try delivery(tradeID: "t1", give: "mine",
                                       receiving: entry(id: "x", base: 25, final: 26, chain: [25, 26]))])
        XCTAssertEqual(sash.itemCount(.leftovers), 1)
    }

    func testPoolEntryCarriesTheHeldTradeItemAndNothingElse() throws {
        var state = CompanionState()
        state.dex = [entry(id: "coat", base: 95, final: 95, chain: [95]),
                     entry(id: "sash", base: 95, final: 95, chain: [95])]
        state.heldItems["coat"] = ItemKind.metalCoat.rawValue
        state.heldItems["sash"] = ItemKind.leftovers.rawValue
        let pool = TradePool.build(state: state, fightingIDs: [], name: { _ in "n" })
        XCTAssertEqual(pool.first { $0.id == "coat" }?.entry.tradeHeldItem, ItemKind.metalCoat.rawValue)
        XCTAssertNil(pool.first { $0.id == "sash" }?.entry.tradeHeldItem)
    }

    func testOldDexEntryWithoutTradeItemFieldsDecodes() throws {
        let data = try JSONEncoder().encode(entry(id: "o", base: 95, final: 95, chain: [95]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "tradeHeldItem")
        object.removeValue(forKey: "tradePartnerID")
        let back = try JSONDecoder().decode(DexEntry.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(back.tradeHeldItem)
        XCTAssertNil(back.tradePartnerID)
    }

    func testRaisedBattlePickAndArrivingPokemonCannotBeOffered() async throws {
        let raised = PokemonProfile.generate(seed: 5, instanceID: "raise")
        var arriving = entry(id: "arr", base: 92, final: 93, chain: [92, 93])
        arriving.tradeEvolutionPending = true
        let released = { () -> DexEntry in
            var e = entry(id: "gone", base: 25, final: 26, chain: [25, 26])
            e.releasedAt = Date(timeIntervalSince1970: 5)
            return e
        }()
        let free = entry(id: "free", base: 25, final: 26, chain: [25, 26])
        let pick = entry(id: "pick", base: 25, final: 26, chain: [25, 26])
        let store = try makeStore { state in
            state.active = MonState(baseID: 92, pathIDs: [92], stageIndex: 0, usedAtStage: 0,
                                    rarity: .common, totalForms: 2, profile: raised)
            state.dex = [arriving, released, free, pick]
        }
        XCTAssertEqual(store.tradeRefusal(for: pick, fightingIDs: ["pick"]), .fighting)
        XCTAssertEqual(store.tradeRefusal(for: arriving, fightingIDs: []), .arriving)
        XCTAssertEqual(store.tradeRefusal(for: released, fightingIDs: []), .unavailable)
        XCTAssertNil(store.tradeRefusal(for: free, fightingIDs: ["pick"]))
        XCTAssertEqual(store.tradePool(fightingIDs: ["pick"]).map(\.id), ["free"])
        XCTAssertEqual(store.tradableEntries(fightingIDs: ["pick"]).map(\.id), ["free"])
    }

    func testEveryPokemonInTheThreeSlotLineupIsRefused() throws {
        let ids = ["one", "two", "three", "spare"]
        let store = try makeStore { state in
            state.dex = ids.map { entry(id: $0, base: 25, final: 26, chain: [25, 26]) }
        }
        let slots = ["one", "two", "three"].map { BattleEntrySlot(instanceID: $0) }
        let fighting = TradePool.fightingIDs(state: store.state, slots: slots)
        XCTAssertEqual(fighting, ["one", "two", "three"])
        XCTAssertEqual(store.tradePool(fightingIDs: fighting).map(\.id), ["spare"])
        XCTAssertEqual(store.tradeRefusal(for: store.state.dex[2], fightingIDs: fighting), .fighting)
    }

    func testPoolSkipsIdsTheBotWouldRefuse() throws {
        var state = CompanionState()
        state.dex = [entry(id: "a|b", base: 25, final: 26, chain: [25, 26]),
                     entry(id: String(repeating: "x", count: 65), base: 25, final: 26, chain: [25, 26]),
                     entry(id: "ok", base: 25, final: 26, chain: [25, 26])]
        XCTAssertEqual(TradePool.build(state: state, fightingIDs: [], name: { _ in "n" }).map(\.id), ["ok"])
    }

    func testOldSaveWithoutTradeFieldsDecodesAndStaysUngated() throws {
        let json = #"{"dex":[],"inventory":{}}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertTrue(state.appliedTradeIDs.isEmpty)
        let mon = try JSONEncoder().encode(MonState(baseID: 92, pathIDs: [92], stageIndex: 0, usedAtStage: 0,
                                                    rarity: .common, totalForms: 3))
        XCTAssertNil(try JSONDecoder().decode(MonState.self, from: mon).tradeGated)
    }

    func testChainDetailsKeepHeldItemAndPartnerOfTradeMethods() throws {
        let json = """
        [{"trigger":{"name":"trade","url":null},"item":null,"held_item":{"name":"metal-coat","url":null}},
         {"trigger":{"name":"trade","url":null},"item":null,"trade_species":{"name":"karrablast","url":null}},
         {"trigger":{"name":"trade","url":null},"item":null}]
        """
        let details = try JSONDecoder().decode([EvolutionDetailDTO].self, from: Data(json.utf8))
        let methods = PokeAPIClient.methods(from: details)
        XCTAssertEqual(methods.map(\.isPlainTrade), [false, false, true])
        XCTAssertFalse(EvoNode(speciesID: 1, children: [], methods: Array(methods.prefix(2))).viaTrade)
        XCTAssertTrue(EvoNode(speciesID: 1, children: [], methods: Array(methods.suffix(1))).viaTrade)
    }

    func testTradeGatedLineKeepsGenderRateAndGenderLocks() {
        let tree = EvoNode(speciesID: 281, children: [
            EvoNode(speciesID: 282, children: [], requiredGender: nil),
            EvoNode(speciesID: 475, children: [], requiredGender: .male),
        ])
        let line = EvoLine(baseID: 281, tree: tree, rarity: .common, names: [:], genderRate: 4)
        let pruned = line.prunedTradeOnly()
        XCTAssertEqual(pruned.genderRate, 4)
        XCTAssertEqual(pruned.tree.children(for: .female).map(\.speciesID), [282])
        XCTAssertEqual(pruned.tree.children(for: .male).map(\.speciesID), [282, 475])
    }

    func testReplyDropsBadEntriesAndIgnoresUnknownKeys() throws {
        let good = try delivery(tradeID: "ok", give: "a", receiving: entry(id: "n", base: 92, final: 93, chain: [92, 93]))
        XCTAssertEqual(good.tradeID, "ok")
        let body = #"{"ok":true,"future":1,"trades":{"deliveries":[{"trade_id":"bad"},"junk"],"history":[]}}"#
        XCTAssertTrue(TradeSyncReply.decode(Data(body.utf8)).deliveries.isEmpty)
        XCTAssertTrue(TradeSyncReply.decode(Data(#"{"ok":true,"party_size":1}"#.utf8)).deliveries.isEmpty)
        XCTAssertTrue(TradeSyncReply.decode(Data("not json".utf8)).deliveries.isEmpty)
    }

    func testPartyBodyKeepsNestedKeysAndOldBotsIgnoreThePool() throws {
        let payload = PartyPayload(appVersion: "2.5.7", party: [PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)])
        XCTAssertEqual(try payload.encoded(), try payload.encoded(tradePool: nil))
        var state = CompanionState()
        state.dex = [entry(id: "keep", base: 92, final: 93, chain: [92, 93])]
        let pool = TradePool.build(state: state, fightingIDs: [], name: { _ in "고우스트" })
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload.encoded(tradePool: pool)) as? [String: Any])
        XCTAssertEqual(object["app_version"] as? String, "2.5.7")
        let wire = try XCTUnwrap((object["trade_pool"] as? [[String: Any]])?.first)
        XCTAssertEqual(wire["pokemon_id"] as? Int, 93)
        let nested = try XCTUnwrap(wire["entry"] as? [String: Any])
        XCTAssertNotNil(nested["baseID"] ?? nested["base_id"])
        XCTAssertNil(nested["base_i_d"])
        let back = try JSONDecoder().decode(DexEntry.self, from: JSONSerialization.data(withJSONObject: nested))
        XCTAssertEqual(back.id, "keep")
    }
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

@MainActor
final class TradeUploaderTests: XCTestCase {
    private func uploader(calls: Calls, tradesStatus: Int = 200, body: String,
                          applied: Calls) throws -> PartyUploader {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-up-\(UUID())")
        let tokenStore = PartyTokenStore(fileURL: dir.appendingPathComponent("token"))
        try tokenStore.save("secret-token")
        let suite = "trade-up-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set("http://127.0.0.1:1", forKey: PartyUploader.serverURLDefaultsKey)
        let trades = TradeSync(pool: { [] }, apply: { deliveries in
            deliveries.forEach { applied.add($0.tradeID) }
            return deliveries.map(\.tradeID)
        })
        return PartyUploader(tokenStore: tokenStore, defaults: defaults, appVersion: "t",
                             exchange: { _ in (Data(), 200) },
                             fetch: { request in
                                 calls.add("\(request.httpMethod ?? "GET") \(request.url?.path ?? "")")
                                 if request.url?.path == "/v1/trades", request.httpMethod == nil || request.httpMethod == "GET" {
                                     return (Data(body.utf8), tradesStatus)
                                 }
                                 return (Data(), 200)
                             },
                             partySource: { [PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)] },
                             trades: trades)
    }

    private var oneDelivery: String {
        let entry = DexEntry(id: "e", baseID: 92, finalID: 93, chainOrder: [92, 93], rarity: .common,
                             caughtAt: nil, profile: PokemonProfile.generate(seed: 1, instanceID: "e"))
        let item = TradePoolEntry(id: "e", pokemonID: 93, level: 5, shiny: false, name: "n", entry: entry)
        let pool = String(decoding: (try? JSONEncoder().encode(item)) ?? Data(), as: UTF8.self)
        return #"{"ok":true,"trades":{"deliveries":[{"trade_id":"t1","give_id":"g","from_name":"Sam","receive":\#(pool)}]}}"#
    }

    func testTickAppliesDeliveriesThenAcknowledgesThem() async throws {
        let calls = Calls(), applied = Calls()
        let up = try uploader(calls: calls, body: oneDelivery, applied: applied)
        await up.tick()
        XCTAssertEqual(applied.all, ["t1"])
        XCTAssertEqual(calls.all, ["GET /v1/trades", "POST /v1/trades/ack"])
    }

    func testTheShippedPartyReplyDecoderIgnoresTheTradesKey() throws {
        let reply = #"{"ok":true,"party_size":1,"recent_battles":[],"coworkers":[],"trades":{"deliveries":[{"trade_id":"x"}]}}"#
        XCTAssertNotNil(BattleInfo.decode(Data(reply.utf8)))
        XCTAssertNil(BattleInfo.decode(Data(#"{"ok":true,"party_size":1,"trades":{"deliveries":[]}}"#.utf8)))
    }

    func testBotWithoutTradesIsLeftAloneAfterTheFirst404() async throws {
        let calls = Calls(), applied = Calls()
        let up = try uploader(calls: calls, tradesStatus: 404, body: "{}", applied: applied)
        await up.tick()
        await up.tick(now: Date().addingTimeInterval(400))
        XCTAssertEqual(calls.all, ["GET /v1/trades"])
        XCTAssertTrue(applied.all.isEmpty)
    }

    func testNoTradesMeansNoTradeRequests() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-up-\(UUID())")
        let tokenStore = PartyTokenStore(fileURL: dir.appendingPathComponent("token"))
        try tokenStore.save("secret-token")
        let calls = Calls()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "trade-up-\(UUID())"))
        defaults.set("http://127.0.0.1:1", forKey: PartyUploader.serverURLDefaultsKey)
        let up = PartyUploader(tokenStore: tokenStore, defaults: defaults, appVersion: "t",
                               send: { request in calls.add(request.url?.path ?? ""); return 200 },
                               fetch: { _ in calls.add("fetch"); return (Data(), 200) },
                               partySource: { [PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)] })
        await up.tick()
        XCTAssertEqual(calls.all, ["/v1/party"])
    }
}
