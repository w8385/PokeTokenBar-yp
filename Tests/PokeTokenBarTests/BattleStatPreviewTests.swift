import XCTest
@testable import PokeTokenBar

private struct StatPreviewProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try SpeciesFacts.details(speciesID)
    }
}

@MainActor
final class BattleStatPreviewTests: XCTestCase {
    private let ivs = PokemonIVs(hp: 31, attack: 20, defense: 7, specialAttack: 13, specialDefense: 0, speed: 25)

    func testRowWithoutAMegaStoneShowsAStatLine() async throws {
        let lines = try await storeLines(species: 149, heldItem: nil)

        XCTAssertEqual(lines.map(\.form), [.normal])
        XCTAssertEqual(lines.first?.stats.map(\.name), PokemonStatCalculator.order)
    }

    func testMegaStoneRowShowsNormalAndMegaLinesAtBattleLevel() async throws {
        let stone = try XCTUnwrap(MegaStone.stone(slug: "charizardite-x"))
        let lines = try await storeLines(species: 6, heldItem: stone.inventoryKey)

        XCTAssertEqual(lines.map(\.form), [.normal, .mega])
        let mega = try XCTUnwrap(lines.last)
        XCTAssertNotEqual(mega.stats.map(\.value), stone.stats)
        XCTAssertEqual(mega.stats.map(\.base), stone.stats)
    }

    func testNumbersMatchTheBotFormulaAtTheCappedLevel() throws {
        let member = PartyMember(pokemonID: 149, level: 62, shiny: false, ivs: ivs, nature: PokemonNature.adamant.rawValue)
        let line = try XCTUnwrap(BattleStatPreview.lines(member: member, details: try SpeciesFacts.details(149),
                                                         heldItem: nil, mega: nil, tera: nil).first)

        let base = try SpeciesFacts.fact(149).stats
        let ivList = [31, 20, 7, 13, 0, 25]
        let expected = botStats(base: base, ivs: ivList, level: 50, up: 1, down: 3)
        XCTAssertEqual(expected, [166, 163, 103, 99, 105, 97])
        XCTAssertEqual(line.stats.map(\.value), expected)
    }

    func testNatureMarksLandOnTheRaisedAndLoweredStats() throws {
        let details = try SpeciesFacts.details(149)
        func marks(_ nature: PokemonNature) throws -> [BattleStatLine.Mark?] {
            let member = PartyMember(pokemonID: 149, level: 40, shiny: false, ivs: ivs, nature: nature.rawValue)
            let line = try XCTUnwrap(BattleStatPreview.lines(member: member, details: details, heldItem: nil,
                                                             mega: nil, tera: nil).first)
            return line.stats.map { line.mark(of: $0.name) }
        }

        XCTAssertEqual(try marks(.adamant), [nil, .raised, nil, .lowered, nil, nil])
        XCTAssertEqual(try marks(.modest), [nil, .lowered, nil, .raised, nil, nil])
        XCTAssertEqual(try marks(.careful), [nil, nil, nil, .lowered, .raised, nil])
        XCTAssertEqual(try marks(.hardy), [nil, nil, nil, nil, nil, nil])
        XCTAssertEqual(L(.ko).battleStatName("special-attack"), "특공")
        XCTAssertEqual(L(.en).battleStatName("special-defense"), "SpD")
        XCTAssertEqual(L(.en).battleStatName("hp"), "HP")
    }

    func testTherianLandorusRowsShowTherianTypesAndStats() async throws {
        let therian = PokemonForm("therian")
        let expected = botStats(base: [89, 145, 90, 105, 80, 91], ivs: [31, 20, 7, 13, 0, 25], level: 50, up: 1, down: 3)
        XCTAssertEqual(expected, [164, 176, 98, 104, 85, 108])

        var entry = try landorusEntry(form: therian)
        entry.id = "boxed"
        var raisedProfile = PokemonProfile.generate(seed: 645, instanceID: "raised")
        raisedProfile.level = 62
        raisedProfile.ivs = ivs
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = [entry]
        state.active = MonState(baseID: 645, pathIDs: [645], stageIndex: 0, usedAtStage: 0, rarity: .rare,
                                totalForms: 1, nature: .adamant, profile: raisedProfile, form: therian)
        let store = try await store(state: state, species: 645)

        for id in ["boxed", "raised"] {
            let fighter = try XCTUnwrap(BattleEntry.candidates(in: store.state).first { $0.id == id })
            XCTAssertEqual(fighter.member.pokemonID, 10021, id)
            let speciesID = BattleStatPreview.speciesID(of: fighter, in: store)
            XCTAssertEqual(speciesID, 645, id)
            XCTAssertEqual(BattleStatPreview.types(for: fighter, speciesID: speciesID, in: store), ["ground", "flying"], id)
            let details = BattleStatPreview.details(for: fighter, speciesID: speciesID, in: store)
            XCTAssertEqual(details?.baseStats["attack"], 145, id)
            let lines = BattleStatPreview.lines(for: fighter, speciesID: speciesID, in: store)
            XCTAssertEqual(lines.map(\.form), [.normal], id)
            XCTAssertEqual(lines.first?.stats.map(\.value), expected, id)
        }
    }

    func testIceRiderCalyrexRowTakesTheFormTypes() async throws {
        var entry = DexEntry(baseID: 898, finalID: 898, chainOrder: [898], rarity: .rare,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                             profile: PokemonProfile.generate(seed: 898, instanceID: "rider"),
                             names: [898: try SpeciesFacts.names(898)])
        entry.form = PokemonForm("ice")
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = [entry]
        let store = try await store(state: state, species: 898)
        let fighter = try XCTUnwrap(BattleEntry.candidates(in: store.state).first)

        XCTAssertEqual(fighter.member.pokemonID, 10193)
        let speciesID = BattleStatPreview.speciesID(of: fighter, in: store)
        XCTAssertEqual(BattleStatPreview.types(for: fighter, speciesID: speciesID, in: store), ["psychic", "ice"])
    }

    func testVarietyWithoutBattleDataShowsNoLine() async throws {
        var entry = DexEntry(baseID: 492, finalID: 492, chainOrder: [492], rarity: .rare,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                             profile: PokemonProfile.generate(seed: 492, instanceID: "sky"),
                             names: [492: try SpeciesFacts.names(492)])
        entry.form = PokemonForm("sky")
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = [entry]
        let store = try await store(state: state, species: 492)
        let fighter = try XCTUnwrap(BattleEntry.candidates(in: store.state).first)

        XCTAssertEqual(fighter.member.pokemonID, 10006)
        XCTAssertEqual(BattleStatPreview.lines(for: fighter, speciesID: 492, in: store), [])
    }

    func testStellarCrystalRowShowsOnlyTheStellarLine() async throws {
        let lines = try await storeLines(species: TeraForm.terapagos, heldItem: ItemKind.stellarCrystal.rawValue)

        XCTAssertEqual(lines.map(\.form), [.stellar])
    }

    func testRowWithAFormItemGetsNoNormalLine() {
        XCTAssertFalse(BattleStatPreview.startsInOwnForm(speciesID: 487, heldItem: .griseousCore))
        XCTAssertFalse(BattleStatPreview.startsInOwnForm(speciesID: 888, heldItem: .rustedSword))
        XCTAssertTrue(BattleStatPreview.startsInOwnForm(speciesID: 487, heldItem: .rustedSword))
        XCTAssertTrue(BattleStatPreview.startsInOwnForm(speciesID: 149, heldItem: nil))
    }

    func testMemberWithoutIVsShowsNoLine() throws {
        let member = PartyMember(pokemonID: 149, level: 40, shiny: false, ivs: nil)

        XCTAssertEqual(BattleStatPreview.lines(member: member, details: try SpeciesFacts.details(149), heldItem: nil,
                                               mega: nil, tera: nil), [])
    }

    /// `_Fighter.enter` and `_other_stat` in bot/ypoke/battle.py, integer math as written there.
    private func botStats(base: [Int], ivs: [Int], level: Int, up: Int, down: Int) -> [Int] {
        var stats = (0..<6).map { index in
            index == 0 ? (2 * base[0] + ivs[0]) * level / 100 + level + 10 : (2 * base[index] + ivs[index]) * level / 100 + 5
        }
        stats[up] = stats[up] * 110 / 100
        stats[down] = stats[down] * 90 / 100
        return stats
    }

    private func landorusEntry(form: PokemonForm) throws -> DexEntry {
        var profile = PokemonProfile.generate(seed: 645, instanceID: "boxed")
        profile.level = 62
        profile.ivs = ivs
        var entry = DexEntry(baseID: 645, finalID: 645, chainOrder: [645], rarity: .rare,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile,
                             names: [645: try SpeciesFacts.names(645)])
        entry.nature = .adamant
        entry.form = form
        return entry
    }

    private func store(state: CompanionState, species: Int) async throws -> CompanionStore {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("stat-preview-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: StatPreviewProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: species)
        return store
    }

    private func storeLines(species: Int, heldItem: String?) async throws -> [BattleStatLine] {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("stat-preview-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var profile = PokemonProfile.generate(seed: UInt64(species), instanceID: "fighter")
        profile.level = 62
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .rare,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000), profile: profile,
                             names: [species: try SpeciesFacts.names(species)])
        entry.id = "fighter"
        entry.nature = .adamant
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = [entry]
        if let heldItem { state.heldItems = ["fighter": heldItem] }
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: StatPreviewProvider(), fileURL: file)
        await store.loadPokemonDetails(speciesID: species)
        let fighter = try XCTUnwrap(BattleEntry.candidates(in: store.state).first { $0.id == "fighter" })
        return BattleStatPreview.lines(for: fighter, speciesID: species, in: store)
    }
}
