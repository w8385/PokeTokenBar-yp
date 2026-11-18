import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// `BoxDexFixture` plus a Johto Xatu and a Sinnoh Lucario, so the Box spans more than one region and grade.
enum BoxChipsFixture {
    static let xatuID = "xatu"
    static let lucarioID = "lucario"

    static func state(language: AppLanguage) -> CompanionState {
        var state = BoxDexFixture.state(language: language)
        func entry(_ id: String, species: Int, chain: [Int], rarity: Rarity, level: Int, names: [Int: [String: String]],
                   at offset: Double) -> DexEntry {
            var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: id)
            profile.level = level
            return DexEntry(id: id, baseID: chain[0], finalID: species, chainOrder: chain, rarity: rarity,
                            caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + offset), profile: profile, names: names)
        }
        state.dex += [
            entry(xatuID, species: 178, chain: [177, 178], rarity: .rare, level: 55,
                  names: [177: ["ko": "네이티", "en": "Natu"], 178: ["ko": "네이티오", "en": "Xatu"]], at: 500),
            entry(lucarioID, species: 448, chain: [447, 448], rarity: .uncommon, level: 36,
                  names: [447: ["ko": "리오르", "en": "Riolu"], 448: ["ko": "루카리오", "en": "Lucario"]], at: 600),
        ]
        return state
    }

    struct Provider: PokeProviding, PokemonDetailProviding {
        func line(baseSpeciesID: Int) async throws -> EvoLine { try await BoxDexProvider().line(baseSpeciesID: baseSpeciesID) }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
        func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
        func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { try SpeciesFacts.details(speciesID) }
    }

    static let speciesIDs = [5, 25, 6, 95, 133, 178, 448]

    @MainActor
    static func makeStore(language: AppLanguage, test: XCTestCase,
                          mutate: (inout CompanionState) -> Void = { _ in }) async throws -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("box-chips-\(UUID()).json")
        var state = state(language: language)
        mutate(&state)
        try JSONEncoder().encode(state).write(to: file)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(provider: Provider(), fileURL: file)
        for id in speciesIDs { await store.loadPokemonDetails(speciesID: id) }
        return store
    }

    @MainActor
    static func navigation(test: XCTestCase) throws -> PopoverNavigation {
        let suite = "box-chips-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        test.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let navigation = PopoverNavigation(boxFilters: BoxFilterStore(defaults: defaults), defaults: defaults)
        navigation.tab = .box
        return navigation
    }
}

/// Opt-in captures: a synthetic save, the real Box view, ko and en.
///
///     PTB_BOX_CHIPS_SCREENSHOT_DIR=/tmp/shots swift test --filter BoxChipsScreenshotTests
@MainActor
final class BoxChipsScreenshotTests: XCTestCase {
    func testCaptureBoxChips() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BOX_CHIPS_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_BOX_CHIPS_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = ProcessInfo.processInfo.environment["PTB_BOX_CHIPS_STAGE"] ?? "after"
        for language in [AppLanguage.ko, .en] {
            let store = try await BoxChipsFixture.makeStore(language: language, test: self)
            let navigation = try BoxChipsFixture.navigation(test: self)
            if stage == "after" {
                navigation.boxFilters.filter.region = .kanto
                navigation.boxFilters.filter.rarity = .rare
            }
            try await capture(BoxView(store: store, navigation: navigation).environment(store), language: language,
                              to: directory.appendingPathComponent("box-chips-\(stage)-\(language.rawValue).png"))
        }
    }

    private func capture<V: View>(_ view: V, language: AppLanguage, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: BoxView.contentHeight)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua, scale: 2, to: file)
    }
}
