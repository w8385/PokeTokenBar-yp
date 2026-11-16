import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ItemsShotProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "synthetic", height: 4, weight: 60, baseExperience: 112,
                       genderRate: 4, types: ["electric"],
                       baseStats: ["hp": 35, "attack": 55, "defense": 40, "special-attack": 50,
                                   "special-defense": 50, "speed": 90],
                       abilities: [], moves: [])
    }
}

/// Opt-in captures of the real views over a synthetic save.
///
///     PTB_ITEMS_MORE_SHOT_DIR=/tmp/shots swift test --filter ItemsMoreScreenshotTests
@MainActor
final class ItemsMoreScreenshotTests: XCTestCase {
    func testCaptureShopAndEverstoneBoxDetail() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_ITEMS_MORE_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_ITEMS_MORE_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("items-more-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 30_000_000_000
        var pikachuProfile = PokemonProfile.generate(seed: 25, instanceID: "pikachu")
        pikachuProfile.level = 42
        var pikachu = DexEntry(baseID: 172, finalID: 25, chainOrder: [172, 25], rarity: .rare,
                               caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: pikachuProfile,
                               names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        pikachu.id = "pikachu"
        state.dex = [pikachu]
        state.heldItems = ["pikachu": ItemKind.everstone.rawValue]
        state.inventory = ["eviolite": 1, "choiceSpecs": 1]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: ItemsShotProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: 25)

        let defaults = UserDefaults(suiteName: "items-more-shot-\(UUID())")!
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data(), 404) }, partySource: { [] })
        let battle = BattleEntryStore(defaults: defaults)
        let nav = PopoverNavigation()

        try await capture(ShopView(store: store, nav: nav, initialCategory: ItemCategory.heldItem).environment(store),
                          to: directory.appendingPathComponent("items-more-shop-held-items.png"), height: 760)
        let individual = BoxIndividual(id: "pikachu", entry: pikachu, role: .graduated)
        try await capture(BoxDetailView(store: store, individual: individual, navigation: nav, onBack: {})
            .environment(uploader).environment(battle).environment(store),
                          to: directory.appendingPathComponent("items-more-box-everstone.png"), height: 620)
    }

    private func capture<V: View>(_ view: V, to file: URL, height: CGFloat) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, AppLanguage.ko.displayLocale),
            size: size, appearance: .aqua, settle: .seconds(4), to: file)
    }
}
