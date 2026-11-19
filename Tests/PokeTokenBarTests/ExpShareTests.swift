import XCTest
@testable import PokeTokenBar

private func levelUp(_ id: Int, _ children: [EvoNode] = []) -> EvoNode {
    EvoNode(speciesID: id, children: children, methods: [EvoMethod(trigger: "level-up")])
}

private struct ExpShareProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        switch baseSpeciesID {
        case 704:
            return EvoLine(baseID: 704, tree: levelUp(704, [levelUp(705, [levelUp(706)])]), rarity: .common,
                           names: [704: ["en": "Goomy"], 705: ["en": "Sliggoo"], 706: ["en": "Goodra"]])
        case 25:
            return EvoLine(baseID: 25, tree: levelUp(25), rarity: .common, names: [25: ["en": "Pikachu"]])
        default:
            return EvoLine(baseID: 4, tree: levelUp(4, [levelUp(5, [levelUp(6)])]), rarity: .common,
                           names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"], 6: ["en": "Charizard"]])
        }
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Exp. Share gives a Box Pokémon half of what the raised Pokémon earns, and never changes the raised one.
@MainActor
final class ExpShareTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    nonisolated(unsafe) private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var fed: [ObjectIdentifier: Int] = [:]
    private static let lineID = "line"
    private static let pikachuID = "pika"
    private static let sliggooID = "sliggoo"

    private func baseState() -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .en
        state.claimedTodayTokensByProvider = ["test": 0]
        state.lastDate = "d1"
        state.usedSinceInstall = 90_000_000_000
        var profile = PokemonProfile.generate(seed: 4, instanceID: Self.lineID)
        profile.level = 20
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 0, rarity: .common,
                                totalForms: 3, profile: profile)
        var pikachu = PokemonProfile.generate(seed: 11, instanceID: Self.pikachuID)
        pikachu.level = 30
        var sliggoo = PokemonProfile.generate(seed: 12, instanceID: Self.sliggooID)
        sliggoo.level = 40
        state.dex = [
            DexEntry(id: Self.pikachuID, baseID: 25, finalID: 25, chainOrder: [25], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_000), profile: pikachu, names: [25: ["en": "Pikachu"]]),
            DexEntry(id: Self.sliggooID, baseID: 704, finalID: 705, chainOrder: [704, 705], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 2_000), profile: sliggoo,
                     names: [704: ["en": "Goomy"], 705: ["en": "Sliggoo"]]),
        ]
        state.collectedFinals = ["25:25", "704:705"]
        return state
    }

    private func makeStore(_ state: CompanionState) throws -> CompanionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exp-share-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "exp-share-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return CompanionStore(provider: ExpShareProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    private func holding(_ ids: String...) -> CompanionState {
        var state = baseState()
        state.expShareHolders = ids
        return state
    }

    /// Real token usage through the same path the app takes.
    private func feed(_ store: CompanionStore, _ tokens: Int) {
        let total = fed[ObjectIdentifier(store), default: 0] + tokens
        fed[ObjectIdentifier(store)] = total
        store.update(todayTokensByProvider: ["test": total], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
    }

    private func entry(_ store: CompanionStore, _ id: String) throws -> DexEntry {
        try XCTUnwrap(store.state.dex.first { $0.id == id })
    }

    private func growth(_ store: CompanionStore, _ id: String) throws -> Int {
        try XCTUnwrap(entry(store, id).profile?.growthTokens)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try XCTUnwrap(String(data: encoder.encode(value), encoding: .utf8))
    }

    // MARK: shop

    func testTheSecondCopyCostsTheSecondPrice() throws {
        let store = try makeStore(baseState())
        XCTAssertEqual(ItemKind.expShare.shopPrice, ExpShare.prices[0])
        XCTAssertEqual(ItemKind.expShare.category, .growth)
        XCTAssertFalse(ItemKind.expShare.isEquippable)
        XCTAssertTrue(store.purchasableItems.contains(.expShare))
        let first = ExpShare.prices[0]
        let second = ExpShare.prices[1]
        XCTAssertEqual(store.price(of: .expShare), first)

        let spent = store.state.spentTokens
        XCTAssertTrue(store.buy(.expShare))
        XCTAssertEqual(store.state.spentTokens, spent + first)
        XCTAssertTrue(store.attachExpShare(to: Self.pikachuID))
        XCTAssertEqual(store.price(of: .expShare), second, "an attached copy still counts")
        XCTAssertTrue(store.buy(.expShare))
        XCTAssertEqual(store.state.spentTokens, spent + first + second)
    }

    func testTheShopSellsAtMostTwoOneAtATimeCountingAttachedCopies() throws {
        let store = try makeStore(baseState())
        XCTAssertEqual(ExpShare.maxOwned, 2)
        XCTAssertEqual(store.maxBuyCount(.expShare), 1)
        XCTAssertFalse(store.buy(.expShare, count: 2))
        XCTAssertTrue(store.buy(.expShare))
        XCTAssertEqual(store.maxBuyCount(.expShare), 1)
        XCTAssertTrue(store.attachExpShare(to: Self.pikachuID))
        XCTAssertEqual(store.maxBuyCount(.expShare), 1)
        XCTAssertTrue(store.buy(.expShare))
        XCTAssertEqual(store.itemOwnedTotal(.expShare), 2)
        XCTAssertTrue(store.isSoldOut(.expShare))
        XCTAssertFalse(store.canBuy(.expShare))
        XCTAssertTrue(store.detachExpShare(from: Self.pikachuID))
        XCTAssertEqual(store.itemCount(.expShare), 2)
        XCTAssertTrue(store.isSoldOut(.expShare))
        XCTAssertTrue(store.attachExpShare(to: Self.sliggooID))
        XCTAssertEqual(store.itemCount(.expShare), 1)
    }

    // MARK: attaching

    func testAttachDetachAndMoveLeaveTheHeldItemAlone() throws {
        var state = baseState()
        state.inventory[ItemKind.expShare.rawValue] = 1
        state.heldItems[Self.pikachuID] = ItemKind.focusSash.rawValue
        let store = try makeStore(state)

        XCTAssertTrue(store.attachExpShare(to: Self.pikachuID))
        XCTAssertEqual(store.itemCount(.expShare), 0)
        XCTAssertTrue(store.holdsExpShare(Self.pikachuID))
        XCTAssertFalse(store.attachExpShare(to: Self.sliggooID), "the bag is empty")
        XCTAssertEqual(store.state.heldItems[Self.pikachuID], ItemKind.focusSash.rawValue)

        XCTAssertTrue(store.detachExpShare(from: Self.pikachuID))
        XCTAssertTrue(store.attachExpShare(to: Self.sliggooID))
        XCTAssertEqual(store.state.expShareHolders, [Self.sliggooID])
        XCTAssertEqual(store.state.heldItems[Self.pikachuID], ItemKind.focusSash.rawValue)
        XCTAssertFalse(store.detachExpShare(from: Self.pikachuID))
    }

    func testThePokemonBeingRaisedOrRestingCannotTakeOne() throws {
        var state = baseState()
        state.inventory[ItemKind.expShare.rawValue] = 2
        let store = try makeStore(state)
        XCTAssertFalse(store.canAttachExpShare(to: Self.lineID), "raising")
        XCTAssertTrue(store.raise(entryID: Self.pikachuID))
        XCTAssertFalse(store.canAttachExpShare(to: Self.pikachuID), "raising")
        XCTAssertFalse(store.canAttachExpShare(to: Self.lineID), "resting")
        XCTAssertTrue(store.canAttachExpShare(to: Self.sliggooID))
    }

    // MARK: sharing

    func testAHolderGetsHalfAndTheLineMainIsUnchanged() throws {
        let plain = try makeStore(baseState())
        let shared = try makeStore(holding(Self.pikachuID))
        let before = try growth(shared, Self.pikachuID)
        feed(plain, 4_000_001)
        feed(shared, 4_000_001)

        XCTAssertEqual(try json(shared.state.active), try json(plain.state.active))
        XCTAssertEqual(try growth(shared, Self.pikachuID), before + 2_000_000)
        XCTAssertEqual(try growth(plain, Self.pikachuID), before)
    }

    func testAHolderSharesARaisedGraduateMainToo() throws {
        let plain = try makeStore(baseState())
        let shared = try makeStore(holding(Self.sliggooID))
        XCTAssertTrue(plain.raise(entryID: Self.pikachuID))
        XCTAssertTrue(shared.raise(entryID: Self.pikachuID))
        let before = try growth(shared, Self.sliggooID)
        feed(plain, 3_000_000)
        feed(shared, 3_000_000)

        XCTAssertEqual(try growth(shared, Self.sliggooID), before + 1_500_000)
        XCTAssertEqual(try json(entry(shared, Self.pikachuID)), try json(entry(plain, Self.pikachuID)))
        XCTAssertEqual(try json(shared.state.active), try json(plain.state.active), "the resting line gets nothing")
    }

    func testAHolderGetsHalfWhileAnEggIncubatesAndTheEggIsUnchanged() throws {
        var plainState = baseState()
        plainState.active = nil
        var sharedState = holding(Self.pikachuID)
        sharedState.active = nil
        let plain = try makeStore(plainState)
        let shared = try makeStore(sharedState)
        let before = try growth(shared, Self.pikachuID)
        feed(plain, 3_000_000)
        feed(shared, 3_000_000)

        XCTAssertEqual(shared.state.eggUsage, 3_000_000)
        XCTAssertEqual(shared.state.eggUsage, plain.state.eggUsage)
        XCTAssertEqual(try growth(shared, Self.pikachuID), before + 1_500_000)
    }

    func testTheOldPokemonKeepsGrowingWhileTheNewEggIncubates() throws {
        let store = try makeStore(baseState())
        XCTAssertTrue(store.buyEgg(nil))
        XCTAssertTrue(store.buy(.expShare))
        XCTAssertTrue(store.attachExpShare(to: Self.lineID))
        let before = try XCTUnwrap(store.state.storedLines[Self.lineID]?.mon)
        let eggBefore = store.state.eggUsage

        feed(store, 4_000_000)
        XCTAssertNil(store.state.active)
        XCTAssertEqual(store.state.eggUsage, eggBefore + 4_000_000)
        XCTAssertEqual(try XCTUnwrap(store.state.storedLines[Self.lineID]?.mon).usedAtStage, before.usedAtStage + 2_000_000)
    }

    func testAHolderBeingRaisedGetsNoDoubleShare() throws {
        let plain = try makeStore(baseState())
        let shared = try makeStore(holding(Self.pikachuID))
        XCTAssertTrue(plain.raise(entryID: Self.pikachuID))
        XCTAssertTrue(shared.raise(entryID: Self.pikachuID))
        feed(plain, 3_000_000)
        feed(shared, 3_000_000)
        XCTAssertEqual(try growth(shared, Self.pikachuID), try growth(plain, Self.pikachuID))
        XCTAssertTrue(shared.holdsExpShare(Self.pikachuID), "it keeps the item while raised")
    }

    // MARK: evolving

    func testAGraduateHolderEvolvesUnderTheGraduateGateWithoutTheHomeCelebration() async throws {
        let store = try makeStore(holding(Self.sliggooID))
        await store.checkExpShareEvolution()
        XCTAssertEqual(try entry(store, Self.sliggooID).finalID, 705, "Goodra needs rain or a long stage")
        XCTAssertNotNil(store.expShareLines[704])

        feed(store, 2_000_000)
        XCTAssertEqual(store.state.graduateEvolution[Self.sliggooID]?.graduateXP, 1_000_000)
        XCTAssertEqual(try entry(store, Self.sliggooID).finalID, 705)

        feed(store, 2_000_000_000)
        XCTAssertEqual(try entry(store, Self.sliggooID).finalID, 706)
        XCTAssertTrue(store.state.collectedFinals.contains("704:706"))
        XCTAssertNil(store.justEvolvedTo, "the home screen belongs to the raised Pokémon")
    }

    func testAHolderWhoseSavedProgressIsEnoughEvolvesOnTheTick() async throws {
        var state = holding(Self.sliggooID)
        var progress = EvolutionProgress(spentBaseline: 0)
        progress.graduateXP = 2_000_000_000
        state.graduateEvolution[Self.sliggooID] = progress
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertEqual(try entry(store, Self.sliggooID).finalID, 706)
        XCTAssertNil(store.justEvolvedTo)
    }

    func testAFinalFormHolderOnlyLevels() async throws {
        let store = try makeStore(holding(Self.pikachuID))
        await store.checkExpShareEvolution()
        let level = try XCTUnwrap(entry(store, Self.pikachuID).profile?.level)
        feed(store, 2_000_000_000)
        XCTAssertEqual(try entry(store, Self.pikachuID).finalID, 25)
        XCTAssertGreaterThan(try XCTUnwrap(entry(store, Self.pikachuID).profile?.level), level)
        XCTAssertNil(store.state.graduateEvolution[Self.pikachuID])
    }

    func testAStoredHolderBanksTheShareInItsStage() async throws {
        let store = try makeStore(baseState())
        XCTAssertTrue(store.buyEgg(nil))
        await store.hatch(baseID: 4)
        XCTAssertTrue(store.buy(.expShare))
        XCTAssertTrue(store.attachExpShare(to: Self.lineID))
        let before = try XCTUnwrap(store.state.storedLines[Self.lineID]?.mon)

        feed(store, 4_000_000)
        let after = try XCTUnwrap(store.state.storedLines[Self.lineID]?.mon)
        XCTAssertEqual(after.usedAtStage, before.usedAtStage + 2_000_000)
        XCTAssertEqual(after.stageIndex, before.stageIndex, "still below its stage threshold")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(after.profile?.growthTokens), try XCTUnwrap(before.profile?.growthTokens))

        XCTAssertTrue(store.raise(entryID: Self.lineID))
        XCTAssertEqual(store.state.active?.usedAtStage, after.usedAtStage)
        XCTAssertTrue(store.holdsExpShare(Self.lineID))
    }

    // MARK: saves

    func testAHolderThatIsGoneGivesTheCopyBack() throws {
        let store = try makeStore(holding(Self.pikachuID, "traded-away", Self.pikachuID))
        XCTAssertEqual(store.state.expShareHolders, [Self.pikachuID])
        XCTAssertEqual(store.itemCount(.expShare), 2)
    }

    func testAnOldOrBrokenSaveDecodesWithNoHolders() throws {
        let data = try JSONEncoder().encode(baseState())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["expShareHolders"] = nil
        let old = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.expShareHolders, [])
        object["expShareHolders"] = 7
        let broken = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(broken.expShareHolders, [])
        XCTAssertEqual(broken.dex.count, 2)
    }
}
