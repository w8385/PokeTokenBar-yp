import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct EvolutionShotProvider: PokeProviding, PokemonDetailProviding, SpeciesIndexProviding {
    func speciesIndex() async throws -> SpeciesIndex {
        let names: [Int: (String, String)] = [686: ("Inkay", "개무소"), 687: ("Malamar", "오케이징"), 95: ("Onix", "롱스톤"),
                                              208: ("Steelix", "강철톤"), 106: ("Hitmonlee", "시라소몬"), 236: ("Tyrogue", "배리볼")]
        return SpeciesIndex(entries: names.map { id, n in
            SpeciesIndexEntry(id: id, names: ["en": n.0, "ko": n.1], types: [], captureRate: 45, isLegendary: false,
                              isMythical: false, evolvesFromID: nil)
        })
    }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 686, tree: EvoNode(speciesID: 686, children: [
            EvoNode(speciesID: 687, children: [], methods: [EvoMethod(trigger: "level-up", item: nil)])]),
                rarity: .common, names: [686: ["ko": "개무소", "en": "Inkay"], 687: ["ko": "오케이징", "en": "Malamar"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "synthetic", height: 4, weight: 35,
            baseExperience: 58, genderRate: 4, types: speciesID == 686 || speciesID == 687 ? ["dark", "psychic"] : speciesID == 106 ? ["fighting"] : ["rock", "ground"],
            baseStats: ["hp": 53, "attack": 54, "defense": 53, "special-attack": 37, "special-defense": 46, "speed": 45],
            abilities: [], moves: [])
    }
}

/// Opt-in captures for the PR: a synthetic save, the real dex detail view.
///
///     PTB_EVO_SHOT_DIR=/tmp/shots swift test --filter EvolutionShotTests
@MainActor
final class EvolutionShotTests: XCTestCase {
    private func entry(_ id: String, base: Int, final: Int, level: Int, nature: PokemonNature = .adamant,
                       ivs: PokemonIVs? = nil, names: [Int: [String: String]]) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(final), instanceID: id)
        profile.level = level
        if let ivs { profile.ivs = ivs }
        return DexEntry(id: id, baseID: base, finalID: final, chainOrder: [base, final], rarity: .common,
                        caughtAt: Date(timeIntervalSince1970: 1_700_000_000), nature: nature,
                        profile: profile, names: names)
    }

    func testCaptureInkayTyrogueAndOnix() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_EVO_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_EVO_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("evo-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        for language in [AppLanguage.ko, .en] {
            var state = CompanionState()
            state.language = language
            state.installBaselineSet = true
            state.usedSinceInstall = 6_000_000_000
            var raised = PokemonProfile.generate(seed: 7, instanceID: "raised")
            raised.level = 28
            state.active = MonState(baseID: 686, pathIDs: [686], plannedPathIDs: [686, 687], stageIndex: 0,
                                    usedAtStage: 0, rarity: .common, totalForms: 2, profile: raised)
            let attackHeavy = PokemonIVs(hp: 10, attack: 31, defense: 2, specialAttack: 10, specialDefense: 10, speed: 10)
            state.dex = [
                entry("inkay", base: 686, final: 686, level: 12, names: [686: ["ko": "개무소", "en": "Inkay"]]),
                entry("tyrogue", base: 236, final: 106, level: 24, ivs: attackHeavy,
                      names: [106: ["ko": "시라소몬", "en": "Hitmonlee"]]),
                entry("onix", base: 95, final: 95, level: 40, names: [95: ["ko": "롱스톤", "en": "Onix"]]),
            ]
            state.inventory[ItemKind.metalCoat.rawValue] = 1
            let file = scratch.appendingPathComponent("state-\(language.rawValue).json")
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: EvolutionShotProvider(), fileURL: file, dittoDisguiseRollingEnabled: false)
            store.update(todayTokensByProvider: ["shot": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                         limitWarning: false, hasUsageData: true)
            for _ in 0..<100 where store.currentLine == nil { await Task.yield() }
            await store.loadPokemonDetails(speciesID: 686)
            await store.loadPokemonDetails(speciesID: 106)
            await store.loadPokemonDetails(speciesID: 95)

            let defaults = UserDefaults(suiteName: "evo-shot-\(UUID())")!
            let battle = BattleEntryStore(defaults: defaults)
            let uploader = PartyUploader(
                tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
                appVersion: "shot", fetch: { _ in (Data(), 200) }, partySource: { [] })

            for (id, name) in [(686, "inkay"), (106, "tyrogue"), (95, "onix-trade")] {
                let species = try XCTUnwrap(store.dexSpecies.first { $0.id == id }, "\(id)")
                try await capture(PokemonDetailView(store: store, species: species, onBack: {})
                    .environment(uploader).environment(battle).environment(store).environment(PopoverNavigation()),
                                  language: language,
                                  to: directory.appendingPathComponent("\(name)-\(language.rawValue).png"))
            }
        }
    }

    private func capture<V: View>(_ view: V, language: AppLanguage, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 640)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale))
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
