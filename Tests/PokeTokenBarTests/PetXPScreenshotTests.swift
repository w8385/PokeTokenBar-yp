import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in README capture: Home after five fast clicks, the "+XP" badge showing their sum. Sample data.
///
///     PTB_PET_XP_SHOT_DIR=/tmp/shots swift test --filter PetXPScreenshotTests
@MainActor
final class PetXPScreenshotTests: XCTestCase {
    func testCaptureSummedXPBadgeAfterFastClicks() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_PET_XP_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_PET_XP_SHOT_DIR to draw the README image")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "pet-xp-shot-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore.offline(providers: [], defaults: defaults)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("pet-xp-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))

        for (language, suffix) in [(AppLanguage.en, ""), (.ko, "-ko"), (.ja, "-ja")] {
            let (store, cleanup) = try BoxDexFixture.makeStore(language: language, defaults: defaults)
            defer { cleanup() }
            store.update(todayTokensByProvider: ["claude_code": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                         limitWarning: false, hasUsageData: true)
            try await waitUntil("Charmeleon's line to load") { store.currentLine != nil }
            await ReadmeScreenshotTests.preloadHeaderSprites(of: store, into: sprites)
            var flash = XPFlash()
            for _ in 0..<5 { _ = flash.show(store.growByClick()) }
            XCTAssertEqual(flash.amount, 5 * ClickGrowth.tokensPerClick)
            let header = CompanionHeader(store: store, spriteStore: sprites, xpFlash: flash).padding(12)
                .environment(store).environment(usage)
                .environment(\.locale, language.displayLocale)
            let size = CGSize(width: PopoverMetrics.contentWidth, height: 150)
            let host = OffscreenRender.host(
                header.frame(width: size.width, height: size.height, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor)),
                size: size, appearance: .aqua)
            try await OffscreenRender.settle(host)
            try OffscreenRender.writePNG(of: host, to: dir.appendingPathComponent("screenshot-pet-xp\(suffix).png"),
                                         scale: 2)
        }
    }
}
