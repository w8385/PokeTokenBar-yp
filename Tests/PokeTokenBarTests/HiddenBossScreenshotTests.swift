import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct PrizeShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures for the PR: synthetic data, real views.
///
///     PTB_HIDDEN_BOSS_SHOT_DIR=/tmp/shots swift test --filter HiddenBossScreenshotTests
@MainActor
final class HiddenBossScreenshotTests: XCTestCase {
    private let mine = [(25, "피카츄"), (131, "라프라스"), (94, "팬텀")]
    private var original: URL?

    override func setUp() {
        original = GymTrainerArt.directory
        GymTrainerArt.directory = GymRepo.trainerAssets
        GymTrainerArt.clearCache()
    }

    override func tearDown() {
        GymTrainerArt.directory = original
        GymTrainerArt.clearCache()
    }

    func testCaptureTheRegionListTheResultAndTheBag() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_HIDDEN_BOSS_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_HIDDEN_BOSS_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await captureTheRegionList(to: directory)
        try await captureTheHiddenResult(to: directory)
        try await captureTheBag(to: directory)
    }

    /// "before" is the catalog of a bot without the hidden boss.
    private func captureTheRegionList(to directory: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("hidden-boss-list-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let shots: [(name: String, hidden: Bool, hallOfFame: Bool, beaten: Bool, badgeCase: Bool)] = [
            ("list-before", false, false, false, false), ("list-locked", true, false, false, false),
            ("list-unlocked", true, true, false, false),
            ("case-before", true, true, false, true), ("case-after", true, true, true, true),
        ]
        for language in [AppLanguage.ko, .en] {
            for shot in shots {
                var badges = GymBadges()
                badges.update("kanto") { $0.gyms = Set(1...8); $0.hallOfFame = shot.hallOfFame; $0.hiddenBeaten = shot.beaten }
                var state = CompanionState()
                state.language = language
                state.installBaselineSet = true
                state.gymBadges = badges
                let file = scratch.appendingPathComponent("\(shot.name)-\(language.rawValue).json")
                try JSONEncoder().encode(state).write(to: file)
                let store = CompanionStore(provider: PrizeShotProvider(), fileURL: file)
                let defaults = try XCTUnwrap(UserDefaults(suiteName: "hidden-boss-shot-\(UUID())"))
                let uploader = PartyUploader(
                    tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
                    appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
                uploader.saveToken("synthetic-token")
                uploader.serverURL = "http://bot-host:8790"
                let session = GymSession()
                session.showsBadgeCase = shot.badgeCase
                session.setCatalog(try GymCatalog.decode(GymFixtures.catalogData(hidden: shot.hidden)), for: "http://bot-host:8790")
                let service = GymService(link: { uploader.gymLink }, exchange: { _ in (Data(), 503) },
                                         badges: { store.state.gymBadges }, ownedTMs: { [] },
                                         applyReward: { _, _, _ in }, session: session)
                let section = GymSection(store: store, uploader: uploader, entry: BattleEntryStore(defaults: defaults),
                                         service: service).ptbCard()
                    .padding(.horizontal, 12).padding(.top, 8)
                try await capture(section, language: language, height: shot.badgeCase ? 420 : 1080,
                                  to: directory.appendingPathComponent("hidden-\(shot.name)-\(language.rawValue).png"))
            }
        }
    }

    private func captureTheHiddenResult(to directory: URL) async throws {
        let kanto = try XCTUnwrap(GymFixtures.catalog(hidden: true).region("kanto"))
        let boss = try XCTUnwrap(kanto.hidden)
        let seven = zip(boss.team + [150], ["썬더", "파이어", "망나뇽", "리자몽", "팬텀", "갸라도스", "뮤츠"]).map { ($0, $1) }
        for species in mine.map(\.0) + boss.team { _ = await SpriteLoader.image(speciesID: species) }
        let won = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: boss.id, kind: "hidden", won: true, turns: 18,
            teams: (fighters(mine, hp: [0, 30, 100]), fighters(seven, hp: [0, 0, 0, 0, 0, 0, nil]))))
        let tm = try XCTUnwrap(MachineCatalog.moves.first { $0.power >= GymRewards.finaleMinPower })
        for language in [AppLanguage.ko, .en] {
            let l = L(language)
            let reward = GymReward(region: "kanto", battleID: boss.id, kind: .hiddenBoss, tmMoveID: tm.id, badges: GymBadges())
            try write(GymResultView(record: GymFightRecord(opponent: boss, outcome: won, reward: reward),
                                    language: language, l: l, regionName: l.gymRegionName(kanto),
                                    tmName: { _ in tm.name(language) }, primaryTitle: l.gymRematch, busy: false,
                                    onPrimary: {}, onClose: {}),
                      language: language, height: 460,
                      to: directory.appendingPathComponent("hidden-result-\(language.rawValue).png"))
        }
    }

    private func captureTheBag(to directory: URL) async throws {
        _ = await SpriteLoader.image(speciesID: 150, shiny: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("hidden-boss-bag-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for language in [AppLanguage.ko, .en] {
            let file = scratch.appendingPathComponent("state-\(language.rawValue).json")
            let json = "{\"economyVersion\":2,\"installBaselineSet\":true,\"usedSinceInstall\":1,\"spentTokens\":0,"
                + "\"lastDate\":\"d\",\"language\":\"\(language.rawValue)\",\"dex\":[],\"collectedFinals\":[],"
                + "\"active\":{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":0,\"rarity\":\"common\","
                + "\"totalForms\":3,\"isShiny\":false},"
                + "\"inventory\":{\"shiny-egg:150\":1,\"rareCandy\":16,\"redOrb\":1,\"adamantCrystal\":1,"
                + "\"punchingGlove\":1,\"occaBerry\":1,\"chilanBerry\":1,\"flamePlate\":1,\"pixiePlate\":1}}"
            try Data(json.utf8).write(to: file)
            let store = CompanionStore(provider: PrizeShotProvider(), fileURL: file)
            let nav = PopoverNavigation()
            try await capture(BagView(store: store, nav: nav, initialCategory: .egg).environment(store), language: language,
                              height: 540, to: directory.appendingPathComponent("hidden-bag-egg-\(language.rawValue).png"))
            try await capture(BagView(store: store, nav: nav, initialCategory: .heldItem).environment(store), language: language,
                              height: 540, to: directory.appendingPathComponent("hidden-bag-items-\(language.rawValue).png"))        }
        try await captureTheSignatureItems(to: directory, scratch: scratch)
        try await captureTheShopSignatureCards(to: directory, scratch: scratch)
    }

    /// The Shop's signature section past the masks, cut out so the long held-item tab need not scroll.
    private func captureTheShopSignatureCards(to directory: URL, scratch: URL) async throws {
        let added = Set(ItemKind.megaSlotItems + ItemKind.crownedItems).subtracting(ItemKind.primalOrbs)
        let shown = ItemKind.megaSlotItems + ItemKind.originItems + ItemKind.crownedItems
        for language in [AppLanguage.ko, .en] {
            var state = CompanionState()
            state.language = language
            state.installBaselineSet = true
            state.usedSinceInstall = 9_000_000_000
            let file = scratch.appendingPathComponent("shop-\(language.rawValue).json")
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: PrizeShotProvider(), fileURL: file)
            for (name, kinds) in [("before", shown.filter { !added.contains($0) }), ("after", shown)] {
                let cards = VStack(alignment: .leading, spacing: 10) {
                    HeldItemSections(sections: [BattleItemSection(group: .signature, kinds: kinds)], l: store.l) { kind in
                        ShopItemCard(store: store, kind: kind)
                    }
                }
                .padding(.horizontal, 12)
                try await capture(cards.environment(store), language: language, height: CGFloat(kinds.count) * 180 + 40,
                                  to: directory.appendingPathComponent("npc-items-shop-\(name)-\(language.rawValue).png"))
            }
        }
    }

    /// "before" holds signature items the Shop already sold; "after" holds the three NPC items it now sells.
    private func captureTheSignatureItems(to directory: URL, scratch: URL) async throws {
        let shots = [("before", "\"redOrb\":1,\"adamantCrystal\":1"),
                     ("after", "\"ultranecroziumZ\":1,\"rustedSword\":1,\"rustedShield\":1")]
        for language in [AppLanguage.ko, .en] {
            for (name, inventory) in shots {
                let file = scratch.appendingPathComponent("signature-\(name)-\(language.rawValue).json")
                let json = "{\"economyVersion\":2,\"installBaselineSet\":true,\"usedSinceInstall\":1,\"spentTokens\":0,"
                    + "\"lastDate\":\"d\",\"language\":\"\(language.rawValue)\",\"dex\":[],\"collectedFinals\":[],"
                    + "\"active\":{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":0,\"rarity\":\"common\","
                    + "\"totalForms\":3,\"isShiny\":false},\"inventory\":{\(inventory)}}"
                try Data(json.utf8).write(to: file)
                let store = CompanionStore(provider: PrizeShotProvider(), fileURL: file)
                try await capture(BagView(store: store, nav: PopoverNavigation(), initialCategory: .heldItem).environment(store),
                                  language: language, height: 540,
                                  to: directory.appendingPathComponent("npc-items-bag-\(name)-\(language.rawValue).png"))
            }
        }
    }

    private func fighters(_ team: [(Int, String)], hp: [Int?]) -> [[String: Any]] {
        zip(team, hp).map { GymFixtures.fighter($0.0, name: $0.1, hp: $1) }
    }

    private func write<V: View>(_ view: V, language: AppLanguage, height: CGFloat, to file: URL) throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        let host = OffscreenRender.host(
            view.frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.white).environment(\.colorScheme, .light)
                .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua)
        try OffscreenRender.writePNG(of: host, to: file, scale: 2)
    }

    private func capture<V: View>(_ view: V, language: AppLanguage, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua, to: file)
    }
}
