import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Opt-in PR captures from the synthetic `BoxDexFixture` save plus two Charmander lines in the Box: a Charizard
/// holding an Exp. Share with full XP, and a Charmander still short of XP.
///
///     PTB_BOX_GRADUATION_SHOTS=/tmp/shots swift test --filter BoxGraduationScreenshotTests
@MainActor
final class BoxGraduationScreenshotTests: XCTestCase {
    static let zardID = "box-zard"
    static let manderID = "box-mander"
    static let names: [Int: [String: String]] = [4: ["ko": "파이리", "en": "Charmander"],
                                                  5: ["ko": "리자드", "en": "Charmeleon"],
                                                  6: ["ko": "리자몽", "en": "Charizard"]]

    static func addLine(_ state: inout CompanionState, id: String, stage: Int, used: Int, seed: UInt64, at: Double) {
        var profile = PokemonProfile.generate(seed: seed, instanceID: id)
        profile.level = 20 + stage * 15
        let path = [4, 5, 6]
        let mon = MonState(baseID: 4, pathIDs: Array(path.prefix(stage + 1)), plannedPathIDs: path, stageIndex: stage,
                           usedAtStage: used, rarity: .common, totalForms: 3, profile: profile)
        state.storedLines[id] = StoredLine(mon: mon, spentAtStore: 0)
        state.dex.append(DexEntry(id: id, baseID: 4, finalID: path[stage], chainOrder: Array(path.prefix(stage + 1)),
                                  rarity: .common, caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + at),
                                  profile: profile, names: names, releasedAt: Date(timeIntervalSince1970: 1_700_000_000 + at)))
    }

    func testCaptureBoxBeforeAndAfterAGraduationInTheBox() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BOX_GRADUATION_SHOTS"] else {
            throw XCTSkip("Set PTB_BOX_GRADUATION_SHOTS for the Box graduation captures")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "box-graduation-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = UsageStore(providers: [], discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil },
                               claudeUsageEntries: { _ in [] }, autoRefresh: false, defaults: defaults)
        let updater = UpdateChecker(currentVersion: "2.5.7-yp1", defaults: defaults, fetchLatest: { nil })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("box-graduation-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch, connected: false)
        let battle = BattleEntryStore(defaults: defaults)
        let species = [4, 5, 6, 25, 95, 133]
        for id in species {
            _ = await SpriteLoader.image(speciesID: id)
            _ = await SpriteLoader.image(speciesID: id, shiny: true)
        }
        for name in ItemKind.allCases.compactMap(\.spriteName) {
            _ = await SpriteLoader.itemImage(name: name)
        }

        for language in [AppLanguage.ko, .en] {
            let tag = language.rawValue
            let (store, cleanup) = try BoxDexFixture.makeStore(language: language, mutate: {
                Self.addLine(&$0, id: Self.zardID, stage: 2, used: 2_000_000_000, seed: 61, at: 500)
                Self.addLine(&$0, id: Self.manderID, stage: 0, used: 10, seed: 62, at: 600)
                $0.expShareHolders = [Self.zardID]
            }, defaults: defaults)
            defer { cleanup() }
            for id in species { await store.loadPokemonDetails(speciesID: id) }
            let popover = { (nav: PopoverNavigation) in
                PopoverView(screenHeight: 5000)
                    .environment(usage).environment(store).environment(updater).environment(nav)
                    .environment(uploader).environment(battle)
                    .environment(\.colorScheme, .light)
                    .environment(\.controlActiveState, .active)
            }
            let box = { let nav = PopoverNavigation(); nav.tab = .box; return nav }
            let detail = { let nav = PopoverNavigation(); nav.openBoxDetail(id: Self.zardID); return nav }

            try await shot(popover(box()), "before-box-\(tag)", dir: dir, height: 520)
            try await shot(popover(detail()), "before-box-detail-\(tag)", dir: dir, height: 520)

            await store.checkExpShareEvolution()
            XCTAssertNil(store.state.storedLines[Self.zardID])
            XCTAssertEqual(store.state.expShareHolders, [Self.manderID])
            try await shot(popover(box()), "after-box-\(tag)", dir: dir, height: 520)
            try await shot(popover(detail()), "after-box-detail-\(tag)", dir: dir, height: 520)

            let event = try XCTUnwrap(store.latestEvent?.text)
            let l = L(language)
            let text = FloatingPetView.hoverTooltip(todayTokens: 12_345_678, limitUtilization: nil, mode: .used, l: l,
                                                    eventLine: event)
            let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
            let callout = FloatingPetController.hoverCalloutView(text: text, appearance: appearance)
            callout.appearance = appearance
            try OffscreenRender.writePNG(of: callout, to: dir.appendingPathComponent("after-notice-\(tag).png"), scale: 2)
        }
    }

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
