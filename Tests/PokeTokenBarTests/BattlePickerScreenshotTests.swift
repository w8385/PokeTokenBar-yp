import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [
            EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                rarity: .common,
                names: [4: ["ko": "파이리"], 5: ["ko": "리자드"], 6: ["ko": "리자몽"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        let types: [Int: [String]] = [6: ["fire", "flying"], 25: ["electric"], 94: ["ghost", "poison"],
                                      130: ["water", "flying"], 143: ["normal"], 149: ["dragon", "flying"]]
        return PokemonDetails(speciesID: speciesID, name: "synthetic", height: 10, weight: 295,
            baseExperience: 142, genderRate: 4, types: types[speciesID] ?? ["normal"],
            baseStats: ["hp": 60, "attack": 95, "defense": 80, "special-attack": 60, "special-defense": 80, "speed": 30],
            abilities: [], moves: [])
    }
}

private let movesJSON = """
{"moves":[
 {"id":85,"name":"10만볼트","type":"electric","power":90,"damage_class":"special","accuracy":100,"level":26,"pp":15},
 {"id":98,"name":"전광석화","type":"normal","power":40,"damage_class":"physical","accuracy":100,"level":10,"pp":30}
],"default":[85,98]}
"""

/// Opt-in captures for the PR: a synthetic save, the real views.
///
///     PTB_BATTLEPICKER_SCREENSHOT_DIR=/tmp/shots swift test --filter BattlePickerScreenshotTests
@MainActor
final class BattlePickerScreenshotTests: XCTestCase {
    private func entry(_ species: Int, id: String, ko: String, en: String, level: Int,
                       rarity: Rarity = .common, shiny: Bool = false) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
        profile.level = level
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: rarity,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: shiny, profile: profile,
                             names: [species: ["ko": ko, "en": en]])
        entry.id = id
        return entry
    }

    func testCaptureBattleTabPickerAndDexDetail() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BATTLEPICKER_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_BATTLEPICKER_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("battlepicker-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: raised)
        state.dex = [
            entry(25, id: "pikachu", ko: "피카츄", en: "Pikachu", level: 62, rarity: .rare, shiny: true),
            entry(6, id: "charizard", ko: "리자몽", en: "Charizard", level: 55, rarity: .rare),
            entry(94, id: "gengar", ko: "팬텀", en: "Gengar", level: 38, rarity: .rare),
            entry(130, id: "gyarados", ko: "갸라도스", en: "Gyarados", level: 33, rarity: .uncommon),
            entry(143, id: "snorlax", ko: "잠만보", en: "Snorlax", level: 47, rarity: .rare),
            entry(149, id: "dragonite", ko: "망나뇽", en: "Dragonite", level: 18, rarity: .legendary),
            entry(10, id: "caterpie", ko: "캐터피", en: "Caterpie", level: 9),
            entry(16, id: "pidgey", ko: "구구", en: "Pidgey", level: 12),
        ]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: ShotProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: 25)
        try await Task.sleep(for: .seconds(1))

        let defaults = UserDefaults(suiteName: "battlepicker-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        battle.add("pikachu")
        battle.add("gengar")
        battle.add("snorlax")
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 },
            fetch: { _ in (Data(movesJSON.utf8), 200) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        let nav = PopoverNavigation()
        func battleTab(_ query: String = "") -> some View {
            BattleView(store: store, navigation: nav, initialPickerQuery: query)
                .environment(uploader).environment(battle).environment(store)
        }
        try await capture(battleTab(), to: directory.appendingPathComponent("battle-tab-after.png"))
        nav.battlePicker = .slot("pikachu")
        try await capture(battleTab(), to: directory.appendingPathComponent("battle-picker.png"))
        try await capture(battleTab("리자"), to: directory.appendingPathComponent("battle-picker-search.png"))

        battle.remove("snorlax")
        let charizard = try XCTUnwrap(store.dexSpecies.first { $0.id == 6 })
        try await capture(PokemonDetailView(store: store, species: charizard, onBack: {})
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("dex-detail-send.png"))
        battle.add("charizard")
        try await capture(PokemonDetailView(store: store, species: charizard, onBack: {})
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("dex-detail-fighting.png"))
    }

    private func capture<V: View>(_ view: V, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
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
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
