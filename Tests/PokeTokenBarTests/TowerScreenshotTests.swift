import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct OfflineProvider: PokeProviding, SpeciesIndexProviding {
    static let rentalIDs = [3, 6, 9, 65, 68, 112, 130, 143, 149]

    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func speciesIndex() async throws -> SpeciesIndex {
        SpeciesIndex(entries: try Self.rentalIDs.map { try SpeciesFacts.indexEntry($0) })
    }
}

/// Opt-in captures for the PR: a synthetic save and a stubbed bot, the real views.
///
///     PTB_TOWER_SCREENSHOT_DIR=/tmp/shots swift test --filter TowerScreenshotTests
@MainActor
final class TowerScreenshotTests: XCTestCase {
    private var original: URL?
    private var scratch: URL!

    override func setUp() async throws {
        original = GymTrainerArt.directory
        GymTrainerArt.directory = GymRepo.trainerAssets
        GymTrainerArt.clearCache()
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tower-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        GymTrainerArt.directory = original
        GymTrainerArt.clearCache()
        try? FileManager.default.removeItem(at: scratch)
    }

    private struct Rig {
        let store: CompanionStore
        let entry: BattleEntryStore
        let service: TowerService
        let bot: TowerFakeBot
    }

    private func rig(_ language: AppLanguage, bp: Int = 37) throws -> Rig {
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.dex = [TowerFixtures.entry(448, id: "a"), TowerFixtures.entry(445, id: "b"), TowerFixtures.entry(373, id: "c")]
        state.tower.bp = bp
        state.tower.entry = ["a", "b", "c"]
        let file = scratch.appendingPathComponent("state-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: OfflineProvider(), fileURL: file)
        let bot = TowerFakeBot()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "tower-shot-\(UUID())"))
        let service = TowerService(link: { GymService.Link(server: "http://bot-host:8790", token: "synthetic") },
                                   exchange: bot.exchange, apply: { run, gain in store.applyTower(run, gain: gain) })
        return Rig(store: store, entry: BattleEntryStore(defaults: defaults), service: service, bot: bot)
    }

    private func shot(_ rig: Rig, height: CGFloat, to file: URL) async throws {
        let section = VStack(alignment: .leading, spacing: 6) {
            Text(rig.store.l.towerTitle).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            TowerSection(store: rig.store, entry: rig.entry, service: rig.service, onPickSlot: { _ in }).ptbCard()
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        let moveNames = PokemonNameDisplayStore()
        await MoveName.load(ids: StubMoveNames.table.keys, store: moveNames, provider: StubMoveNames())
        try await OffscreenRender.capture(
            section.frame(width: size.width, height: size.height)
                .background(Color.white).environment(\.colorScheme, .light)
                .environment(\.locale, rig.store.language.displayLocale)
                .environment(\.pokemonNameProvider, StubMoveNames()).environment(\.pokemonNameStore, moveNames),
            size: size, appearance: .aqua, to: file, until: {
                (!rig.service.runs.isEmpty || rig.service.last != nil)
                    && (rig.service.mode == .entry || rig.store.speciesIndex != nil)
            })
    }

    private func coworkerShot(_ rig: Rig, ranking: Bool, to file: URL) async throws {
        let info = BattleInfo(coworkers: [.init(name: "두리", pokemonId: 445, level: 52),
                                          .init(name: "세나", pokemonId: 149, level: 47, shiny: true)])
        let tab = VStack(alignment: .leading, spacing: 18) {
            BattleInfoSections(info: info, l: rig.store.l, parts: [.coworkers])
            if ranking { TowerRankingCard(service: rig.service, l: rig.store.l) }
        }
        .padding(.horizontal, 12).padding(.top, 8).frame(maxHeight: .infinity, alignment: .top)
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 400)
        try await OffscreenRender.capture(
            tab.frame(width: size.width, height: size.height).background(Color.white)
                .environment(\.colorScheme, .light).environment(\.locale, rig.store.language.displayLocale),
            size: size, appearance: .aqua, to: file, until: { !ranking || !rig.service.ranking.isEmpty })
    }

    private func record(entry: [String: Any], rental: [String: Any] = TowerFixtures.run("rental", streak: 0, best: 0)) -> Data {
        TowerFixtures.record(entry: entry, rental: rental)
    }

    func testCaptureTheTower() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_TOWER_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_TOWER_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.ko, .en] {
            let live = try rig(language)
            live.store.state.tower.records["entry"] = TowerModeRecord(streak: 23, best: 31, trophies: ["silver"])
            live.bot.replies["/v1/tower/record"] = [(record(entry: TowerFixtures.run(streak: 23, best: 31, trophies: ["silver"])), 200)]
            try await shot(live, height: 420, to: directory.appendingPathComponent("tower-entry-\(language.rawValue).png"))

            let owner = try rig(language)
            owner.bot.replies["/v1/tower/battle"] = [(TowerFixtures.battle(won: true, battle: 20, best: 20, bp: 10, trophy: "silver"), 200)]
            owner.bot.replies["/v1/tower/record"] = [(record(entry: TowerFixtures.run(streak: 20, best: 20, trophies: ["silver"])), 200)]
            let team = TowerEntry.team(state: owner.store.state, ids: owner.store.state.tower.entry, moveChoices: [:])
            await owner.service.fight(.entry, team: team)
            XCTAssertNotNil(owner.service.last)
            try await shot(owner, height: 520, to: directory.appendingPathComponent("tower-owner-win-\(language.rawValue).png"))

            let offer = try rig(language)
            offer.service.mode = .rental
            let six = TowerTests.rentals([112, 149, 68, 9, 6, 3])
            offer.bot.replies["/v1/tower/record"] = [(record(entry: TowerFixtures.run(streak: 0, best: 31),
                                                             rental: TowerFixtures.run("rental", streak: 0, best: 12,
                                                                                       extra: ["offer": six])), 200)]
            try await shot(offer, height: 520, to: directory.appendingPathComponent("tower-rental-offer-\(language.rawValue).png"))

            let swap = try rig(language)
            swap.service.mode = .rental
            swap.store.state.tower.records["rental"] = TowerModeRecord(streak: 4, best: 12)
            let rental = TowerFixtures.run("rental", streak: 4, best: 12, extra: [
                "team": TowerTests.rentals([112, 149, 9]), "beaten": TowerTests.rentals([143, 130, 65], item: "leftovers")])
            swap.bot.replies["/v1/tower/record"] = [(record(entry: TowerFixtures.run(streak: 0, best: 31), rental: rental), 200)]
            try await shot(swap, height: 560, to: directory.appendingPathComponent("tower-rental-swap-\(language.rawValue).png"))

            let exchange = try rig(language, bp: 1_240)
            exchange.store.state.dex.append(TowerFixtures.entry(6, id: "d"))
            let host = TowerExchangeView(store: exchange.store, onClose: {}).ptbCard()
                .padding(.horizontal, 12).padding(.top, 8).frame(maxHeight: .infinity, alignment: .top)
            let size = NSSize(width: PopoverMetrics.contentWidth, height: 1100)
            try await OffscreenRender.capture(
                host.frame(width: size.width, height: size.height).background(Color.white)
                    .environment(\.colorScheme, .light).environment(\.locale, language.displayLocale),
                size: size, appearance: .aqua,
                to: directory.appendingPathComponent("tower-exchange-\(language.rawValue).png"))

            let friends = try rig(language)
            friends.bot.replies["/v1/tower/record"] = [(TowerFixtures.record(
                entry: TowerFixtures.run(streak: 0, best: 12), rental: TowerFixtures.run("rental", streak: 0, best: 4),
                ranking: ["entry": [["name": "두리", "best": 30, "me": false], ["name": "하나", "best": 12, "me": true],
                                    ["name": "세나", "best": 7, "me": false]],
                          "rental": [["name": "세나", "best": 9, "me": false], ["name": "하나", "best": 4, "me": true]]]), 200)]
            try await coworkerShot(friends, ranking: false,
                                   to: directory.appendingPathComponent("coworkers-before-\(language.rawValue).png"))
            try await coworkerShot(friends, ranking: true,
                                   to: directory.appendingPathComponent("coworkers-after-\(language.rawValue).png"))
        }
    }
}
