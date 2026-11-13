import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct EeveeProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        let stones: [(Int, String)] = [(134, "water-stone"), (135, "thunder-stone"), (136, "fire-stone")]
        let kids = stones.map {
            EvoNode(speciesID: $0.0, children: [], methods: [EvoMethod(trigger: "use-item", item: $0.1)])
        }
        return EvoLine(baseID: 133, tree: EvoNode(speciesID: 133, children: kids), rarity: .rare,
                       names: [133: ["ko": "이브이"], 134: ["ko": "샤미드"], 135: ["ko": "쥬피썬더"],
                               136: ["ko": "부스터"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures for the PR (synthetic save, real views):
///
///     PTB_EVO_SCREENSHOT_DIR=/tmp/shots swift test --filter EvolutionStoneScreenshotTests
@MainActor
final class EvolutionStoneScreenshotTests: XCTestCase {
    func testCaptureShopBagAndEvolution() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_EVO_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_EVO_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("evo-shot-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 6_000_000_000
        state.inventory[ItemKind.waterStone.rawValue] = 1
        state.inventory[ItemKind.moonStone.rawValue] = 1
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: EeveeProvider(), fileURL: file, dittoDisguiseRollingEnabled: false)
        await store.hatch(baseID: 133)

        try await capture(ShopView(store: store, nav: PopoverNavigation()), scrollToBottom: true,
                          to: directory.appendingPathComponent("evo-shop-stones.png"))
        try await capture(CompanionHeader(store: store), height: 300,
                          to: directory.appendingPathComponent("evo-before.png"))
        XCTAssertEqual(store.useEvolutionStone(.moonStone), .wrongStone)
        XCTAssertEqual(store.useEvolutionStone(.waterStone), .evolved)
        try await capture(CompanionHeader(store: store), height: 300,
                          to: directory.appendingPathComponent("evo-after-water-stone.png"))
    }

    private func capture<V: View>(_ view: V, height: CGFloat = 520, scrollToBottom: Bool = false,
                                  to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .seconds(5))
        host.layoutSubtreeIfNeeded()
        if scrollToBottom, let scroll = Self.scrollView(in: host), let doc = scroll.documentView {
            doc.scroll(NSPoint(x: 0, y: max(0, doc.bounds.height - 1150)))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .seconds(1))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = scrollView(in: sub) { return found } }
        return nil
    }
}
