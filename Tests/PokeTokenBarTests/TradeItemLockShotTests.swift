import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.badServerResponse) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in capture for the PR: a synthetic save, the real battle tab.
///
///     PTB_TRADE_SCREENSHOT_DIR=/tmp/shots swift test --filter TradeItemLockShotTests
@MainActor
final class TradeItemLockShotTests: XCTestCase {
    func testCaptureTheHeldItemRowBeforeAndWhileListed() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_TRADE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_TRADE_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("trade-lock-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: raised)
        var profile = PokemonProfile.generate(seed: 95, instanceID: "onix")
        profile.level = 41
        state.dex = [DexEntry(id: "onix", baseID: 95, finalID: 95, chainOrder: [95], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false,
                              profile: profile, names: [95: ["ko": "롱스톤"]])]
        state.heldItems["onix"] = ItemKind.metalCoat.rawValue
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: ShotProvider(), fileURL: file)

        let defaults = UserDefaults(suiteName: "trade-lock-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        battle.add("onix")
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 200) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        func view() -> some View {
            BattleView(store: store, navigation: PopoverNavigation(), initialPickerQuery: "")
                .environment(uploader).environment(battle).environment(store)
        }
        try await capture(view(), to: directory.appendingPathComponent("held-item-before.png"))
        store.setTradeLocked(["onix"])
        try await capture(view(), to: directory.appendingPathComponent("held-item-listed.png"))
    }

    private func capture<V: View>(_ view: V, to file: URL, height: CGFloat = 700) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top)
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
        try await Task.sleep(for: .seconds(3))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
