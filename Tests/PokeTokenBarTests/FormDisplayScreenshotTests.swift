import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct FormShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID, abilities: [PokemonAbilityOption(name: "unseen-fist", slot: 1, isHidden: false)],
                                 moves: ["wicked-blow", "close-combat", "aqua-jet"].map {
                                     PokemonMoveOption(name: $0, learnMethods: [PokemonMoveLearnMethod(method: "level-up", level: 1)])
                                 })
    }
}

/// Opt-in captures for the PR: a graduated Rapid Strike Urshifu on its Pokédex page, sample data.
///
///     PTB_FORM_SHOT_DIR=/tmp/shots swift test --filter FormDisplayScreenshotTests
@MainActor
final class FormDisplayScreenshotTests: XCTestCase {
    func testCaptureRapidStrikeUrshifuDexPage() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_FORM_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_FORM_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("form-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        for language in [AppLanguage.ko, .en] {
            var profile = PokemonProfile.generate(seed: 892, instanceID: "urshifu")
            profile.level = 60
            var entry = DexEntry(id: "urshifu", baseID: 891, finalID: 892, chainOrder: [891, 892], rarity: .legendary,
                                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile,
                                 names: [891: try SpeciesFacts.names(891), 892: try SpeciesFacts.names(892)])
            entry.form = PokemonForm("rapid-strike")
            var state = CompanionState()
            state.language = language
            state.installBaselineSet = true
            state.dex = [entry]
            let file = scratch.appendingPathComponent("state-\(language.rawValue).json")
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: FormShotProvider(), fileURL: file, dittoDisguiseRollingEnabled: false)
            await store.loadPokemonDetails(speciesID: 892)

            let defaults = try XCTUnwrap(UserDefaults(suiteName: "form-shot-\(UUID())"))
            let battle = BattleEntryStore(defaults: defaults)
            let uploader = PartyUploader(
                tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
                appVersion: "shot", fetch: { _ in (Data(), 200) }, partySource: { [] })
            let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 892 })
            let view = PokemonDetailView(store: store, species: species, onBack: {})
                .environment(uploader).environment(battle).environment(store).environment(PopoverNavigation())
            let size = NSSize(width: PopoverMetrics.contentWidth, height: 1180)
            try await OffscreenRender.capture(view.frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .environment(\.locale, language.displayLocale),
                size: size, appearance: .aqua,
                to: directory.appendingPathComponent("urshifu-rapid-strike-dex-\(language.rawValue).png"))
        }
    }
}
