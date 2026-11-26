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

    private struct CatalogCase {
        let speciesID: Int
        let form: PokemonForm?
        var label: String { "#\(speciesID) \(form?.rawValue ?? "nil")" }
        var isDefault: Bool { PokemonForm.isDefault(form, speciesID: speciesID) }
        var data: FormBattleData? { FormBattleData.of(speciesID: speciesID, form: form, gender: nil) }
    }

    private static var catalogCases: [CatalogCase] {
        PokemonForm.catalog.keys.sorted().flatMap { speciesID in
            ([nil] + PokemonForm.forms(speciesID: speciesID)).map { CatalogCase(speciesID: speciesID, form: $0) }
        }
    }

    private static func lineBase(of speciesID: Int) -> Int {
        (1...speciesID).first { PokemonForm.formSpecies(baseID: $0).contains(speciesID) } ?? speciesID
    }

    private func assertComplete(_ details: PokemonDetails?, _ catalogCase: CatalogCase, _ screen: String,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let label = "\(catalogCase.label) \(screen)"
        guard let details else { return XCTFail("no details: \(label)", file: file, line: line) }
        XCTAssertFalse(details.types.isEmpty, label, file: file, line: line)
        XCTAssertEqual(Set(details.baseStats.keys), Set(PokemonStatCalculator.order), label, file: file, line: line)
        XCTAssertTrue(details.baseStats.values.allSatisfy { $0 > 0 }, label, file: file, line: line)
        XCTAssertFalse(details.abilities.isEmpty, label, file: file, line: line)
        let species = try SpeciesFacts.details(catalogCase.speciesID)
        XCTAssertEqual(details.types, catalogCase.data?.types ?? species.types, label, file: file, line: line)
        XCTAssertEqual(details.baseStats, catalogCase.data?.baseStats ?? species.baseStats, label, file: file, line: line)
    }

    func testEveryCatalogFormShowsTypesStatsAndAbilityAsAGraduateOnEveryScreen() async throws {
        for catalogCase in Self.catalogCases {
            let speciesID = catalogCase.speciesID
            let store = try await graduateStore(speciesID, form: catalogCase.form)
            let page = try detailView(store, speciesID)
            try assertComplete(page.details, catalogCase, "dex page")
            let individual = try XCTUnwrap(store.boxIndividuals.first { $0.id == "graduate" }, catalogCase.label)
            let profile = try XCTUnwrap(individual.entry.profile, catalogCase.label)
            try assertComplete(store.pokemonDetails(speciesID: individual.speciesID, form: individual.entry.form,
                                                    gender: profile.gender), catalogCase, "box")
            XCTAssertNotNil(FormBattleData.abilityName(speciesID: speciesID, form: individual.entry.form,
                                                       profile: profile), catalogCase.label)
            XCTAssertFalse(store.types(speciesID: speciesID, form: individual.entry.form, gender: profile.gender).isEmpty,
                           catalogCase.label)
            let fighter = try XCTUnwrap(BattleEntry.candidates(in: store.state).first { $0.id == "graduate" },
                                        catalogCase.label)
            XCTAssertEqual(fighter.member.pokemonID,
                           PokemonForm.varietyID(speciesID: speciesID, form: catalogCase.form, gender: nil) ?? speciesID,
                           catalogCase.label)
            let previewSpecies = BattleStatPreview.speciesID(of: fighter, in: store)
            try assertComplete(BattleStatPreview.details(for: fighter, speciesID: previewSpecies, in: store),
                               catalogCase, "battle preview")
            XCTAssertEqual(BattleStatPreview.types(for: fighter, speciesID: previewSpecies, in: store)?.isEmpty, false,
                           catalogCase.label)
        }
    }

    func testEveryCatalogFormShowsTypesStatsAndAbilityWhileRaised() async throws {
        for catalogCase in Self.catalogCases {
            let speciesID = catalogCase.speciesID
            let baseID = Self.lineBase(of: speciesID)
            let path = baseID == speciesID ? [speciesID] : [baseID, speciesID]
            var state = CompanionState()
            state.active = MonState(baseID: baseID, pathIDs: path, stageIndex: path.count - 1, usedAtStage: 0,
                                    rarity: .legendary, totalForms: path.count,
                                    profile: PokemonProfile.generate(seed: UInt64(speciesID), instanceID: "raised"),
                                    form: catalogCase.form)
            let store = try await store(state, loading: [speciesID])
            XCTAssertEqual(store.currentSpeciesID, speciesID, catalogCase.label)
            try assertComplete(store.pokemonDetails(speciesID: speciesID, form: store.currentForm,
                                                    gender: store.currentGender), catalogCase, "raised")
        }
    }

    func testTheDexPageNotesTheDefaultFormsDataOnlyForAFormWithoutBattleData() async throws {
        for catalogCase in Self.catalogCases where catalogCase.speciesID != PokemonForm.unownSpeciesID {
            let defaultForm = PokemonForm.forms(speciesID: catalogCase.speciesID).first
            let shown = try await graduateStore(catalogCase.speciesID, form: catalogCase.form)
            let plain = try await graduateStore(catalogCase.speciesID, form: defaultForm)
            let difference = height(try detailView(shown, catalogCase.speciesID).identityText)
                - height(try detailView(plain, catalogCase.speciesID).identityText)
            if catalogCase.isDefault || catalogCase.data != nil {
                XCTAssertEqual(difference, 0, accuracy: 0.5, catalogCase.label)
            } else {
                XCTAssertGreaterThanOrEqual(difference, 8, catalogCase.label)
            }
        }
    }

    func testADefaultFormDrawsThePlainSpeciesArt() {
        for catalogCase in Self.catalogCases {
            let speciesID = catalogCase.speciesID
            for animated in [false, true] {
                let file = SpriteStore.spriteURL(speciesID: speciesID, animated: animated, shiny: false,
                                                 form: catalogCase.form).lastPathComponent
                let plain = "\(speciesID).\(animated ? "gif" : "png")"
                if catalogCase.isDefault {
                    XCTAssertEqual(file, plain, catalogCase.label)
                } else {
                    XCTAssertNotEqual(file, plain, catalogCase.label)
                }
            }
        }
    }

    private func graduate(_ speciesID: Int, form: PokemonForm?, id: String = "graduate") throws -> DexEntry {
        let baseID = Self.lineBase(of: speciesID)
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
