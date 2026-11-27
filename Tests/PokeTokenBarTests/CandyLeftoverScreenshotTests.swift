import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in PR captures from the synthetic `BoxDexFixture` save: the Bag's candy preview without and with Exp. Share
/// holders, and the home line after the batch.
///
///     PTB_CANDY_LEFTOVER_SHOTS=/tmp/shots swift test --filter CandyLeftoverScreenshotTests
@MainActor
final class CandyLeftoverScreenshotTests: XCTestCase {
    func testCaptureBagPreviewAndHomeLine() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_CANDY_LEFTOVER_SHOTS"] else {
            throw XCTSkip("Set PTB_CANDY_LEFTOVER_SHOTS for the candy leftover captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "candy-leftover-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore.offline(providers: [], defaults: defaults)
        let updater = UpdateChecker(currentVersion: "2.5.7-yp1", defaults: defaults, fetchLatest: { nil })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("candy-leftover-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: false)
        let battle = BattleEntryStore(defaults: defaults)
        for id in [4, 5, 6, 25, 95] {
            _ = await SpriteLoader.image(speciesID: id)
            _ = await SpriteLoader.image(speciesID: id, shiny: true)
        }
        for name in ItemKind.allCases.compactMap(\.spriteName) {
            _ = await SpriteLoader.itemImage(name: name)
        }

        for language in [AppLanguage.ko, .en, .ja] {
            let tag = language.rawValue
            for (name, holders) in [("before", [String]()), ("after", [BoxDexFixture.pikachuID, BoxDexFixture.onixID])] {
                let (store, cleanup) = try BoxDexFixture.makeStore(language: language, mutate: {
                    $0.inventory[ItemKind.rareCandy.rawValue] = 3
                    $0.expShareHolders = holders
                }, defaults: defaults)
                defer { cleanup() }
                await store.loadCurrentLine()
                XCTAssertTrue(try XCTUnwrap(store.planRareCandyUse(count: 3)).graduates)
                try await shot(BagView(store: store, nav: PopoverNavigation(), initialCategory: ItemKind.rareCandy.category)
                    .environment(store).environment(\.colorScheme, .light), "\(name)-bag-\(tag)", dir: dir, height: 420)
                guard !holders.isEmpty else { continue }
                XCTAssertEqual(store.useRareCandy(count: 3), .graduated)
                let nav = PopoverNavigation()
                try await shot(PopoverView(screenHeight: 5000)
                    .environment(usage).environment(store).environment(updater).environment(nav)
                    .environment(uploader).environment(battle)
                    .environment(\.colorScheme, .light)
                    .environment(\.controlActiveState, .active), "after-home-\(tag)", dir: dir, height: 520)
            }
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
