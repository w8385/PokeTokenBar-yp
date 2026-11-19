import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct AutoAttachProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [
            EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                rarity: .common,
                names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"], 6: ["en": "Charizard"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Swapping the raised Pokémon for a shop or scout egg puts a free Exp. Share from the bag on it in the Box.
@MainActor
final class ExpShareAutoAttachTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private static let lineID = "line"
    private static let graduateID = "grad"

    private func state(inBag: Int, attachedTo holders: [String] = []) -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .en
        state.lastDate = "d1"
        state.usedSinceInstall = 90_000_000_000
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 777, rarity: .common,
                                totalForms: 3, profile: PokemonProfile.generate(seed: 4, instanceID: Self.lineID))
        state.dex = [DexEntry(id: Self.graduateID, baseID: 25, finalID: 25, chainOrder: [25], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_000),
                              profile: PokemonProfile.generate(seed: 11, instanceID: Self.graduateID),
                              names: [25: ["en": "Pikachu"]])]
        state.collectedFinals = ["25:25"]
        if inBag > 0 { state.inventory[ItemKind.expShare.rawValue] = inBag }
        state.expShareHolders = holders
        return state
    }

    private func makeStore(_ state: CompanionState) throws -> CompanionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exp-share-auto-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "exp-share-auto-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: PokemonBalance.difficultyMigratedKey)
        return CompanionStore(provider: AutoAttachProvider(), fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    func testAShopEggPutsAFreeCopyOnThePokemonGoingToTheBox() throws {
        let store = try makeStore(state(inBag: 1, attachedTo: [Self.graduateID]))
        XCTAssertTrue(store.buyEgg(nil))
        XCTAssertEqual(store.state.expShareHolders, [Self.graduateID, Self.lineID])
        XCTAssertEqual(store.itemCount(.expShare), 0)
        XCTAssertEqual(store.itemOwnedTotal(.expShare), 2)
    }

    func testAScoutEggPutsAFreeCopyOnThePokemonGoingToTheBox() throws {
        var start = state(inBag: 2)
        let pool = ScoutPool.region(.kanto)
        start.inventory[pool.inventoryKey] = 1
        start.scoutDraws[pool.key] = Array(1...10)
        let store = try makeStore(start)
        XCTAssertTrue(store.pickScout(pool, speciesID: 7))
        XCTAssertEqual(store.state.expShareHolders, [Self.lineID])
        XCTAssertEqual(store.itemCount(.expShare), 1)
    }

    func testCopiesAttachedByHandStayWhenNoneIsFree() throws {
        let store = try makeStore(state(inBag: 0, attachedTo: [Self.graduateID]))
        XCTAssertTrue(store.buyEgg(nil))
        XCTAssertEqual(store.state.expShareHolders, [Self.graduateID])
        XCTAssertEqual(store.itemOwnedTotal(.expShare), 1)
    }

    func testNothingIsAttachedWithoutAnExpShare() throws {
        let store = try makeStore(state(inBag: 0))
        XCTAssertTrue(store.buyEgg(nil))
        XCTAssertEqual(store.state.expShareHolders, [])
        XCTAssertNil(store.state.inventory[ItemKind.expShare.rawValue])
        XCTAssertEqual(store.boxIndividual(id: Self.lineID)?.role, .stored)
    }

    func testTheEggCardNoteNamesTheExpShareInEveryLanguage() {
        let en = L(.en).expShareGoesWithEggSwap
        for language in AppLanguage.allCases where language != .en {
            XCTAssertNotEqual(L(language).expShareGoesWithEggSwap, en, "\(language)")
        }
    }

    // MARK: egg card

    private func eggShop(_ store: CompanionStore) -> NSHostingView<AnyView> {
        let size = CGSize(width: PopoverMetrics.width, height: 560)
        return OffscreenRender.host(
            ShopView(store: store, nav: PopoverNavigation(), initialCategory: ItemCategory.egg)
                .environment(store).environment(\.colorScheme, .light)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: size, appearance: .aqua)
    }

    func testTheEggCardNoteFollowsAFreeCopyInTheBag() async throws {
        for (inBag, holders, shows) in [(1, [String](), true), (0, [Self.graduateID], false), (0, [], false)] {
            let store = try makeStore(state(inBag: inBag, attachedTo: holders))
            XCTAssertEqual(store.eggSwapAttachesExpShare, shows, "\(inBag) in bag, \(holders.count) attached")
            try await OffscreenRender.settle(eggShop(store))
        }
    }

    /// Opt-in PR captures: `PTB_EXPSHARE_AUTO_SHOTS=/tmp/shots swift test --filter ExpShareAutoAttachTests`.
    func testCaptureTheEggCardWithAFreeCopy() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_EXPSHARE_AUTO_SHOTS"] else {
            throw XCTSkip("Set PTB_EXPSHARE_AUTO_SHOTS for the egg card captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for language in [AppLanguage.ko, .en] {
            for inBag in [0, 1] {
                var start = state(inBag: inBag)
                start.language = language
                let host = eggShop(try makeStore(start))
                try await OffscreenRender.settle(host)
                try OffscreenRender.writePNG(of: host, to: dir.appendingPathComponent(
                    "shop-egg-expshare\(inBag)-\(language.rawValue).png"), scale: 2)
            }
        }
    }
}

/// Opt-in PR captures from the synthetic `BoxDexFixture` save plus a stored Charmander short of XP and one Exp. Share
/// in the Bag, before and after the periodic check.
///
///     PTB_BAG_EXPSHARE_SHOTS=/tmp/shots swift test --filter BagExpShareScreenshotTests
@MainActor
final class BagExpShareScreenshotTests: XCTestCase {
    static let manderID = "bag-mander"

    func testCaptureBoxBeforeAndAfterTheBagCopyGoesOn() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BAG_EXPSHARE_SHOTS"] else {
            throw XCTSkip("Set PTB_BAG_EXPSHARE_SHOTS for the bag Exp. Share captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "bag-expshare-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore(providers: [], discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil },
                               claudeUsageEntries: { _ in [] }, autoRefresh: false, defaults: defaults)
        let updater = UpdateChecker(currentVersion: "2.5.7-yp1", defaults: defaults, fetchLatest: { nil })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("bag-expshare-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: false)
        let battle = BattleEntryStore(defaults: defaults)
        let species = [4, 5, 6, 25, 95, 133]
        for id in species {
            _ = await SpriteLoader.image(speciesID: id)
            _ = await SpriteLoader.image(speciesID: id, shiny: true)
        }
        for name in ItemKind.allCases.compactMap(\.spriteName) {
            _ = await SpriteLoader.itemImage(name: name)
        }

        for language in [AppLanguage.ko, .en] {
            let tag = language.rawValue
            let (store, cleanup) = try BoxDexFixture.makeStore(language: language, mutate: {
                BoxGraduationScreenshotTests.addLine(&$0, id: Self.manderID, stage: 0, used: 10, seed: 62, at: 600)
                $0.expShareHolders = []
                $0.inventory[ItemKind.expShare.rawValue] = 1
            }, defaults: defaults)
            defer { cleanup() }
            for id in species { await store.loadPokemonDetails(speciesID: id) }
            let popover = { (nav: PopoverNavigation) in
                PopoverView(screenHeight: 5000)
                    .environment(usage).environment(store).environment(updater).environment(nav)
                    .environment(uploader).environment(battle)
                    .environment(\.colorScheme, .light)
                    .environment(\.controlActiveState, .active)
            }
            let detail = { let nav = PopoverNavigation(); nav.openBoxDetail(id: Self.manderID); return nav }

            try await shot(popover(detail()), "before-bag-expshare-detail-\(tag)", dir: dir, height: 520)
            await store.checkExpShareEvolution()
            XCTAssertEqual(store.state.expShareHolders, [Self.manderID])
            try await shot(popover(detail()), "after-bag-expshare-detail-\(tag)", dir: dir, height: 520)

            let event = try XCTUnwrap(store.latestEvent?.text)
            let text = FloatingPetView.hoverTooltip(todayTokens: 12_345_678, limitUtilization: nil, mode: .used,
                                                    l: L(language), eventLine: event)
            let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
            let callout = FloatingPetController.hoverCalloutView(text: text, appearance: appearance)
            callout.appearance = appearance
            try OffscreenRender.writePNG(of: callout, to: dir.appendingPathComponent("after-bag-expshare-notice-\(tag).png"),
                                         scale: 2)
        }
    }

    private func shot<V: View>(_ view: V, _ name: String, dir: URL, height: CGFloat) async throws {
        let width = PopoverMetrics.width
        let host = OffscreenRender.host(
            view.frame(width: width, height: height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: width, height: height), appearance: .aqua)
        try await OffscreenRender.settle(host)
        try OffscreenRender.writePNG(of: host, to: dir.appendingPathComponent("\(name).png"), scale: 2)
    }
}

/// The periodic Exp. Share check puts bag copies on the closest Pokémon that can use them, while auto move-on is on.
final class BagExpSharePassTests: StoredLineHarness {
    static let nearID = "near"
    static let farID = "far"
    static let zardID = "zard"

    func fullXP(_ mon: MonState) -> Int { PokemonBalance.scaled(mon.phaseThreshold, by: 1.0) }

    func charmander(_ id: String, short: Int, seed: UInt64) -> MonState {
        var mon = storedMon(id, path: [4, 5, 6], seed: seed)
        mon.usedAtStage = fullXP(mon) - short
        return mon
    }

    func charizard(short: Int) -> MonState {
        var mon = storedMon(Self.zardID, path: [4, 5, 6], stage: 2, seed: 73)
        mon.usedAtStage = fullXP(mon) - short
        return mon
    }

    func twoCandidates(inBag: Int) -> CompanionState {
        var state = baseState()
        store(charmander(Self.nearID, short: 5, seed: 71), in: &state, holding: false)
        store(charmander(Self.farID, short: 500, seed: 72), in: &state, holding: false)
        state.inventory[ItemKind.expShare.rawValue] = inBag
        return state
    }

    func testABagCopyGoesToTheClosestCandidateOnThePeriodicCheck() async throws {
        let store = try makeStore(twoCandidates(inBag: 1))
        store.checkEvolutionGate()
        try await waitUntil("the bag copy to go on the closest candidate") { store.state.expShareHolders == [Self.nearID] }
        XCTAssertEqual(store.itemCount(.expShare), 0)
        XCTAssertEqual(store.latestEvent?.text, store.l.expShareFromBagLine(to: "#4"))
    }

    func testTwoCopiesGoOnTwoCandidatesInOneNotice() async throws {
        let store = try makeStore(twoCandidates(inBag: 2))
        let before = store.latestEvent?.seq ?? 0
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [Self.nearID, Self.farID])
        XCTAssertEqual(store.itemCount(.expShare), 0)
        XCTAssertEqual(store.latestEvent?.seq, before + 1)
        XCTAssertEqual(store.latestEvent?.text,
                       Array(repeating: store.l.expShareFromBagLine(to: "#4"), count: 2).joined(separator: "\n"))
    }

    func testWithNoCandidateTheCopyStaysInTheBagWithoutANotice() async throws {
        var state = baseState()
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try makeStore(state)
        let before = store.latestEvent?.seq
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.itemCount(.expShare), 1)
        XCTAssertEqual(store.state.expShareHolders, [])
        XCTAssertEqual(store.latestEvent?.seq, before)
    }

    func testAStoredFinalFormShortOfGraduationXPGetsACopyAndThenGraduates() async throws {
        var state = baseState()
        store(charizard(short: 100), in: &state, holding: false)
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try makeStore(state)
        XCTAssertEqual(store.moveOnCandidates().first { $0.id == Self.zardID }?.xpLeft, 100)
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [Self.zardID])
        XCTAssertNotNil(store.state.storedLines[Self.zardID], "still short of XP")

        feed(store, 200)
        await store.checkExpShareEvolution()
        XCTAssertNil(store.state.storedLines[Self.zardID])
        XCTAssertNotNil(store.state.dex.first { $0.id == Self.zardID && !$0.isReleased })
    }

    func testAnEverstoneKeepsAStepButNotAFinalFormFromTheCandidates() async throws {
        var state = baseState()
        store(charizard(short: 100), in: &state, holding: false)
        store(charmander(Self.nearID, short: 5, seed: 71), in: &state, holding: false)
        state.heldItems[Self.zardID] = ItemKind.everstone.rawValue
        state.heldItems[Self.nearID] = ItemKind.everstone.rawValue
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try makeStore(state)
        XCTAssertEqual(store.moveOnCandidates().map(\.id), [], "its line isn't loaded yet")
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [Self.zardID])
    }

    func testAnEverstoneOnAnOldSavesPlanThatEndsMidLineKeepsItFromTheCandidates() async throws {
        var state = baseState()
        var meleon = storedMon(Self.zardID, path: [4, 5], stage: 1, seed: 73)
        meleon.usedAtStage = fullXP(meleon) - 100
        store(meleon, in: &state, holding: false)
        state.heldItems[Self.zardID] = ItemKind.everstone.rawValue
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [])
        XCTAssertEqual(store.itemCount(.expShare), 1)
    }

    func testWithMoveOnOffNothingMoves() async throws {
        let store = try makeStore(twoCandidates(inBag: 1))
        store.autoMoveOn = false
        store.checkEvolutionGate()
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.itemCount(.expShare), 1)
        XCTAssertEqual(store.state.expShareHolders, [])
    }

    func testAPokemonThePlayerTookACopyOffIsSkippedUntilThePlayerAttachesOneAgain() async throws {
        var state = twoCandidates(inBag: 0)
        state.expShareHolders = [Self.nearID]
        let store = try makeStore(state)
        XCTAssertTrue(store.detachExpShare(from: Self.nearID))
        await store.checkExpShareEvolution()
        XCTAssertEqual(store.state.expShareHolders, [Self.farID], "the copy still goes to another candidate")

        XCTAssertTrue(store.moveExpShare(from: Self.farID, to: Self.nearID))
        XCTAssertFalse(store.isExpShareTakenOff(Self.nearID))
    }

    func testACopyOnThePokemonMoveOnRaisesGoesToTheNextClosest() async throws {
        var state = twoCandidates(inBag: 0)
        var munchlax = storedMon("munch", path: [446, 143])
        munchlax.usedAtStage = fullXP(munchlax)
        state.active = munchlax
        state.expShareHolders = [Self.nearID]
        let store = try makeStore(state)
        feed(store, 0)
        try await waitUntil("the raised line to load") { store.currentLine != nil }
        store.checkEvolutionGate()
        now += CompanionStore.stuckMoveOnDelay
        store.checkEvolutionGate()
        XCTAssertEqual(store.state.active?.profile?.instanceID, Self.nearID)
        XCTAssertEqual(store.state.expShareHolders, [Self.farID])
        XCTAssertEqual(store.latestEvent?.text.components(separatedBy: "\n").last,
                       store.l.expShareMovedLine("#4", to: "#4"))
    }

    func testAnEggSwapDoesNotPutACopyBackOnAPokemonThePlayerTookOneOff() throws {
        var state = baseState()
        state.expShareHolders = [Self.lineID]
        let store = try makeStore(state)
        XCTAssertTrue(store.detachExpShare(from: Self.lineID))
        XCTAssertFalse(store.eggSwapAttachesExpShare)
        XCTAssertTrue(store.buyEgg(nil))
        XCTAssertEqual(store.state.expShareHolders, [])
        XCTAssertEqual(store.itemCount(.expShare), 1)
    }

    func testTheTakenOffMarkSurvivesASaveAndOldSavesLoadWithoutIt() throws {
        var state = baseState()
        state.expShareTakenOff = [Self.gradID]
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: data).expShareTakenOff, [Self.gradID])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["expShareTakenOff"] = nil
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: old).expShareTakenOff, [])
    }

    func testTheMarkLeavesWithItsPokemon() throws {
        var state = baseState()
        state.expShareTakenOff = [Self.gradID, "gone"]
        let store = try makeStore(state)
        store.dismissIdleTokenHint()
        XCTAssertEqual(store.state.expShareTakenOff, [Self.gradID])
    }
}
