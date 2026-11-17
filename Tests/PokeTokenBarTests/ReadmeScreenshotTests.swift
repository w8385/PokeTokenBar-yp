import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The README and landing images: the production popover drawn dark at 720px from the synthetic `BoxDexFixture`
/// save, in English, Korean and Japanese. Nothing reads the player's save; the bot is a stub.
///
///     PTB_README_SHOT_DIR=assets swift test --filter ReadmeScreenshotTests
@MainActor
final class ReadmeScreenshotTests: XCTestCase {
    private static let server = "http://bot-host:8790"
    private static let species = [4, 5, 6, 25, 95, 133]
    private let languages: [(AppLanguage, String)] = [(.en, ""), (.ko, "-ko"), (.ja, "-ja")]

    func testDrawReadmeImages() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_README_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_README_SHOT_DIR to draw the README images")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "readme-shots-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("readme-shots-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let originalArt = GymTrainerArt.directory
        GymTrainerArt.directory = GymRepo.trainerAssets
        GymTrainerArt.clearCache()
        let catalog = try GymCatalog.decode(Data(contentsOf: GymRepo.kantoCatalog))
        GymSession.shared.setCatalog(catalog, for: Self.server)
        defer {
            GymSession.shared.setCatalog(nil, for: Self.server)
            GymTrainerArt.directory = originalArt
            GymTrainerArt.clearCache()
        }
        try await preloadSprites()

        let usage = UsageStore(providers: [], discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil },
                               claudeUsageEntries: { _ in [] }, autoRefresh: false, defaults: defaults)
        let updater = UpdateChecker(currentVersion: "3.5.0", defaults: defaults, fetchLatest: { nil })
        let uploader = await BoxDexFixture.makeUploader(defaults: defaults, scratch: scratch)
        let entry = BattleEntryStore(defaults: defaults)
        for id in [BoxDexFixture.pikachuID, BoxDexFixture.charizardID, BoxDexFixture.onixID, BoxDexFixture.eeveeID] {
            _ = entry.add(id)
        }

        let home = try await sampleUsage(defaults: defaults)

        for (language, suffix) in languages {
            let (store, cleanup) = try BoxDexFixture.makeStore(language: language, mutate: Self.sample, defaults: defaults)
            defer { cleanup() }
            for id in Self.species { await store.loadPokemonDetails(speciesID: id) }
            store.update(todayTokensByProvider: ["claude_code": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                         limitWarning: false, hasUsageData: true)
            try await waitUntil("the raised Pokémon's line to load") { store.currentLine != nil }

            func popover(_ usage: UsageStore = usage, _ configure: (PopoverNavigation) -> Void) -> some View {
                let nav = PopoverNavigation()
                configure(nav)
                return PopoverView(screenHeight: 5000)
                    .environment(usage).environment(store).environment(updater).environment(nav)
                    .environment(uploader).environment(entry)
            }
            if language == .en {
                store.removeFriend(entryID: BoxDexFixture.pikachuID)
                try await shot(popover(home) { $0.tab = .home }, "screenshot-home", in: dir, height: nil)
                XCTAssertTrue(store.addFriend(entryID: BoxDexFixture.pikachuID))
                try await shot(await floatingFriends(usage: usage, store: store, sprites: scratch), "screenshot-floating-friends",
                               in: dir, height: nil)
            }
            try await shot(popover { $0.tab = .shop }, "screenshot-shop\(suffix)", in: dir, height: 548)
            try await shot(popover { $0.tab = .bag }, "screenshot-bag\(suffix)", in: dir, height: 420)
            try await shot(heldItems(store: store), "screenshot-held-items\(suffix)", in: dir, height: nil)
            try await shot(popover { $0.tab = .dex }, "screenshot-collection-pokedex\(suffix)", in: dir, height: 420)
            try await shot(popover { $0.tab = .box }, "screenshot-collection-box\(suffix)", in: dir, height: 420)
            try await shot(popover { $0.openBoxDetail(id: BoxDexFixture.charizardID) },
                           "screenshot-pokemon-profile\(suffix)", in: dir, height: 560)
            try await shot(popover { $0.openBoxDetail(id: BoxDexFixture.pikachuID) },
                           "screenshot-exp-share\(suffix)", in: dir, height: 372)
            try await shot(popover { $0.tab = .battle }, "screenshot-battle\(suffix)", in: dir, height: 482)
            try await shot(gyms(store: store, uploader: uploader, entry: entry, catalog: catalog),
                           "screenshot-gyms\(suffix)", in: dir, height: nil)
            try await shot(replay(language: language, catalog: catalog), "screenshot-gym-replay\(suffix)", in: dir,
                           height: nil)
            try await shot(finale(language: language, catalog: catalog), "screenshot-champion-finale\(suffix)", in: dir,
                           height: nil)
        }
    }

    private static func sample(_ state: inout CompanionState) {
        state.inventory[ItemKind.rareCandy.rawValue] = 3
        state.inventory[ItemKind.mint.rawValue] = 2
        state.inventory[ItemKind.expShare.rawValue] = 1
        state.expShareHolders = [BoxDexFixture.pikachuID]
        state.friendEntryIDs = [BoxDexFixture.charizardID, BoxDexFixture.pikachuID]
        state.gymBadges.update("kanto") { $0.gyms = [1, 2, 3] }
    }

    /// Two weeks of Claude Code and Codex use, ending with a busy today.
    private func sampleUsage(defaults: UserDefaults) async throws -> UsageStore {
        let formatter = LocalUsageReader.localDayFormatter()
        let now = Date()
        let calendar = Calendar.current
        func day(_ offset: Int, _ tokens: Int) -> DailyUsage {
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            return DailyUsage(date: formatter.string(from: date), inputTokens: tokens / 3, outputTokens: tokens / 6,
                              cacheCreationTokens: tokens / 4, cacheReadTokens: tokens - tokens / 3 - tokens / 6 - tokens / 4,
                              totalTokens: tokens, totalCost: Double(tokens) / 1_000_000 * 2.4)
        }
        func provider(_ id: String, _ name: String, pattern: [Int]) -> SampleUsageProvider {
            let days = pattern.enumerated().map { day(pattern.count - 1 - $0.offset, $0.element * 100_000) }
            let week = days.suffix(7).reduce(0) { $0 + $1.totalTokens }
            let month = days.reduce(0) { $0 + $1.totalTokens }
            return SampleUsageProvider(id: id, displayName: name, today: days.last!, enrichment: ProviderEnrichment(
                weekTotal: PeriodUsage(period: formatter.string(from: LocalUsageReader.startOfWeek(now)),
                                       totalTokens: week, totalCost: Double(week) / 1_000_000 * 2.4),
                monthTotal: PeriodUsage(period: LocalUsageReader.monthKey(now), totalTokens: month,
                                        totalCost: Double(month) / 1_000_000 * 2.4),
                monthDaily: days, recentDaily: days, periodsOK: true))
        }
        let usage = UsageStore(
            providers: [provider("claude_code", "Claude Code", pattern: [4, 0, 6, 9, 3, 5, 7, 0, 2, 6, 8, 5, 10, 7]),
                        provider("codex", "Codex", pattern: [2, 0, 1, 3, 2, 0, 4, 0, 1, 2, 3, 2, 3, 4])],
            discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil }, claudeUsageEntries: { _ in [] },
            autoRefresh: false, defaults: defaults)
        await usage.refresh(scheduleEmptyRetry: false)
        return usage
    }

    /// The floating pet with both friends beside it, the second one wearing the hearts a stroke pops.
    private func floatingFriends(usage: UsageStore, store: CompanionStore, sprites: URL) async -> some View {
        let spriteStore = SpriteStore(directory: sprites.appendingPathComponent("sprites"))
        let main = store.representativeSubject
        if let id = main.spriteSpeciesID {
            _ = await spriteStore.data(speciesID: id, animated: false, shiny: main.isShiny, form: main.form,
                                       female: main.megaSpriteID == nil && main.isFemale)
        }
        for friend in store.friendSubjects {
            _ = await spriteStore.data(speciesID: friend.megaSpriteID ?? friend.speciesID, animated: false,
                                       shiny: friend.isShiny, form: friend.megaSpriteID == nil ? friend.form : nil,
                                       female: friend.megaSpriteID == nil && friend.isFemale)
        }
        let layout = PetRowLayout(friendCount: 2, friendsOnLeft: false, friendsFlank: false)
        let crowd = PetCrowd(settle: .seconds(120))
        crowd.configure(order: layout.slotOrder, motionAllowed: false, active: false)
        crowd.friendsOnLeft = false
        let hearts = PetHeartState()
        hearts.friendIndex = 1
        let panel = FloatingPetController.panelSize(petSize: CGFloat(usage.floatingPetSize), showingBubble: true,
                                                    layout: layout)
        return FloatingPetView(animated: false, spriteStore: spriteStore, hearts: hearts, crowd: crowd)
            .environment(usage).environment(store)
            .frame(width: panel.width, height: panel.height)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
    }

    /// The gym list and the badge case, each on the card the Battle tab draws it on.
    private func gyms(store: CompanionStore, uploader: PartyUploader, entry: BattleEntryStore,
                      catalog: GymCatalog) -> some View {
        let l = store.l
        return VStack(alignment: .leading, spacing: 18) {
            card(l.gymSectionTitle) { GymSection(store: store, uploader: uploader, entry: entry) }
            card(l.gymBadgeCaseTitle) {
                GymBadgeCase(catalog: catalog, badges: store.state.gymBadges, language: store.language, l: l)
            }
        }
        .padding(PopoverMetrics.padding)
    }

    /// The Shop's and the Bag's held-item tabs, cut after their first battle-item groups.
    private func heldItems(store: CompanionStore) -> some View {
        let l = store.l
        return VStack(alignment: .leading, spacing: 18) {
            cropped(l.shop, height: 430) { ShopView(store: store, nav: PopoverNavigation(), initialCategory: .heldItem) }
            cropped(l.bag, height: 305) { BagView(store: store, nav: PopoverNavigation(), initialCategory: .heldItem) }
        }
        .padding(PopoverMetrics.padding)
        .environment(store)
    }

    private func cropped<Content: View>(_ title: String, height: CGFloat,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            content().frame(height: height, alignment: .top).clipped()
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .ptbCard()
        }
    }

    private func preloadSprites() async throws {
        for id in Self.species + ReplayCast.all.map(\.id) {
            _ = await SpriteLoader.image(speciesID: id)
            _ = await SpriteLoader.image(speciesID: id, back: true)
        }
        _ = await SpriteLoader.image(speciesID: 25, shiny: true)
        for name in ItemKind.allCases.compactMap(\.spriteName) {
            _ = await SpriteLoader.itemImage(name: name)
        }
    }

    /// A gym fight in progress: the leader's row and the replay stopped mid-fight.
    private func replay(language: AppLanguage, catalog: GymCatalog) throws -> some View {
        let l = L(language)
        let mine = [ReplayCast.pikachu, ReplayCast.lapras, ReplayCast.gengar]
        let theirs = [ReplayCast.wartortle, ReplayCast.seadra, ReplayCast.seaking]
        let outcome = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: "kanto-1", kind: "gym", won: true, turns: 5, events: ReplayCast.events(language),
            teams: (zip(mine, [0, 100, nil]).map { GymFixtures.fighter($0.id, name: $0.name(language), hp: $1) },
                    zip(theirs, [0, 0, nil]).map { GymFixtures.fighter($0.id, name: $0.name(language), hp: $1) })))
        let opponent = try XCTUnwrap(catalog.region("kanto")?.gyms.first)
        let player = GymReplayPlayer(try XCTUnwrap(GymReplay(outcome)), shown: 12)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(spacing: 0) {
                GymOpponentRow(opponent: opponent, language: language, l: l, earned: false, fighting: true,
                               disabled: true) {}
            }
            .ptbCard()
            GymReplayView(player: player, outcome: outcome, l: l, autoplay: false)
        }
        .padding(PopoverMetrics.padding)
        .environment(\.locale, language.displayLocale)
    }

    /// The Elite Four run with the champion's hidden "+1 ?", and the replay as the hidden partner comes out.
    private func finale(language: AppLanguage, catalog: GymCatalog) throws -> some View {
        let l = L(language)
        let elite = try XCTUnwrap(catalog.region("kanto")?.elite)
        let mine = [ReplayCast.pikachu, ReplayCast.lapras, ReplayCast.gengar]
        let outcome = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: "kanto-champion", kind: "champion", won: false, turns: 8, events: ReplayCast.finaleEvents(language),
            teams: (zip(mine, [0, 0, 40]).map { GymFixtures.fighter($0.id, name: $0.name(language), hp: $1) },
                    zip(ReplayCast.champion, [0, 0, 0, 0, 0, 0, 100]).map {
                        GymFixtures.fighter($0.id, name: $0.name(language), hp: $1)
                    })))
        let player = GymReplayPlayer(try XCTUnwrap(GymReplay(outcome)))
        player.skip()
        return VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(spacing: 0) {
                GymRunRow(title: l.gymEliteTitle, subtitle: nil, emblem: .hallOfFame, battles: elite.battles, l: l,
                          lockedReason: nil, nextStep: elite.battles.count, cleared: false, fighting: true,
                          disabled: true) {}
            }
            .ptbCard()
            GymReplayView(player: player, outcome: outcome, l: l, autoplay: false)
        }
        .padding(PopoverMetrics.padding)
        .environment(\.locale, language.displayLocale)
    }

    /// `height: nil` draws the view at its own height.
    private func shot<V: View>(_ view: V, _ name: String, in dir: URL, height: CGFloat?) async throws {
        let width = PopoverMetrics.width
        let styled = view
            .frame(width: width, height: height, alignment: .top)
            .fixedSize(horizontal: false, vertical: height == nil)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .active)
        let host = OffscreenRender.host(styled, size: CGSize(width: width, height: height ?? 2_000), appearance: .darkAqua)
        try await OffscreenRender.settle(host)
        if height == nil {
            host.frame.size.height = host.fittingSize.height
            try await OffscreenRender.settle(host)
        }
        try OffscreenRender.writePNG(of: host, to: dir.appendingPathComponent("\(name).png"), scale: 2)
    }
}

private struct SampleUsageProvider: UsageProvider {
    let id: String
    let displayName: String
    var reportsCost = true
    let today: DailyUsage
    let enrichment: ProviderEnrichment
    func fetchDaily() async throws -> DailyUsage? { today }
    func fetchEnrichment() async -> ProviderEnrichment { enrichment }
}

/// The replay's fighters and moves, named per language the way the bot sends them.
private struct ReplayCast {
    let id: Int
    let names: [AppLanguage: String]

    func name(_ language: AppLanguage) -> String { names[language] ?? names[.en] ?? "" }

    static let pikachu = ReplayCast(id: 25, names: [.en: "Pikachu", .ko: "피카츄", .ja: "ピカチュウ"])
    static let lapras = ReplayCast(id: 131, names: [.en: "Lapras", .ko: "라프라스", .ja: "ラプラス"])
    static let gengar = ReplayCast(id: 94, names: [.en: "Gengar", .ko: "팬텀", .ja: "ゲンガー"])
    static let wartortle = ReplayCast(id: 8, names: [.en: "Wartortle", .ko: "어니부기", .ja: "カメール"])
    static let seadra = ReplayCast(id: 117, names: [.en: "Seadra", .ko: "시드라", .ja: "シードラ"])
    static let seaking = ReplayCast(id: 119, names: [.en: "Seaking", .ko: "왕콘치", .ja: "アズマオウ"])
    /// The bot's Kanto champion table: six on show, then the hidden finale.
    static let champion = [
        ReplayCast(id: 145, names: [.en: "Zapdos", .ko: "썬더", .ja: "サンダー"]),
        ReplayCast(id: 146, names: [.en: "Moltres", .ko: "파이어", .ja: "ファイヤー"]),
        ReplayCast(id: 149, names: [.en: "Dragonite", .ko: "망나뇽", .ja: "カイリュー"]),
        ReplayCast(id: 6, names: [.en: "Charizard", .ko: "리자몽", .ja: "リザードン"]),
        ReplayCast(id: 94, names: [.en: "Gengar", .ko: "팬텀", .ja: "ゲンガー"]),
        ReplayCast(id: 130, names: [.en: "Gyarados", .ko: "갸라도스", .ja: "ギャラドス"]),
        ReplayCast(id: 150, names: [.en: "Mewtwo", .ko: "뮤츠", .ja: "ミュウツー"]),
    ]
    static let all = [pikachu, lapras, gengar, wartortle, seadra, seaking] + champion

    private static let moves: [String: [AppLanguage: String]] = [
        "thunderbolt": [.en: "Thunderbolt", .ko: "10만볼트", .ja: "10まんボルト"],
        "bubble-beam": [.en: "Bubble Beam", .ko: "거품광선", .ja: "バブルこうせん"],
        "hydro-pump": [.en: "Hydro Pump", .ko: "하이드로펌프", .ja: "ハイドロポンプ"],
        "body-slam": [.en: "Body Slam", .ko: "누르기", .ja: "のしかかり"],
        "ice-beam": [.en: "Ice Beam", .ko: "냉동빔", .ja: "れいとうビーム"],
        "flamethrower": [.en: "Flamethrower", .ko: "화염방사", .ja: "かえんほうしゃ"],
        "surf": [.en: "Surf", .ko: "파도타기", .ja: "なみのり"],
        "shadow-ball": [.en: "Shadow Ball", .ko: "섀도볼", .ja: "シャドーボール"],
        "waterfall": [.en: "Waterfall", .ko: "폭포오르기", .ja: "たきのぼり"],
    ]

    private static func move(_ turn: Int, side: Int, member: Int, _ id: String, _ language: AppLanguage) -> [String: Any] {
        GymFixtures.event(turn, "move", side: side, member: member, move: moves[id]?[language] ?? id)
    }

    /// Each of the champion's six falls in turn; the hidden seventh comes out after the last.
    static func finaleEvents(_ language: AppLanguage) -> [[String: Any]] {
        func hit(_ turn: Int, by side: Int, _ attacker: Int, on defender: Int, _ id: String, hp: Int) -> [[String: Any]] {
            [move(turn, side: side, member: attacker, id, language),
             GymFixtures.event(turn, "damage", side: 1 - side, member: defender, hp: hp)]
        }
        func ko(_ turn: Int, side: Int, _ member: Int, next: Int) -> [[String: Any]] {
            [GymFixtures.event(turn, "faint", side: side, member: member),
             GymFixtures.event(turn, "switch", side: side, member: next, hp: 100)]
        }
        let opening = [GymFixtures.event(0, "switch", side: 0, member: 0, hp: 100),
                       GymFixtures.event(0, "switch", side: 1, member: 0, hp: 100)]
        let fight = [
            hit(1, by: 0, 0, on: 0, "thunderbolt", hp: 0), ko(1, side: 1, 0, next: 1),
            hit(2, by: 1, 1, on: 0, "flamethrower", hp: 0), ko(2, side: 0, 0, next: 1),
            hit(3, by: 0, 1, on: 1, "surf", hp: 0), ko(3, side: 1, 1, next: 2),
            hit(4, by: 0, 1, on: 2, "ice-beam", hp: 0), ko(4, side: 1, 2, next: 3),
            hit(5, by: 0, 1, on: 3, "surf", hp: 0), ko(5, side: 1, 3, next: 4),
            hit(6, by: 1, 4, on: 1, "shadow-ball", hp: 0), ko(6, side: 0, 1, next: 2),
            hit(7, by: 0, 2, on: 4, "shadow-ball", hp: 0), ko(7, side: 1, 4, next: 5),
            hit(8, by: 1, 5, on: 2, "waterfall", hp: 40), hit(8, by: 0, 2, on: 5, "thunderbolt", hp: 0),
            [GymFixtures.event(8, "faint", side: 1, member: 5),
             GymFixtures.event(8, GymBattleEvent.finale, side: 1, member: 6),
             GymFixtures.event(8, "switch", side: 1, member: 6, hp: 100)],
        ]
        return opening + fight.flatMap { $0 }
    }

    /// Pikachu beats Wartortle and falls to Seadra; Lapras comes in and finishes Seadra.
    static func events(_ language: AppLanguage) -> [[String: Any]] {
        func move(_ turn: Int, side: Int, member: Int, _ id: String) -> [String: Any] {
            Self.move(turn, side: side, member: member, id, language)
        }
        func damage(_ turn: Int, side: Int, member: Int, hp: Int) -> [String: Any] {
            GymFixtures.event(turn, "damage", side: side, member: member, hp: hp)
        }
        return [
            GymFixtures.event(0, "switch", side: 0, member: 0, hp: 100),
            GymFixtures.event(0, "switch", side: 1, member: 0, hp: 100),
            move(1, side: 0, member: 0, "thunderbolt"), damage(1, side: 1, member: 0, hp: 40),
            move(1, side: 1, member: 0, "bubble-beam"), damage(1, side: 0, member: 0, hp: 62),
            move(2, side: 0, member: 0, "thunderbolt"), damage(2, side: 1, member: 0, hp: 0),
            GymFixtures.event(2, "faint", side: 1, member: 0),
            GymFixtures.event(2, "switch", side: 1, member: 1, hp: 100),
            move(3, side: 1, member: 1, "hydro-pump"), damage(3, side: 0, member: 0, hp: 15),
            move(3, side: 0, member: 0, "thunderbolt"), damage(3, side: 1, member: 1, hp: 30),
            move(4, side: 1, member: 1, "hydro-pump"), damage(4, side: 0, member: 0, hp: 0),
            GymFixtures.event(4, "faint", side: 0, member: 0),
            GymFixtures.event(4, "switch", side: 0, member: 1, hp: 100),
            move(5, side: 0, member: 1, "body-slam"), damage(5, side: 1, member: 1, hp: 0),
            GymFixtures.event(5, "faint", side: 1, member: 1),
        ]
    }
}
