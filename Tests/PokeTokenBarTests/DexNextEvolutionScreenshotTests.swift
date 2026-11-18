import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct MunchlaxProvider: PokeProviding, SpeciesIndexProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 446, tree: EvoNode(speciesID: 446, children: [EvoNode(speciesID: 143, children: [])]),
                rarity: .rare, names: [446: try SpeciesFacts.names(446), 143: try SpeciesFacts.names(143)])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func speciesIndex() async throws -> SpeciesIndex {
        SpeciesIndex(entries: [try SpeciesFacts.indexEntry(446), try SpeciesFacts.indexEntry(143)])
    }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { try SpeciesFacts.details(speciesID) }
}

private struct NoFlavor: SpeciesFlavorProviding {
    func flavor(speciesID: Int) async -> SpeciesFlavor? { nil }
}

private final class ShotClock: @unchecked Sendable {
    var now = Calendar.current.date(bySettingHour: 12, minute: 1, second: 0, of: Date())!
}

/// Opt-in captures for the PR: Munchlax's Pokédex page, owned and raised. Sample data.
///
///     PTB_DEX_NEXT_SHOT_DIR=/tmp/shots swift test --filter DexNextEvolutionScreenshotTests
@MainActor
final class DexNextEvolutionScreenshotTests: XCTestCase {
    func testCaptureMunchlaxDexPage() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_DEX_NEXT_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_DEX_NEXT_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.ko, .en] {
            var owned = CompanionState()
            owned.dex = [DexEntry(baseID: 446, finalID: 446, chainOrder: [446], rarity: .rare,
                                  caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                                  names: [446: try SpeciesFacts.names(446)])]
            let plain = try await store(owned, language: language, ShotClock())
            try await capturePage(plain, language: language,
                                  to: directory.appendingPathComponent("dex-munchlax-\(language.rawValue).png"))

            let clock = ShotClock()
            let raised = try await store(CompanionState(), language: language, clock)
            await raised.hatch(baseID: 446)
            for _ in 0..<3 { clock.now.addTimeInterval(11); raised.recordPet() }
            try await capturePage(raised, language: language,
                                  to: directory.appendingPathComponent("dex-munchlax-raised-\(language.rawValue).png"))
            try await capture(CompanionHeader(store: raised, onOpenDexEntry: { _ in }).padding(12), height: 200,
                              language: language,
                              to: directory.appendingPathComponent("home-munchlax-raised-\(language.rawValue).png"))
            let snorlax = try XCTUnwrap(raised.unownedDexSpecies.first { $0.id == 143 })
            try await capture(UnownedSpeciesDetailView(store: raised, species: snorlax, onOpen: { _ in }, onBack: {},
                                                       flavorProvider: NoFlavor()),
                              height: 620, language: language,
                              to: directory.appendingPathComponent("dex-snorlax-unowned-raised-\(language.rawValue).png"))
        }
    }

    private func store(_ state: CompanionState, language: AppLanguage, _ clock: ShotClock) async throws
        -> CompanionStore {
        var state = state
        state.language = language
        state.installBaselineSet = true
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("dex-next-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "dex-next-shot-\(UUID())"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = CompanionStore(provider: MunchlaxProvider(), clock: { clock.now }, fileURL: file,
                                   rng: SeededRNG(seed: 1), dittoDisguiseRollingEnabled: false,
                                   defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        await store.loadSpeciesIndexIfNeeded()
        await store.loadPokemonDetails(speciesID: 446)
        return store
    }

    private func capturePage(_ store: CompanionStore, language: AppLanguage, to file: URL) async throws {
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 446 })
        try await capture(PokemonDetailView(store: store, species: species, onBack: {}, flavorProvider: NoFlavor()),
                          height: 620, language: language, to: file)
    }

    private func capture<V: View>(_ view: V, height: CGFloat, language: AppLanguage, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(
            view
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua, to: file)
    }
}
