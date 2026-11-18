import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Move training before and after the Mirror Herb, and its Shop entry, for the PR. Synthetic save and bot replies.
/// Writes only when `PTB_PARITY_SHOT_DIR` is set.
@MainActor
final class MirrorHerbScreenshotTests: XCTestCase {
    func testCaptureMirrorHerb() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_PARITY_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_PARITY_SHOT_DIR")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for language in [AppLanguage.ko, .en] {
            let suffix = language == .ko ? "-ko" : "-en"
            let rig = try await TrainingRig(eggMovesJSON: eggMovesJSON, language: language)
            defer { rig.close() }

            let locked = try await rig.mount(rig.section("pikachu"), height: 1000)
            _ = try await rig.chooseRows(in: locked, count: 2)
            try await OffscreenRender.waitUntil("the locked egg group", in: locked) {
                rig.fetches.all.contains { $0.contains("egg=1") }
            }
            try await OffscreenRender.settle(locked)
            try OffscreenRender.writePNG(of: locked, to: dir.appendingPathComponent("egg-moves-locked\(suffix).png"),
                                         scale: 2)

            XCTAssertEqual(rig.store.useMirrorHerb(on: "pikachu"), .changed)
            let unlocked = try await rig.mount(rig.section("pikachu"), height: 1000)
            _ = try await rig.chooseRows(in: unlocked, count: 3)
            try OffscreenRender.writePNG(of: unlocked, to: dir.appendingPathComponent("egg-moves-unlocked\(suffix).png"),
                                         scale: 2)

            try await capture(ShopItemCard(store: rig.store, kind: .mirrorHerb).padding(12).environment(rig.store),
                              height: 150, to: dir.appendingPathComponent("shop-mirror-herb\(suffix).png"))
        }
    }

    private func capture<V: View>(_ view: V, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light),
            size: size, appearance: .aqua, scale: 2, to: file)
    }
}
