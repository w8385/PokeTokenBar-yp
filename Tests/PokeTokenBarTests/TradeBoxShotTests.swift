import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in captures for the PR: synthetic save and coworker names, the real views.
///
///     PTB_TRADEBOX_SCREENSHOT_DIR=/tmp/shots swift test --filter TradeBoxShotTests
@MainActor
final class TradeBoxShotTests: XCTestCase {
    func testCaptureBoxPickerConfirmRowAndCollapsedFriendsTab() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_TRADEBOX_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_TRADEBOX_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (store, cleanup) = try BoxDexFixture.makeStore(language: .ko)
        defer { cleanup() }
        let suite = "trade-box-shot-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let reply = Data(#"{"coworkers":[{"id":"u1","name":"Alex Kim"},{"id":"u2","name":"Sam Lee"},{"id":"u3","name":"Jordan Park"}]}"#.utf8)
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (reply, 200) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        let battle = BattleEntryStore(defaults: defaults)
        _ = battle.add(BoxDexFixture.pikachuID)

        let eevee = try XCTUnwrap(store.boxIndividuals.first { $0.id == BoxDexFixture.eeveeID })
        func detail(target: String?) -> some View {
            BoxDetailView(store: store, individual: eevee, navigation: PopoverNavigation(), onBack: {},
                          opensTradePanel: true, initialTradeTarget: target)
                .environment(uploader).environment(battle).environment(store)
        }
        try await capture(BoxDetailView(store: store, individual: eevee, navigation: PopoverNavigation(), onBack: {})
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("trade-box-detail-closed.png"))
        try await capture(detail(target: nil), to: directory.appendingPathComponent("trade-box-picker-open.png"))
        try await capture(detail(target: "u2"), to: directory.appendingPathComponent("trade-box-picker-confirm.png"))
        try await capture(TradeOfferView(store: store, uploader: uploader, fightingIDs: [BoxDexFixture.pikachuID], initialCoworkers: nil, onBack: {})
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("trade-box-friends-grid-first.png"))
        try await capture(TradeOfferView(store: store, uploader: uploader, fightingIDs: [BoxDexFixture.pikachuID],
                                         initialGive: BoxDexFixture.eeveeID, onBack: {})
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("trade-box-friends-collapsed.png"))
    }

    private func capture<V: View>(_ view: V, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 620)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, scale: 2, to: file)
    }
}
