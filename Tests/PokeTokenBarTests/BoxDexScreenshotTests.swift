import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private let shotMovesJSON = """
{"moves":[
 {"id":85,"name":"10만볼트","type":"electric","power":90,"damage_class":"special","accuracy":100,"level":26,"pp":15},
 {"id":98,"name":"전광석화","type":"normal","power":40,"damage_class":"physical","accuracy":100,"level":10,"pp":30}
],"default":[85,98]}
"""

/// Opt-in captures of the Pokédex / Box split from the synthetic `BoxDexFixture` save.
/// `PTB_BOXDEX_SHOTS=<dir>` turns them on; nothing reads the player's save.
@MainActor
final class BoxDexScreenshotTests: XCTestCase {
    func testCaptureBoxDexScreens() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BOXDEX_SHOTS"] else {
            throw XCTSkip("Set PTB_BOXDEX_SHOTS for the Pokédex/Box captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "box-dex-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (store, cleanup) = try BoxDexFixture.makeStore(defaults: defaults)
        defer { cleanup() }
        for id in [25, 6, 95] { await store.loadPokemonDetails(speciesID: id) }
        store.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
        for _ in 0..<100 where store.currentLine == nil { await Task.yield() }
        let usage = UsageStore(providers: [], discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil },
                               claudeUsageEntries: { _ in [] }, autoRefresh: false, defaults: defaults)
        let updater = UpdateChecker(currentVersion: "2.5.7-yp1", defaults: defaults, fetchLatest: { nil })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("box-dex-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let battle = BattleEntryStore(defaults: defaults)
        _ = battle.add(BoxDexFixture.pikachuID)
        _ = battle.add(BoxDexFixture.charizardID)
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", exchange: { _ in (Data(BoxDexFixture.botReply.utf8), 200) },
            fetch: { _ in (Data(shotMovesJSON.utf8), 200) },
            partySource: { [PartyMember(pokemonID: 25, level: 42, shiny: false, ivs: nil)] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        await uploader.tick()
        let offlineUploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: false)

        func popover(_ nav: PopoverNavigation) -> some View {
            PopoverView(screenHeight: 5000)
                .environment(usage).environment(store).environment(updater).environment(nav)
                .environment(uploader).environment(battle)
                .environment(\.colorScheme, .light)
                .environment(\.controlActiveState, .active)
        }

        let dex = PopoverNavigation(); dex.tab = .dex
        try await shot(popover(dex), "box-dex-dex-grid", dir: dir, height: 700)

        let dexDetail = PopoverNavigation(); dexDetail.openDexEntry(collectionID: "25")
        try await shot(popover(dexDetail), "box-dex-dex-detail", dir: dir, height: 700)

        let box = PopoverNavigation(); box.tab = .box
        try await shot(popover(box), "box-dex-box-grid", dir: dir, height: 700)

        let boxDetail = PopoverNavigation(); boxDetail.openBoxDetail(id: BoxDexFixture.pikachuID)
        try await shot(popover(boxDetail), "box-dex-box-detail", dir: dir, height: 700)

        let mega = PopoverNavigation(); mega.openBoxDetail(id: BoxDexFixture.charizardID)
        try await shot(popover(mega), "box-dex-box-detail-mega", dir: dir, height: 700)

        let onix = PopoverNavigation(); onix.openBoxDetail(id: BoxDexFixture.onixID)
        try await shot(popover(onix), "box-dex-box-detail-onix", dir: dir, height: 700)

        let battleNav = PopoverNavigation(); battleNav.tab = .battle
        try await shot(popover(battleNav), "box-dex-battle", dir: dir, height: 700)

        let soloSuite = "box-dex-solo-\(UUID())"
        let soloDefaults = try XCTUnwrap(UserDefaults(suiteName: soloSuite))
        defer { soloDefaults.removePersistentDomain(forName: soloSuite) }
        let solo = BattleEntryStore(defaults: soloDefaults)
        _ = solo.add(BoxDexFixture.charizardID)
        let soloNav = PopoverNavigation(); soloNav.tab = .battle
        try await shot(PopoverView(screenHeight: 5000)
            .environment(usage).environment(store).environment(updater).environment(soloNav)
            .environment(uploader).environment(solo)
            .environment(\.colorScheme, .light).environment(\.controlActiveState, .active),
                       "box-dex-battle-held-item", dir: dir, height: 900)

        for language in [AppLanguage.en, .ko, .ja] {
            let (localized, cleanupLocalized) = try BoxDexFixture.makeStore(language: language, defaults: defaults)
            defer { cleanupLocalized() }
            localized.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                             limitWarning: false, hasUsageData: true)
            for _ in 0..<100 where localized.currentLine == nil { await Task.yield() }
            let nav = PopoverNavigation(); nav.tab = .box
            try await shot(PopoverView(screenHeight: 5000)
                .environment(usage).environment(localized).environment(updater).environment(nav)
                .environment(uploader).environment(battle)
                .environment(\.colorScheme, .light).environment(\.controlActiveState, .active),
                           "box-dex-box-grid-\(language.rawValue)", dir: dir, height: 420)
            let dexNav = PopoverNavigation(); dexNav.tab = .dex
            try await shot(PopoverView(screenHeight: 5000)
                .environment(usage).environment(localized).environment(updater).environment(dexNav)
                .environment(uploader).environment(battle)
                .environment(\.colorScheme, .light).environment(\.controlActiveState, .active),
                           "box-dex-dex-grid-\(language.rawValue)", dir: dir, height: 420)
        }

        let coworkers = PopoverNavigation(); coworkers.tab = .coworkers
        try await shot(popover(coworkers), "box-dex-coworkers", dir: dir, height: 700)

        let offer = PopoverNavigation(); offer.openTradeOffer(giving: BoxDexFixture.eeveeID)
        try await shot(popover(offer), "box-dex-coworkers-offer", dir: dir, height: 700)

        let offline = PopoverNavigation(); offline.tab = .coworkers
        try await shot(PopoverView(screenHeight: 5000)
            .environment(usage).environment(store).environment(updater).environment(offline)
            .environment(offlineUploader).environment(battle)
            .environment(\.colorScheme, .light).environment(\.controlActiveState, .active),
                       "box-dex-coworkers-offline", dir: dir, height: 700)

        let home = PopoverNavigation()
        try await shot(popover(home), "box-dex-home", dir: dir, height: 700)

        let bars = VStack(spacing: 8) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                PopoverTabPicker(selection: .constant(.box), l: L(language))
            }
        }
        .padding(PopoverMetrics.padding)
        try await shot(bars, "box-dex-tab-bar", dir: dir, height: 380)

        let bagBars = VStack(spacing: 8) {
            ForEach(PopoverTab.allCases, id: \.self) { tab in
                PopoverTabPicker(selection: .constant(tab), l: L(.ko))
            }
        }
        .padding(PopoverMetrics.padding)
        try await shot(bagBars, "box-dex-tab-bar-ko", dir: dir, height: 320)
    }

    private func shot<V: View>(_ view: V, _ name: String, dir: URL, height: CGFloat) async throws {
        let width = PopoverMetrics.width
        try await OffscreenRender.capture(
            view.frame(width: width, height: height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: width, height: height), appearance: .aqua, scale: 2,
            to: dir.appendingPathComponent("\(name).png"))
    }
}
