import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct TradeShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 92, tree: EvoNode(speciesID: 92, children: [
            EvoNode(speciesID: 93, children: [
                EvoNode(speciesID: 94, children: [], methods: [EvoMethod(trigger: "trade", item: nil)])],
                    methods: [EvoMethod(trigger: "level-up", item: nil)])]),
                rarity: .rare,
                names: [92: ["ko": "고오스"], 93: ["ko": "고우스트"], 94: ["ko": "팬텀"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Opt-in captures for the PR: a synthetic save, the real views.
///
///     PTB_TRADE_SCREENSHOT_DIR=/tmp/shots swift test --filter TradeScreenshotTests
@MainActor
final class TradeScreenshotTests: XCTestCase {
    private func entry(_ base: Int, _ final: Int, chain: [Int], id: String, ko: String, level: Int,
                       shiny: Bool = false, rarity: Rarity = .common) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(final), instanceID: id)
        profile.level = level
        return DexEntry(id: id, baseID: base, finalID: final, chainOrder: chain, rarity: rarity,
                        caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(level)), isShiny: shiny,
                        profile: profile, names: [final: ["ko": ko]])
    }

    func testCaptureOfferSheetArrivalAndCordDetail() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_TRADE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_TRADE_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("trade-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: raised)
        state.inventory[ItemKind.linkingCord.rawValue] = 1
        state.dex = [
            entry(25, 26, chain: [25, 26], id: "raichu", ko: "라이츄", level: 62, shiny: true, rarity: .rare),
            entry(92, 93, chain: [92, 93], id: "haunter", ko: "고우스트", level: 41, rarity: .rare),
            entry(143, 143, chain: [143], id: "snorlax", ko: "잠만보", level: 47, rarity: .rare),
            entry(130, 130, chain: [129, 130], id: "gyarados", ko: "갸라도스", level: 33),
            entry(10, 10, chain: [10], id: "caterpie", ko: "캐터피", level: 9),
        ]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: TradeShotProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: 93)

        let defaults = UserDefaults(suiteName: "trade-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        battle.add("raichu")
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 200) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        try await capture(TradeOfferView(store: store, uploader: uploader, fightingIDs: ["raichu"], initialGive: "haunter",
                                         initialCoworkers: [TradeCoworker(id: "u1", name: "Alex Kim"),
                                                            TradeCoworker(id: "u2", name: "Sam Lee"),
                                                            TradeCoworker(id: "u3", name: "Jordan Park")],
                                         onBack: {})
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("trade-offer-sheet.png"))

        try await capture(BagView(store: store, nav: PopoverNavigation()),
                          to: directory.appendingPathComponent("trade-bag-cord.png"))
        let haunter = try XCTUnwrap(store.dexSpecies.first { $0.id == 93 })
        try await capture(PokemonDetailView(store: store, species: haunter, onBack: {})
            .environment(uploader).environment(battle).environment(store).environment(PopoverNavigation()),
                          to: directory.appendingPathComponent("trade-dex-detail-cord.png"))

        var arriving = entry(92, 93, chain: [92, 93], id: "wire", ko: "고우스트", level: 41, shiny: false, rarity: .rare)
        arriving.originalTrainer = nil
        let item = TradePoolEntry(id: "wire", pokemonID: 93, level: 41, shiny: false, name: "고우스트", entry: arriving)
        let body = try JSONSerialization.data(withJSONObject: [
            "trades": ["deliveries": [[
                "trade_id": "shot-1", "give_id": "snorlax", "from_name": "Alex Kim",
                "receive": try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)),
            ]]],
        ])
        store.applyTrades(TradeSyncReply.decode(body).deliveries)
        await store.resolveTradeEvolutions()
        XCTAssertEqual(store.tradeArrival?.evolvedID, 94)
        try await capture(VStack(spacing: 8) {
            TradeArrivalBanner(store: store)
            BattleView(store: store, navigation: PopoverNavigation(), initialPickerQuery: "")
        }.environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("trade-arrival-evolution.png"), height: 620)
    }

    private func capture<V: View>(_ view: V, to file: URL, height: CGFloat = 520) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, settle: .seconds(5), to: file)
    }
}
