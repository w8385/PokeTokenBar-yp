import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in PR captures from the synthetic `BoxDexFixture` save plus a Bulbasaur waiting in the Box.
///
///     PTB_STORED_FRIEND_SHOTS=/tmp/shots swift test --filter StoredFriendScreenshotTests
@MainActor
final class StoredFriendScreenshotTests: XCTestCase {
    static let bulbasaurID = "bulbasaur"

    static func addBulbasaur(_ state: inout CompanionState) {
        var profile = PokemonProfile.generate(seed: 1, instanceID: bulbasaurID)
        profile.level = 18
        let mon = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1, 2, 3], stageIndex: 0,
                           usedAtStage: 0, rarity: .common, totalForms: 3, profile: profile)
        state.storedLines[bulbasaurID] = StoredLine(mon: mon, spentAtStore: 0)
        state.dex.append(DexEntry(id: bulbasaurID, baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 1_700_000_500), profile: profile,
                                  names: [1: ["ko": "이상해씨", "en": "Bulbasaur"]],
                                  releasedAt: Date(timeIntervalSince1970: 1_700_000_600)))
    }

    func testCaptureStoredFriendPickerPetRowSwapNoteAndMovePicker() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_STORED_FRIEND_SHOTS"] else {
            throw XCTSkip("Set PTB_STORED_FRIEND_SHOTS for the stored-friend captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "stored-friend-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore(providers: [], discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil },
                               claudeUsageEntries: { _ in [] }, autoRefresh: false, defaults: defaults)
        let updater = UpdateChecker(currentVersion: "2.5.7-yp1", defaults: defaults, fetchLatest: { nil })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("stored-friend-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: false)
        let battle = BattleEntryStore(defaults: defaults)
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))
        let species = [1, 5, 6, 25, 95, 133]
        for id in species {
            _ = await SpriteLoader.image(speciesID: id)
            _ = await SpriteLoader.image(speciesID: id, shiny: true)
            for shiny in [false, true] {
                for female in [false, true] {
                    _ = await SpriteLoader.animationFrames(speciesID: id, shiny: shiny, store: sprites, female: female)
                }
            }
        }
        for name in ItemKind.allCases.compactMap(\.spriteName) {
            _ = await SpriteLoader.itemImage(name: name)
        }

        for language in [AppLanguage.ko, .en] {
            let tag = language.rawValue
            let (store, cleanup) = try BoxDexFixture.makeStore(language: language, mutate: {
                Self.addBulbasaur(&$0)
                $0.expShareHolders = [BoxDexFixture.pikachuID, BoxDexFixture.onixID]
            }, defaults: defaults)
            defer { cleanup() }
            for id in species { await store.loadPokemonDetails(speciesID: id) }

            try await shot(FriendPicker(store: store, spriteStore: sprites) {}.environment(store),
                           "friend-picker-\(tag)", dir: dir, width: 300, height: 200)
            try await shot(ShopView(store: store, nav: PopoverNavigation(), initialCategory: .egg)
                .environment(store).environment(\.colorScheme, .light), "shop-egg-swap-\(tag)", dir: dir, height: 560)

            let popover = { (nav: PopoverNavigation) in
                PopoverView(screenHeight: 5000)
                    .environment(usage).environment(store).environment(updater).environment(nav)
                    .environment(uploader).environment(battle)
                    .environment(\.colorScheme, .light)
                    .environment(\.controlActiveState, .active)
            }
            let detail = PopoverNavigation()
            detail.openBoxDetail(id: Self.bulbasaurID)
            try await shot(popover(detail), "box-detail-move-here-\(tag)", dir: dir, height: 520)
            try await shot(ExpShareMovePicker(store: store, targetID: Self.bulbasaurID) {}.environment(store),
                           "exp-share-move-picker-\(tag)", dir: dir, width: 260, height: 140)

            XCTAssertTrue(store.addFriend(entryID: Self.bulbasaurID))
            try await shot(CompanionHeader(store: store, spriteStore: sprites).padding(12)
                .environment(store).environment(usage), "home-stored-friend-\(tag)", dir: dir,
                width: PopoverMetrics.contentWidth, height: 150)
            let crowd = PetCrowd(settle: .seconds(120))
            crowd.configure(order: [1, 0, 2], motionAllowed: true, active: false)
            crowd.friendsOnLeft = true
            let layout = PetRowLayout(friendCount: 2, friendsOnLeft: true)
            let panel = FloatingPetController.panelSize(petSize: CGFloat(usage.floatingPetSize), showingBubble: false,
                                                        layout: layout)
            try await shot(FloatingPetView(animated: false, spriteStore: sprites, crowd: crowd)
                .environment(usage).environment(store), "floating-stored-friend-\(tag)", dir: dir,
                width: panel.width, height: panel.height, background: .white)
        }
    }

    private func shot<V: View>(_ view: V, _ name: String, dir: URL, width: CGFloat = PopoverMetrics.width,
                               height: CGFloat, background: Color = Color(nsColor: .windowBackgroundColor)) async throws {
        let host = OffscreenRender.host(
            view.frame(width: width, height: height, alignment: .top).background(background),
            size: CGSize(width: width, height: height), appearance: .aqua)
        try await OffscreenRender.settle(host)
        try OffscreenRender.writePNG(of: host, to: dir.appendingPathComponent("\(name).png"), scale: 2)
    }
}
