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
        let catalog = try GymCatalog.decode(Data(kantoCatalog.utf8))
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
                try await shot(popover(home) { $0.tab = .home }, "screenshot-home", in: dir, height: nil)
                try await shot(await floatingFriends(usage: usage, store: store, sprites: scratch), "screenshot-floating-friends",
                               in: dir, height: nil)
            }
            try await shot(popover { $0.tab = .shop }, "screenshot-shop\(suffix)", in: dir, height: 548)
            try await shot(popover { $0.tab = .bag }, "screenshot-bag\(suffix)", in: dir, height: 420)
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
        let theirs = [ReplayCast.poliwhirl, ReplayCast.wartortle]
        let outcome = try GymBattleOutcome.decode(GymFixtures.outcomeData(
            gymID: "kanto-1", kind: "gym", won: true, turns: 5, events: ReplayCast.events(language),
            teams: (zip(mine, [0, 100, nil]).map { GymFixtures.fighter($0.id, name: $0.name(language), hp: $1) },
                    theirs.map { GymFixtures.fighter($0.id, name: $0.name(language), hp: 0) })))
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
    static let poliwhirl = ReplayCast(id: 61, names: [.en: "Poliwhirl", .ko: "슈륙챙이", .ja: "ニョロゾ"])
    static let wartortle = ReplayCast(id: 8, names: [.en: "Wartortle", .ko: "어니부기", .ja: "カメール"])
    static let all = [pikachu, lapras, gengar, poliwhirl, wartortle]

    private static let moves: [String: [AppLanguage: String]] = [
        "thunderbolt": [.en: "Thunderbolt", .ko: "10만볼트", .ja: "10まんボルト"],
        "bubble-beam": [.en: "Bubble Beam", .ko: "거품광선", .ja: "バブルこうせん"],
        "aqua-tail": [.en: "Aqua Tail", .ko: "아쿠아테일", .ja: "アクアテール"],
        "body-slam": [.en: "Body Slam", .ko: "누르기", .ja: "のしかかり"],
    ]

    /// Pikachu beats Poliwhirl and falls to Wartortle; Lapras comes in and finishes Wartortle.
    static func events(_ language: AppLanguage) -> [[String: Any]] {
        func move(_ turn: Int, side: Int, member: Int, _ id: String) -> [String: Any] {
            GymFixtures.event(turn, "move", side: side, member: member, move: moves[id]?[language] ?? id)
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
            move(3, side: 1, member: 1, "aqua-tail"), damage(3, side: 0, member: 0, hp: 15),
            move(3, side: 0, member: 0, "thunderbolt"), damage(3, side: 1, member: 1, hp: 30),
            move(4, side: 1, member: 1, "aqua-tail"), damage(4, side: 0, member: 0, hp: 0),
            GymFixtures.event(4, "faint", side: 0, member: 0),
            GymFixtures.event(4, "switch", side: 0, member: 1, hp: 100),
            move(5, side: 0, member: 1, "body-slam"), damage(5, side: 1, member: 1, hp: 0),
            GymFixtures.event(5, "faint", side: 1, member: 1),
        ]
    }
}

/// The Kanto region of the bot's `GET /gyms` catalog (`bot/ypoke/gym_data.py`), trimmed to one region.
private let kantoCatalog = #"""
{"ok":true,"regions":[{"id":"kanto","name":"관동","first":1,"last":151,"gyms":[{"id":"kanto-1","kind":"gym","index":1,"types":["water"],"level":50,"trainer":{"name":{"ko":"물결","en":"Rippa","ja":"リッパ"},"line":{"ko":"파도는 멈추지 않아. 너도 그래야 해.","en":"Waves never stop. Neither should you.","ja":"波は止まらない。君もだ。"}},"team":[61,8,148,51,117,119],"run":null},{"id":"kanto-2","kind":"gym","index":2,"types":["poison"],"level":50,"trainer":{"name":{"ko":"독초","en":"Venn","ja":"ヴェン"},"line":{"ko":"한 방울이면 충분하지.","en":"One drop is plenty.","ja":"一滴で十分さ。"}},"team":[44,2,93,24,49,42],"run":null},{"id":"kanto-3","kind":"gym","index":3,"types":["normal"],"level":50,"trainer":{"name":{"ko":"한결","en":"Hal","ja":"ハル"},"line":{"ko":"평범함이 가장 단단해.","en":"Ordinary is the hardest thing to break.","ja":"ふつうが一番かたいんだ。"}},"team":[40,53,22,113,85,18],"run":null},{"id":"kanto-4","kind":"gym","index":4,"types":["flying"],"level":50,"trainer":{"name":{"ko":"새벽","en":"Aeron","ja":"エアロン"},"line":{"ko":"높이 나는 쪽이 먼저 본다.","en":"The higher flier sees first.","ja":"高く飛ぶ者が先に見る。"}},"team":[22,42,82,85,18,123],"run":null},{"id":"kanto-5","kind":"gym","index":5,"types":["ground"],"level":50,"trainer":{"name":{"ko":"자갈","en":"Dunn","ja":"ダン"},"line":{"ko":"발밑부터 단단히 다져.","en":"Pack the ground under you first.","ja":"足元から固めなさい。"}},"team":[28,112,101,76,31,34],"run":null},{"id":"kanto-6","kind":"gym","index":6,"types":["grass"],"level":50,"trainer":{"name":{"ko":"새싹","en":"Fennel","ja":"フェンネル"},"line":{"ko":"천천히 자라서 크게 이겨.","en":"Grow slow, win big.","ja":"ゆっくり育って、大きく勝つ。"}},"team":[45,71,78,68,3,103],"run":null},{"id":"kanto-7","kind":"gym","index":7,"types":["fire"],"level":50,"trainer":{"name":{"ko":"불씨","en":"Kade","ja":"ケイド"},"line":{"ko":"작은 불씨도 숲을 태워.","en":"A spark can burn a forest.","ja":"火花ひとつで森も燃える。"}},"team":[126,78,38,136,6,59],"run":null},{"id":"kanto-8","kind":"gym","index":8,"types":["psychic"],"level":50,"trainer":{"name":{"ko":"가온","en":"Oriel","ja":"オリエル"},"line":{"ko":"네 다음 수는 이미 읽었어.","en":"I read your next move already.","ja":"君の次の手は読んでいる。"}},"team":[65,121,103,6,143,59],"run":null}],"elite":{"run":"kanto-elite","badges_needed":8,"battles":[{"id":"kanto-elite-1","kind":"elite","index":1,"types":["bug"],"level":50,"trainer":{"name":{"ko":"메뚜기","en":"Pell","ja":"ペル"},"line":{"ko":"작다고 얕보면 물려.","en":"Small things bite hard.","ja":"小さいからって侮ると噛まれるよ。"}},"team":[15,49,127,131,143,59],"run":{"id":"kanto-elite","step":1,"steps":5}},{"id":"kanto-elite-2","kind":"elite","index":2,"types":["fighting"],"level":50,"trainer":{"name":{"ko":"주먹","en":"Tor","ja":"トール"},"line":{"ko":"말은 필요 없다. 덤벼라.","en":"No talk. Come at me.","ja":"言葉はいらん。かかってこい。"}},"team":[106,68,62,6,143,59],"run":{"id":"kanto-elite","step":2,"steps":5}},{"id":"kanto-elite-3","kind":"elite","index":3,"types":["rock"],"level":50,"trainer":{"name":{"ko":"바위","en":"Holt","ja":"ホルト"},"line":{"ko":"산은 한 번도 물러난 적 없다.","en":"A mountain has never stepped back.","ja":"山は一歩も退いたことがない。"}},"team":[76,141,142,131,143,59],"run":{"id":"kanto-elite","step":3,"steps":5}},{"id":"kanto-elite-4","kind":"elite","index":4,"types":["ice"],"level":50,"trainer":{"name":{"ko":"서리","en":"Rime","ja":"ライム"},"line":{"ko":"식을 때까지 기다려 줄게.","en":"I'll wait until you cool off.","ja":"頭が冷えるまで待ってあげる。"}},"team":[87,91,103,131,143,59],"run":{"id":"kanto-elite","step":4,"steps":5}},{"id":"kanto-champion","kind":"champion","index":5,"types":[],"level":50,"trainer":{"name":{"ko":"여울","en":"Idris","ja":"イドリス"},"line":{"ko":"여기까지 온 건 인정하지. 이제 진짜를 보여 줘.","en":"You made it here. Now show me the real thing.","ja":"ここまで来たことは認めよう。本物を見せてくれ。"}},"team":[142,135,103,130,143,59],"run":{"id":"kanto-elite","step":5,"steps":5}}]},"hideout":{"run":"kanto-hideout","org":{"name":{"ko":"어둠전선","en":"The Dim Circuit","ja":"ディム・サーキット"},"types":["electric","ghost"]},"battles":[{"id":"kanto-hideout-1","kind":"grunt","index":1,"types":["electric","ghost"],"level":50,"trainer":{"name":{"ko":"어둠전선 단원","en":"Dim Circuit Grunt","ja":"ディム・サーキットの下っ端"},"line":{"ko":"불 꺼지면 우리 세상이야!","en":"Lights out is our time!","ja":"明かりが消えたら俺たちの時間だ！"}},"team":[148,40,22,26,101,94],"run":{"id":"kanto-hideout","step":1,"steps":4}},{"id":"kanto-hideout-2","kind":"grunt","index":2,"types":["electric","ghost"],"level":50,"trainer":{"name":{"ko":"어둠전선 단원","en":"Dim Circuit Grunt","ja":"ディム・サーキットの下っ端"},"line":{"ko":"불 꺼지면 우리 세상이야!","en":"Lights out is our time!","ja":"明かりが消えたら俺たちの時間だ！"}},"team":[51,40,49,26,101,94],"run":{"id":"kanto-hideout","step":2,"steps":4}},{"id":"kanto-hideout-3","kind":"admin","index":3,"types":["electric","ghost"],"level":50,"trainer":{"name":{"ko":"퓨즈","en":"Fuse","ja":"ヒューズ"},"line":{"ko":"여기서부터는 정전이다.","en":"Power's out from here on.","ja":"ここから先は停電だ。"}},"team":[87,99,26,101,110,94],"run":{"id":"kanto-hideout","step":3,"steps":4}},{"id":"kanto-hideout-4","kind":"boss","index":4,"types":["electric","ghost"],"level":50,"trainer":{"name":{"ko":"어스름","en":"Umbra Vex","ja":"アンブラ・ヴェクス"},"line":{"ko":"세상 불을 다 꺼 주마.","en":"I'll put out every light in the world.","ja":"世界中の明かりを消してやる。"}},"team":[101,94,135,136,9,103],"run":{"id":"kanto-hideout","step":4,"steps":4}}]}}]}
"""#
