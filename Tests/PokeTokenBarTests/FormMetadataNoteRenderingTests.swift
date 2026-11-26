import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct FormMetadataProvider: PokeProviding, PokemonDetailProviding {
    let detailsAvailable: Bool

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .legendary, names: [baseSpeciesID: ["en": "Shellos"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        guard detailsAvailable else { throw URLError(.notConnectedToInternet) }
        let ability = speciesID == 422 ? [PokemonAbilityOption(name: "sticky-hold", slot: 1, isHidden: false)] : []
        return try SpeciesFacts.details(speciesID, abilities: ability)
    }
}

/// Measures the real Home header and Pokédex identity header: a helper-only test would miss either call site.
@MainActor
final class FormMetadataNoteRenderingTests: XCTestCase {
    private func store(form: PokemonForm?, speciesID: Int = 422, egg: Bool = false,
                       detailsAvailable: Bool = true) async throws -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("form-note-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let suite = "FormMetadataNote-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var state = CompanionState()
        state.language = .en
        if !egg {
            state.active = MonState(baseID: speciesID, pathIDs: [speciesID], stageIndex: 0,
                usedAtStage: 0, rarity: .legendary, totalForms: 1, form: form)
            let forms: [PokemonForm?] = speciesID == 422 ? [PokemonForm("west"), PokemonForm("east")] : [nil]
            state.dex = forms.map {
                DexEntry(baseID: speciesID, finalID: speciesID, chainOrder: [speciesID], rarity: .legendary,
                         caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                         names: [speciesID: ["en": "Shellos"]], form: $0)
            }
            state.representativeSpeciesID = speciesID
            state.representativeForm = form
        }
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: FormMetadataProvider(detailsAvailable: detailsAvailable),
                                   fileURL: file, defaults: defaults)
        if !egg && detailsAvailable { await store.loadPokemonDetails(speciesID: speciesID) }
        return store
    }

    /// What the note adds to a header: one caption line or more, so any real note is well above this.
    private let noteLine: CGFloat = 8

    private func homeHeight(_ store: CompanionStore) -> CGFloat {
        LayoutMeasure.size(CompanionHeader(store: store).frame(width: PopoverMetrics.contentWidth),
                           width: PopoverMetrics.contentWidth).height
    }

    private func detailHeaderHeight(_ store: CompanionStore) throws -> CGFloat {
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 422 })
        let header = PokemonDetailView(store: store, species: species, onBack: {}).identityText
        return LayoutMeasure.size(header.frame(width: PopoverMetrics.contentWidth),
                                  width: PopoverMetrics.contentWidth).height
    }

    func testHomeExplainsLoadedAlternateMetadataOnly() async throws {
        let east = try await store(form: PokemonForm("east"))
        let west = try await store(form: PokemonForm("west"))
        XCTAssertGreaterThanOrEqual(homeHeight(east) - homeHeight(west), noteLine,
                                    "an alternate form must add the default-form note to Home")

        // Where the form is the default one, or the details are not loaded, the header gains no line.
        let eastOnPikachu = try await store(form: PokemonForm("east"), speciesID: 25)
        let plainPikachu = try await store(form: nil, speciesID: 25)
        XCTAssertTrue(PokemonForm.isDefault(PokemonForm("east"), speciesID: 25))
        XCTAssertEqual(homeHeight(eastOnPikachu), homeHeight(plainPikachu), accuracy: 0.5)
        let eastUnloaded = try await store(form: PokemonForm("east"), detailsAvailable: false)
        let westUnloaded = try await store(form: PokemonForm("west"), detailsAvailable: false)
        XCTAssertNil(eastUnloaded.pokemonDetailsByID[422])
        XCTAssertEqual(homeHeight(eastUnloaded), homeHeight(westUnloaded), accuracy: 0.5)
        let egg = try await store(form: nil, egg: true, detailsAvailable: false)
        XCTAssertFalse(egg.hasActive)
    }

    func testDexExplainsTheDisplayedFormRatherThanTheOriginalSelection() async throws {
        // Pass the aggregate/default species, as CollectionView does; the representative is East.
        let west = try await store(form: PokemonForm("west"))
        let east = try await store(form: PokemonForm("east"))
        XCTAssertGreaterThanOrEqual(try detailHeaderHeight(east) - detailHeaderHeight(west), noteLine,
                                    "the displayed East form must add the default-form note to the Pokédex page")
    }
}
