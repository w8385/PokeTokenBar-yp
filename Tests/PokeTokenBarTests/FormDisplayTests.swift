import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private let speciesDefaultAbility = PokemonAbilityOption(name: "species-default-ability", slot: 1, isHidden: false)

private struct FormDisplayProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID, abilities: [speciesDefaultAbility],
                                 moves: [PokemonMoveOption(name: "tackle", learnMethods: [])])
    }
}

/// Every form that is its own PokéAPI variety with battle data, as a graduated Pokédex entry.
@MainActor
final class FormDisplayTests: XCTestCase {
    private struct FormCase {
        let speciesID: Int
        let form: PokemonForm
        let pokemonID: Int
        let data: FormBattleData
    }

    private static var formCases: [FormCase] {
        PokemonForm.catalog.flatMap { speciesID, entries in
            entries.compactMap { entry in
                guard let pokemonID = entry.pokemonID, let data = FormBattleData.byPokemonID[pokemonID] else { return nil }
                return FormCase(speciesID: speciesID, form: entry.form, pokemonID: pokemonID, data: data)
            }
        }.sorted { ($0.speciesID, $0.form.rawValue) < ($1.speciesID, $1.form.rawValue) }
    }

    private func graduate(_ speciesID: Int, form: PokemonForm?, id: String = "graduate") throws -> DexEntry {
        let baseID = [892: 891][speciesID] ?? speciesID
        XCTAssertTrue(PokemonForm.formSpecies(baseID: baseID).contains(speciesID), "#\(speciesID) needs its line base")
        var entry = DexEntry(id: id, baseID: baseID, finalID: speciesID,
                             chainOrder: baseID == speciesID ? [speciesID] : [baseID, speciesID],
                             rarity: .legendary, caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                             profile: PokemonProfile.generate(seed: UInt64(speciesID), instanceID: id),
                             names: [speciesID: try SpeciesFacts.names(speciesID)])
        entry.form = form
        return entry
    }

    private func store(_ state: CompanionState, loading speciesIDs: [Int]) async throws -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("form-display-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        var state = state
        state.language = .en
        state.installBaselineSet = true
        try JSONEncoder().encode(state).write(to: file)
        let suite = "FormDisplay-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = CompanionStore(provider: FormDisplayProvider(), fileURL: file, dittoDisguiseRollingEnabled: false,
                                   defaults: defaults)
        for speciesID in speciesIDs { await store.loadPokemonDetails(speciesID: speciesID) }
        return store
    }

    private func graduateStore(_ speciesID: Int, form: PokemonForm?) async throws -> CompanionStore {
        var state = CompanionState()
        state.dex = [try graduate(speciesID, form: form)]
        return try await store(state, loading: [speciesID])
    }

    private func detailView(_ store: CompanionStore, _ speciesID: Int) throws -> PokemonDetailView {
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == speciesID }, "#\(speciesID)")
        return PokemonDetailView(store: store, species: species, onBack: {})
    }

    private func height<V: View>(_ view: V) -> CGFloat {
        LayoutMeasure.size(view.frame(width: PopoverMetrics.contentWidth), width: PopoverMetrics.contentWidth).height
    }

    func testEveryVarietyWithBattleDataIsReachableFromTheFormCatalogOrAGender() {
        XCTAssertEqual(Set(Self.formCases.map(\.pokemonID)).union(GenderVariety.femalePokemonIDs.values),
                       Set(FormBattleData.byPokemonID.keys))
    }

    func testTheDexPageShowsTheGraduatesFormTypesStatsAndAbility() async throws {
        for formCase in Self.formCases {
            let label = "#\(formCase.speciesID) \(formCase.form.rawValue)"
            let store = try await graduateStore(formCase.speciesID, form: formCase.form)
            let details = try XCTUnwrap(try detailView(store, formCase.speciesID).details, label)
            XCTAssertEqual(details.types, formCase.data.types, label)
            XCTAssertEqual(details.baseStats, formCase.data.baseStats, label)
            XCTAssertEqual(details.abilities, formCase.data.abilities, label)
        }
    }

    func testTheDexPageHeaderAddsNoDefaultFormNoteForAFormWithBattleData() async throws {
        for formCase in Self.formCases {
            let label = "#\(formCase.speciesID) \(formCase.form.rawValue)"
            let defaultForm = PokemonForm.forms(speciesID: formCase.speciesID).first
            let shown = try await graduateStore(formCase.speciesID, form: formCase.form)
            let plain = try await graduateStore(formCase.speciesID, form: defaultForm)
            XCTAssertEqual(height(try detailView(shown, formCase.speciesID).identityText),
                           height(try detailView(plain, formCase.speciesID).identityText), accuracy: 0.5, label)
        }
    }

    func testTheDexPageSaysHeightWeightAndMovesAreTheDefaultFormsForAFormWithBattleData() async throws {
        let rapid = try await graduateStore(892, form: PokemonForm("rapid-strike"))
        let single = try await graduateStore(892, form: PokemonForm("single-strike"))
        let rapidView = try detailView(rapid, 892)
        let singleView = try detailView(single, 892)
        let rapidDetails = try XCTUnwrap(rapidView.details)
        let singleDetails = try XCTUnwrap(singleView.details)
        XCTAssertGreaterThanOrEqual(height(rapidView.speciesSection(rapidDetails))
                                    - height(singleView.speciesSection(singleDetails)), 8,
                                    "height and weight are still species 892's")
        XCTAssertGreaterThanOrEqual(height(rapidView.movesSection(rapidDetails))
                                    - height(singleView.movesSection(singleDetails)), 8,
                                    "the move list is still species 892's")
    }

    func testTheBoxPageShowsTheGraduatesFormTypes() async throws {
        for formCase in Self.formCases {
            let label = "#\(formCase.speciesID) \(formCase.form.rawValue)"
            let store = try await graduateStore(formCase.speciesID, form: formCase.form)
            let individual = try XCTUnwrap(store.boxIndividuals.first { $0.id == "graduate" }, label)
            XCTAssertEqual(store.pokemonDetails(speciesID: individual.speciesID, form: individual.entry.form,
                                                gender: individual.entry.profile?.gender)?.types,
                           formCase.data.types, label)
        }
    }

    func testTheBoxPageShowsAFemaleVarietysTypesStatsAndAbilitiesAndAMaleTheSpecies() async throws {
        for (speciesID, pokemonID) in GenderVariety.femalePokemonIDs.sorted(by: { $0.key < $1.key }) {
            let data = try XCTUnwrap(FormBattleData.byPokemonID[pokemonID], "#\(pokemonID)")
            for gender in [PokemonGender.female, .male] {
                let label = "#\(speciesID) \(gender)"
                var profile = PokemonProfile.generate(seed: UInt64(speciesID), instanceID: "graduate")
                profile.gender = gender
                let entry = DexEntry(id: "graduate", baseID: speciesID, finalID: speciesID, chainOrder: [speciesID],
                                     rarity: .rare, caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                                     profile: profile, names: [speciesID: try SpeciesFacts.names(speciesID)])
                var state = CompanionState()
                state.dex = [entry]
                let store = try await store(state, loading: [speciesID])
                let individual = try XCTUnwrap(store.boxIndividuals.first { $0.id == "graduate" }, label)
                let details = try XCTUnwrap(store.pokemonDetails(speciesID: individual.speciesID, form: individual.entry.form,
                                                                 gender: individual.entry.profile?.gender), label)
                let species = try XCTUnwrap(store.pokemonDetailsByID[speciesID], label)
                XCTAssertEqual(details.baseStats, gender == .female ? data.baseStats : species.baseStats, label)
                XCTAssertEqual(details.abilities, gender == .female ? data.abilities : species.abilities, label)
                let trainable = try XCTUnwrap(store.trainable(id: "graduate"), label)
                XCTAssertEqual(store.abilityOptions(of: trainable), details.abilities, label)
                let fighter = try XCTUnwrap(BattleEntry.candidates(in: store.state).first { $0.id == "graduate" }, label)
                XCTAssertEqual(fighter.member.pokemonID, gender == .female ? pokemonID : speciesID, label)
                let previewSpecies = BattleStatPreview.speciesID(of: fighter, in: store)
                XCTAssertEqual(BattleStatPreview.details(for: fighter, speciesID: previewSpecies, in: store)?.baseStats,
                               details.baseStats, label)
                XCTAssertEqual(BattleStatPreview.types(for: fighter, speciesID: previewSpecies, in: store),
                               details.types, label)
            }
        }
    }

    func testTheBattlePickerUploadsAndShowsTheGraduatesForm() async throws {
        for formCase in Self.formCases {
            let label = "#\(formCase.speciesID) \(formCase.form.rawValue)"
            let store = try await graduateStore(formCase.speciesID, form: formCase.form)
            let fighter = try XCTUnwrap(BattleEntry.candidates(in: store.state).first { $0.id == "graduate" }, label)
            XCTAssertEqual(fighter.member.pokemonID, formCase.pokemonID, label)
            let speciesID = BattleStatPreview.speciesID(of: fighter, in: store)
            XCTAssertEqual(BattleStatPreview.types(for: fighter, speciesID: speciesID, in: store), formCase.data.types, label)
            XCTAssertEqual(BattleStatPreview.details(for: fighter, speciesID: speciesID, in: store)?.baseStats,
                           formCase.data.baseStats, label)
        }
    }

    func testTheBoxTypeFilterUsesTheGraduatesFormTypes() async throws {
        let store = try await graduateStore(892, form: PokemonForm("rapid-strike"))
        XCTAssertEqual(store.filteredBoxIndividuals(types: [.water]).map(\.id), ["graduate"])
        XCTAssertEqual(store.filteredBoxIndividuals(types: [.dark]).map(\.id), [])
        let single = try await graduateStore(892, form: PokemonForm("single-strike"))
        XCTAssertEqual(single.filteredBoxIndividuals(types: [.dark]).map(\.id), ["graduate"])
    }

    func testAFriendCountsWithItsFormTypesForEvolution() async throws {
        var state = CompanionState()
        state.dex = [try graduate(892, form: PokemonForm("rapid-strike"), id: "friend")]
        state.friendEntryIDs = ["friend"]
        state.active = MonState(baseID: 674, pathIDs: [674], stageIndex: 0, usedAtStage: 0, rarity: .common,
                                totalForms: 2, profile: PokemonProfile.generate(seed: 674, instanceID: "pancham"))
        let store = try await store(state, loading: [892])
        let context = store.evolutionContext(for: try XCTUnwrap(store.state.active))
        XCTAssertEqual(context.friendTypes, ["fighting", "water"])
    }
}
