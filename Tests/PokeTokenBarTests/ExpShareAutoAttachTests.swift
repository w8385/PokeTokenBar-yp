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
