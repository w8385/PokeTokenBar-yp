import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct EntrySlotsShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { try SpeciesFacts.details(speciesID) }
}

/// Opt-in captures for the PR: the Battle tab's entry and the Box page's slot control, in Korean and English.
///
///     PTB_ENTRY_SLOTS_DIR=/tmp/shots swift test --filter EntrySlotsScreenshotTests
@MainActor
final class EntrySlotsScreenshotTests: XCTestCase {
    private let lineup = [(5, "charmeleon"), (25, "pikachu"), (94, "gengar"), (6, "zard"), (130, "gyarados"),
                          (149, "dragonite")]

    func testCaptureTheEntryAndTheSlotControl() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_ENTRY_SLOTS_DIR"] else {
            throw XCTSkip("Set PTB_ENTRY_SLOTS_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (species, _) in lineup {
            _ = await SpriteLoader.image(speciesID: species)
            _ = await SpriteLoader.image(speciesID: species, animated: true)
        }
        for language in [AppLanguage.ko, .en] {
            try await capture(language, to: directory)
        }
    }

    private func capture(_ language: AppLanguage, to directory: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("entry-slots-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.dex = lineup.map { species, id in entry(species, id: id) } + [entry(3, id: "venusaur")]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: EntrySlotsShotProvider(), fileURL: file)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "entry-slots-\(UUID())"))
        let battle = BattleEntryStore(defaults: defaults)
        lineup.forEach { battle.add($0.1) }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        let venusaur = try XCTUnwrap(store.state.dex.first { $0.id == "venusaur" })

        try write(BattleEntrySection(entry: battle, uploader: uploader, openPicker: { _ in })
            .environment(uploader).environment(battle).environment(store).environment(PopoverNavigation()),
                  language: language, height: 560, to: directory.appendingPathComponent("entry-tab-\(language.rawValue).png"))
        try write(BattleSlotControl(store: store, entry: venusaur, battleEntry: battle, onChange: {})
            .padding(.horizontal, Spacing.lg),
                  language: language, height: 90, to: directory.appendingPathComponent("entry-box-slots-\(language.rawValue).png"))
    }

    private func entry(_ species: Int, id: String) -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
        profile.level = 50
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false, profile: profile,
                             names: [species: ["ko": "#\(species)", "en": "#\(species)"]])
        entry.id = id
        return entry
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
}
