import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in PR captures from the synthetic `BoxDexFixture` save: the shop card, the Box page control and the Box mark.
///
///     PTB_EXPSHARE_SHOTS=/tmp/shots swift test --filter ExpShareScreenshotTests
@MainActor
final class ExpShareScreenshotTests: XCTestCase {
    func testCaptureShopCardBoxControlAndMark() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_EXPSHARE_SHOTS"] else {
            throw XCTSkip("Set PTB_EXPSHARE_SHOTS for the Exp. Share captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "exp-share-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore.offline(providers: [], defaults: defaults)
        let updater = UpdateChecker(currentVersion: "2.5.7-yp1", defaults: defaults, fetchLatest: { nil })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("exp-share-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: false)
        let battle = BattleEntryStore(defaults: defaults)
        let species = [5, 25, 6, 95, 133]
        for id in species {
            _ = await SpriteLoader.image(speciesID: id)
            _ = await SpriteLoader.image(speciesID: id, shiny: true)
        }
        for name in ItemKind.allCases.compactMap(\.spriteName) {
            _ = await SpriteLoader.itemImage(name: name)
        }

        for language in [AppLanguage.ko, .en] {
            let tag = language.rawValue
            let (plain, cleanPlain) = try BoxDexFixture.makeStore(language: language, defaults: defaults)
            defer { cleanPlain() }
            let (store, cleanup) = try BoxDexFixture.makeStore(language: language, mutate: {
                $0.inventory[ItemKind.expShare.rawValue] = 1
                $0.expShareHolders = [BoxDexFixture.pikachuID]
            }, defaults: defaults)
            defer { cleanup() }
            for id in species {
                await plain.loadPokemonDetails(speciesID: id)
                await store.loadPokemonDetails(speciesID: id)
            }
            func popover(_ s: CompanionStore, _ nav: PopoverNavigation) -> some View {
                PopoverView(screenHeight: 5000)
                    .environment(usage).environment(s).environment(updater).environment(nav)
                    .environment(uploader).environment(battle)
                    .environment(\.colorScheme, .light)
                    .environment(\.controlActiveState, .active)
            }
            func detail(_ id: String) -> PopoverNavigation {
                let nav = PopoverNavigation(); nav.openBoxDetail(id: id); return nav
            }
            let box = { let nav = PopoverNavigation(); nav.tab = .box; return nav }

            for owned in 0..<ExpShare.maxOwned {
                let (shop, cleanShop) = try BoxDexFixture.makeStore(language: language, mutate: {
                    $0.inventory[ItemKind.shinyCharm.rawValue] = 1
                    $0.inventory[ItemKind.expShare.rawValue] = owned > 0 ? owned : nil
                }, defaults: defaults)
                defer { cleanShop() }
                try await shot(ShopView(store: shop, nav: PopoverNavigation(), initialCategory: ItemCategory.growth)
                    .environment(shop).environment(\.colorScheme, .light), "shop-growth-owned\(owned)-\(tag)", dir: dir, height: 560)
            }
            try await shot(popover(plain, box()), "before-box-\(tag)", dir: dir, height: 520)
            try await shot(popover(plain, detail(BoxDexFixture.onixID)), "before-box-detail-\(tag)", dir: dir, height: 520)

            try await shot(popover(store, box()), "box-mark-\(tag)", dir: dir, height: 520)
            try await shot(popover(store, detail(BoxDexFixture.onixID)), "box-attach-\(tag)", dir: dir, height: 520)
            try await shot(popover(store, detail(BoxDexFixture.pikachuID)), "box-holding-\(tag)", dir: dir, height: 520)
        }
    }

    /// Sprites and item icons are cached before the view is built, so the first layout already draws them.
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
