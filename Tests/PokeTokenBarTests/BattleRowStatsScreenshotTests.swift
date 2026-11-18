import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct RowStatsShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

/// Opt-in captures for the PR: a synthetic save, the real battle tab lineup.
///
///     PTB_ROW_STATS_SHOT_DIR=/tmp/shots swift test --filter BattleRowStatsScreenshotTests
@MainActor
final class BattleRowStatsScreenshotTests: XCTestCase {
    func testCaptureLineupWithAMegaHolder() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_ROW_STATS_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_ROW_STATS_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let megaLineup = try [
            entry(6, id: "zard", level: 62, nature: .adamant),
            entry(94, id: "gengar", level: 38, nature: .timid),
            entry(149, id: "dragonite", level: 55, nature: .hardy),
        ]
        let formLineup = try [
            entry(645, id: "landorus", level: 58, nature: .jolly, form: PokemonForm("therian")),
            entry(898, id: "calyrex", level: 60, nature: .brave, form: PokemonForm("ice")),
        ]
        let stone = try XCTUnwrap(MegaStone.stone(slug: "charizardite-x")).inventoryKey
        for language in [AppLanguage.ko, .en] {
            try await captureLineup(megaLineup, heldItems: ["zard": stone], language: language,
                                    to: directory.appendingPathComponent("row-stats-\(language.rawValue).png"))
            try await captureLineup(formLineup, heldItems: [:], language: language,
                                    to: directory.appendingPathComponent("row-forms-\(language.rawValue).png"))
        }
    }

    private func captureLineup(_ lineup: [DexEntry], heldItems: [String: String], language: AppLanguage,
                               to file: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("row-stats-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = language
        state.installBaselineSet = true
        state.dex = lineup
        state.heldItems = heldItems
        let stateFile = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: stateFile)
        let store = CompanionStore(provider: RowStatsShotProvider(), fileURL: stateFile)
        for entry in lineup { await store.loadPokemonDetails(speciesID: entry.finalID) }

        let defaults = UserDefaults(suiteName: "row-stats-shot-\(UUID())")!
        let battle = BattleEntryStore(defaults: defaults)
        lineup.forEach { battle.add($0.id) }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 560)
        try await OffscreenRender.capture(VStack(spacing: 0) {
            BattleEntrySection(entry: battle, uploader: uploader, openPicker: { _ in })
            Spacer(minLength: 0)
        }
        .environment(uploader).environment(battle).environment(store).environment(PopoverNavigation())
        .frame(width: size.width, height: size.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua, to: file)
    }

    private func entry(_ species: Int, id: String, level: Int, nature: PokemonNature,
                       form: PokemonForm? = nil) throws -> DexEntry {
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
        profile.level = level
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .rare,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile,
                             names: [species: try SpeciesFacts.names(species)])
        entry.id = id
        entry.nature = nature
        entry.form = form
        return entry
    }
}
