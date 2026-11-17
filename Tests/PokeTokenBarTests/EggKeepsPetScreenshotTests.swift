import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in PR captures from the synthetic `BoxDexFixture` save: the shop egg card, then the Box after an egg is bought.
///
///     PTB_EGGBOX_SHOTS=/tmp/shots swift test --filter EggKeepsPetScreenshotTests
@MainActor
final class EggKeepsPetScreenshotTests: XCTestCase {
    func testCaptureShopEggAndBoxAfterBuying() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_EGGBOX_SHOTS"] else {
            throw XCTSkip("Set PTB_EGGBOX_SHOTS for the egg/Box captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "egg-box-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore(providers: [], discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil },
                               claudeUsageEntries: { _ in [] }, autoRefresh: false, defaults: defaults)
        let updater = UpdateChecker(currentVersion: "2.5.7-yp1", defaults: defaults, fetchLatest: { nil })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("egg-box-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: false)
        let battle = BattleEntryStore(defaults: defaults)
        for id in [5, 25, 6, 95, 133] {
            _ = await SpriteLoader.image(speciesID: id)
            _ = await SpriteLoader.image(speciesID: id, shiny: true)
        }

        for language in [AppLanguage.ko, .en] {
            let (store, cleanup) = try BoxDexFixture.makeStore(language: language, defaults: defaults)
            defer { cleanup() }
            for id in [5, 25, 6, 95, 133] { await store.loadPokemonDetails(speciesID: id) }
            func popover(_ nav: PopoverNavigation) -> some View {
                PopoverView(screenHeight: 5000)
                    .environment(usage).environment(store).environment(updater).environment(nav)
                    .environment(uploader).environment(battle)
                    .environment(\.colorScheme, .light)
                    .environment(\.controlActiveState, .active)
            }
            let tag = language.rawValue
            try await shot(ShopView(store: store, nav: PopoverNavigation(), initialCategory: ItemCategory.egg)
                .environment(store).environment(\.colorScheme, .light), "shop-egg-\(tag)", dir: dir, height: 560)

            let raising = PopoverNavigation(); raising.openBoxDetail(id: BoxDexFixture.raisedID)
            try await shot(popover(raising), "box-raising-detail-\(tag)", dir: dir, height: 700)

            XCTAssertTrue(store.buyEgg(nil))
            if let record = store.state.dex.first(where: { $0.id == BoxDexFixture.raisedID }) {
                _ = await store.dexResolveChainNames(record)
            }
            let box = PopoverNavigation(); box.tab = .box
            try await shot(popover(box), "box-after-egg-\(tag)", dir: dir, height: 520)
            if store.boxIndividual(id: BoxDexFixture.raisedID) != nil {
                let detail = PopoverNavigation(); detail.openBoxDetail(id: BoxDexFixture.raisedID)
                try await shot(popover(detail), "box-stored-detail-\(tag)", dir: dir, height: 700)
            }
        }
    }

    /// Sprites are loaded before the view is built, so a few run-loop turns are enough for `.task` work to land.
    private func shot<V: View>(_ view: V, _ name: String, dir: URL, height: CGFloat) async throws {
        let width = PopoverMetrics.width
        let host = OffscreenRender.host(
            view.frame(width: width, height: height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: width, height: height), appearance: .aqua)
        for _ in 0..<200 {
            await Task.yield()
            host.layoutSubtreeIfNeeded()
        }
        try OffscreenRender.writePNG(of: host, to: dir.appendingPathComponent("\(name).png"), scale: 2)
    }
}
