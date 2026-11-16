import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct PickerRenderProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "parasect", height: 10, weight: 295,
            baseExperience: 142, genderRate: 4, types: ["bug", "grass"],
            baseStats: ["hp": 60, "attack": 95, "defense": 80, "special-attack": 60, "special-defense": 80, "speed": 30],
            abilities: [PokemonAbilityOption(name: "effect-spore", slot: 1, isHidden: false)], moves: [])
    }
}
@MainActor
final class IndividualPickerRenderingTests: XCTestCase {
    func testSpeciesPageHasNoIndividualPickerForOneOrManyOwned() async throws {
        for count in [1, 2] {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("individual-picker-\(UUID())")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("state.json")
            var state = CompanionState()
            state.language = .en
            state.dex = (0..<count).map { i in
                DexEntry(id: "fixture-\(i)", baseID: 46, finalID: 47, chainOrder: [46,47], rarity: .common,
                    caughtAt: Date(timeIntervalSince1970: 1700000000 + Double(i)),
                    profile: PokemonProfile.generate(seed: UInt64(i + 1), instanceID: "fixture-\(i)"),
                    names: [47: ["en": "Parasect"]])
            }
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: PickerRenderProvider(), fileURL: file)
            await store.loadPokemonDetails(speciesID: 47)
            let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 47 })
            let view = PokemonDetailView(store: store, species: species, onBack: {},
                spriteStore: SpriteStore(directory: dir))
                .frame(width: PopoverMetrics.contentWidth, height: 520)
                .background(Color.white).environment(\.colorScheme, .light)
            let host = OffscreenRender.host(view, size: CGSize(width: PopoverMetrics.contentWidth, height: 520),
                                            appearance: .aqua)
            try await OffscreenRender.settle(host, for: .milliseconds(100))
            func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
            XCTAssertGreaterThan(descendants(host).count, 1, "the page mounted nothing")
            let menus = descendants(host).compactMap { $0 as? NSPopUpButton }
            XCTAssertEqual(menus.count, 0, "the species page never picks between individuals (\(count) owned)")
        }
    }
}
