import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct FormVarietyShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID, abilities: [PokemonAbilityOption(name: "natural-cure", slot: 1, isHidden: false)])
    }
}

/// Opt-in captures for the PR: a synthetic save with a Land and a Sky Shaymin, the real views.
///
///     PTB_FORM_VARIETY_SCREENSHOT_DIR=/tmp/shots swift test --filter FormVarietyScreenshotTests
@MainActor
final class FormVarietyScreenshotTests: XCTestCase {
    private func shaymin(id: String, form: String) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 492, instanceID: id)
        profile.level = 50
        var entry = DexEntry(baseID: 492, finalID: 492, chainOrder: [492], rarity: .legendary,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile,
                             names: [492: ["ko": "쉐이미", "en": "Shaymin"]])
        entry.id = id
        entry.form = PokemonForm(form)
        return entry
    }

    func testCaptureSkyShayminInTheBattleTabAndOnTheDexPage() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_FORM_VARIETY_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_FORM_VARIETY_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("form-variety-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.dex = [shaymin(id: "land", form: "land"), shaymin(id: "sky", form: "sky")]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: FormVarietyShotProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: 492)

        let defaults = UserDefaults(suiteName: "form-variety-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        ["land", "sky"].forEach { battle.add($0) }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"

        try await capture(VStack(spacing: 0) {
            BattleEntrySection(entry: battle, uploader: uploader, openPicker: { _ in })
        }.environment(uploader).environment(battle).environment(store).environment(PopoverNavigation()),
                          height: 420, to: directory.appendingPathComponent("battle-sky-shaymin.png"))

        var skyOnly = state
        skyOnly.dex = [shaymin(id: "sky", form: "sky")]
        let skyFile = scratch.appendingPathComponent("sky.json")
        try JSONEncoder().encode(skyOnly).write(to: skyFile)
        let skyStore = CompanionStore(provider: FormVarietyShotProvider(), fileURL: skyFile)
        await skyStore.loadPokemonDetails(speciesID: 492)
        let species = try XCTUnwrap(skyStore.dexSpecies.first { $0.id == 492 })
        try await capture(PokemonDetailView(store: skyStore, species: species, onBack: {}).environment(skyStore),
                          height: 760, to: directory.appendingPathComponent("dex-sky-shaymin.png"))
    }

    private func capture<V: View>(_ view: V, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, to: file)
    }
}
