import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct FormMetadataProvider: PokeProviding, PokemonDetailProviding {
    let detailsAvailable: Bool

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .legendary, names: [baseSpeciesID: ["en": "Shaymin"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        guard detailsAvailable else { throw URLError(.notConnectedToInternet) }
        // Default Shaymin types, stats and ability. Alternate forms deliberately keep this data.
        return PokemonDetails(speciesID: speciesID, name: "shaymin", height: 2, weight: 21,
            baseExperience: 270, genderRate: -1, types: ["grass"],
            baseStats: Dictionary(uniqueKeysWithValues: PokemonStatCalculator.order.map { ($0, 100) }),
            abilities: [PokemonAbilityOption(name: "natural-cure", slot: 1, isHidden: false)], moves: [])
    }
}

/// Measures the real Home header and Pokédex identity header: a helper-only test would miss either call site.
@MainActor
final class FormMetadataNoteRenderingTests: XCTestCase {
    private func store(form: PokemonForm?, speciesID: Int = 492, egg: Bool = false,
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
            let forms: [PokemonForm?] = speciesID == 492 ? [PokemonForm("land"), PokemonForm("sky")] : [nil]
            state.dex = forms.map {
                DexEntry(baseID: speciesID, finalID: speciesID, chainOrder: [speciesID], rarity: .legendary,
                         caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                         names: [speciesID: ["en": "Shaymin"]], form: $0)
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
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 492 })
        let header = PokemonDetailView(store: store, species: species, onBack: {}).identityText
        return LayoutMeasure.size(header.frame(width: PopoverMetrics.contentWidth),
                                  width: PopoverMetrics.contentWidth).height
    }

    func testHomeExplainsLoadedAlternateMetadataOnly() async throws {
        let sky = try await store(form: PokemonForm("sky"))
        let land = try await store(form: PokemonForm("land"))
        XCTAssertGreaterThanOrEqual(homeHeight(sky) - homeHeight(land), noteLine,
                                    "an alternate form must add the default-form note to Home")

        // Where the form is the default one, or the details are not loaded, the header gains no line.
        let skyOnPikachu = try await store(form: PokemonForm("sky"), speciesID: 25)
        let plainPikachu = try await store(form: nil, speciesID: 25)
        XCTAssertTrue(PokemonForm.isDefault(PokemonForm("sky"), speciesID: 25))
        XCTAssertEqual(homeHeight(skyOnPikachu), homeHeight(plainPikachu), accuracy: 0.5)
        let skyUnloaded = try await store(form: PokemonForm("sky"), detailsAvailable: false)
        let landUnloaded = try await store(form: PokemonForm("land"), detailsAvailable: false)
        XCTAssertNil(skyUnloaded.pokemonDetailsByID[492])
        XCTAssertEqual(homeHeight(skyUnloaded), homeHeight(landUnloaded), accuracy: 0.5)
        let egg = try await store(form: nil, egg: true, detailsAvailable: false)
        XCTAssertFalse(egg.hasActive)
    }

    func testDexExplainsTheDisplayedFormRatherThanTheOriginalSelection() async throws {
        // Pass the aggregate/default species, as CollectionView does; the representative is Sky.
        let land = try await store(form: PokemonForm("land"))
        let sky = try await store(form: PokemonForm("sky"))
        XCTAssertGreaterThanOrEqual(try detailHeaderHeight(sky) - detailHeaderHeight(land), noteLine,
                                    "the displayed Sky form must add the default-form note to the Pokédex page")
    }
}
