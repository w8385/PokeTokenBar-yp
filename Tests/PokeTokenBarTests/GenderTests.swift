import XCTest
@testable import PokeTokenBar

private let now = Date(timeIntervalSince1970: 1_700_000_000)

private func evoNode(_ id: Int, _ children: [EvoNode] = [], gender: PokemonGender? = nil) -> EvoNode {
    EvoNode(speciesID: id, children: children, requiredGender: gender)
}

private func genderLine(base: Int, tree: EvoNode, genderRate: Int?) -> EvoLine {
    func ids(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(ids) }
    let names = Dictionary(uniqueKeysWithValues: ids(tree).map { ($0, ["en": "P\($0)"]) })
    return EvoLine(baseID: base, tree: tree, rarity: .common, names: names, genderRate: genderRate)
}

private let combee = genderLine(base: 415, tree: evoNode(415, [evoNode(416, gender: .female)]), genderRate: 1)
private let ralts = genderLine(
    base: 280, tree: evoNode(280, [evoNode(281, [evoNode(282), evoNode(475, gender: .male)])]), genderRate: 4)
private let burmy = genderLine(
    base: 412, tree: evoNode(412, [evoNode(413, gender: .female), evoNode(414, gender: .male)]), genderRate: 4)

final class GenderRollTests: XCTestCase {
    func testRateZeroIsAlwaysMale() {
        for seed in UInt64(0)..<300 { XCTAssertEqual(PokemonGender.roll(seed: seed, genderRate: 0), .male) }
    }

    func testRateEightIsAlwaysFemale() {
        for seed in UInt64(0)..<300 { XCTAssertEqual(PokemonGender.roll(seed: seed, genderRate: 8), .female) }
    }

    func testRateMinusOneIsGenderless() {
        for seed in UInt64(0)..<300 { XCTAssertEqual(PokemonGender.roll(seed: seed, genderRate: -1), .genderless) }
    }

    func testMixedRateRollsBothAndIsStablePerSeed() {
        let rolls = (UInt64(0)..<300).map { PokemonGender.roll(seed: $0, genderRate: 4) }
        XCTAssertTrue(rolls.contains(.male))
        XCTAssertTrue(rolls.contains(.female))
        XCTAssertEqual(rolls, (UInt64(0)..<300).map { PokemonGender.roll(seed: $0, genderRate: 4) })
    }

    func testOldSaveProfileGetsTheSeedsGenderAndKeepsIt() {
        var profile = PokemonProfile.generate(seed: 42)
        profile.gender = nil
        profile.assignGender(genderRate: 4)
        let first = profile.gender
        XCTAssertEqual(first, PokemonGender.roll(seed: profile.seed, genderRate: 4))
        profile.assignGender(genderRate: 0)
        XCTAssertEqual(profile.gender, first, "a rolled gender is never rerolled")
    }

    func testGlyphs() {
        XCTAssertEqual(PokemonGender.male.symbol, "♂")
        XCTAssertEqual(PokemonGender.female.symbol, "♀")
        XCTAssertNil(PokemonGender.genderless.symbol)
    }
}

final class GenderEvolutionDataTests: XCTestCase {
    private func details(_ genders: [Int?]) -> [EvolutionDetailDTO] {
        let json = "[" + genders.map { $0.map { #"{"gender":\#($0)}"# } ?? #"{"gender":null}"# }.joined(separator: ",") + "]"
        return try! JSONDecoder().decode([EvolutionDetailDTO].self, from: Data(json.utf8))
    }

    func testSingleGenderRestrictsTheStep() {
        XCTAssertEqual(PokeAPIClient.requiredGender(of: details([1])), .female)
        XCTAssertEqual(PokeAPIClient.requiredGender(of: details([2])), .male)
        XCTAssertEqual(PokeAPIClient.requiredGender(of: details([1, 1])), .female)
    }

    func testMixedOrMissingGenderStaysOpen() {
        XCTAssertNil(PokeAPIClient.requiredGender(of: details([1, 2])), "Meowstic takes either")
        XCTAssertNil(PokeAPIClient.requiredGender(of: details([2, nil])))
        XCTAssertNil(PokeAPIClient.requiredGender(of: details([nil])))
        XCTAssertNil(PokeAPIClient.requiredGender(of: []))
    }

    func testChainLinkDecodesEvolutionGender() throws {
        let json = """
        {"species":{"name":"kirlia","url":"https://pokeapi.co/api/v2/pokemon-species/281/"},
         "evolves_to":[{"species":{"name":"gallade","url":"https://pokeapi.co/api/v2/pokemon-species/475/"},
                        "evolves_to":[],"evolution_details":[{"gender":2,"item":{"name":"dawn-stone"}}]}],
         "evolution_details":[{"gender":null}]}
        """
        let link = try JSONDecoder().decode(ChainLink.self, from: Data(json.utf8))
        XCTAssertEqual(PokeAPIClient.requiredGender(of: link.evolves_to[0].evolution_details ?? []), .male)
        XCTAssertNil(PokeAPIClient.requiredGender(of: link.evolution_details ?? []))
    }

    func testChildrenFilterByGenderAndUnknownGenderFiltersNothing() {
        let kirlia = evoNode(281, [evoNode(282), evoNode(475, gender: .male)])
        XCTAssertEqual(kirlia.children(for: .female).map(\.speciesID), [282])
        XCTAssertEqual(kirlia.children(for: .male).map(\.speciesID), [282, 475])
        XCTAssertEqual(kirlia.children(for: nil).map(\.speciesID), [282, 475])
        XCTAssertEqual(kirlia.children(for: .genderless).map(\.speciesID), [282])
        XCTAssertEqual(kirlia.finalIDs(for: .female), [282])
    }

    func testSupportedSpeciesFilterKeepsTheRestriction() throws {
        let line = genderLine(base: 361, tree: evoNode(361, [evoNode(362), evoNode(478, gender: .female)]), genderRate: 4)
        XCTAssertEqual(line.tree.children.map(\.requiredGender), [nil, .female])
    }
}

@MainActor
final class FemaleSpriteTests: XCTestCase {
    func testSpriteSetsFollowTheSpriteRepo() {
        XCTAssertTrue(PokemonAssets.hasFemaleSprite(speciesID: 592, animated: true))
        XCTAssertTrue(PokemonAssets.hasFemaleSprite(speciesID: 592, animated: false))
        XCTAssertFalse(PokemonAssets.hasFemaleSprite(speciesID: 133, animated: true), "Eevee: static only")
        XCTAssertTrue(PokemonAssets.hasFemaleSprite(speciesID: 133, animated: false))
        XCTAssertTrue(PokemonAssets.hasFemaleSprite(speciesID: 902, animated: true), "animated only")
        XCTAssertFalse(PokemonAssets.hasFemaleSprite(speciesID: 902, animated: false))
        XCTAssertFalse(PokemonAssets.hasFemaleSprite(speciesID: 1, animated: true))
    }

    func testFemaleWithAFemaleSpriteResolvesItAndOthersShareTheDefault() {
        let female = SpriteStore.spriteURL(speciesID: 592, animated: true, shiny: false, female: true)
        XCTAssertTrue(female.absoluteString.hasSuffix("black-white/animated/female/592.gif"), female.absoluteString)
        let showdown = SpriteStore.spriteURL(speciesID: 902, animated: true, shiny: false, female: true)
        XCTAssertTrue(showdown.absoluteString.hasSuffix("other/showdown/female/902.gif"), showdown.absoluteString)
        let shiny = SpriteStore.spriteURL(speciesID: 592, animated: false, shiny: true, female: true)
        XCTAssertTrue(shiny.absoluteString.hasSuffix("/shiny/female/592.png"), shiny.absoluteString)
        let male = SpriteStore.spriteURL(speciesID: 592, animated: true, shiny: false)
        XCTAssertTrue(male.absoluteString.hasSuffix("black-white/animated/592.gif"))
        let noFemaleSet = SpriteStore.spriteURL(speciesID: 1, animated: true, shiny: false, female: true)
        XCTAssertEqual(noFemaleSet, SpriteStore.spriteURL(speciesID: 1, animated: true, shiny: false))
    }

    func testCacheKeySeparatesFemaleOnlyWhereTheSpriteExists() {
        XCTAssertNotEqual(SpriteStore.cacheKey(speciesID: 592, animated: true, shiny: false, female: true),
                          SpriteStore.cacheKey(speciesID: 592, animated: true, shiny: false))
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 1, animated: true, shiny: false, female: true),
                       SpriteStore.cacheKey(speciesID: 1, animated: true, shiny: false))
        XCTAssertNotEqual(SpriteStore.cacheKey(speciesID: 133, animated: false, shiny: false, female: true),
                          SpriteStore.cacheKey(speciesID: 133, animated: false, shiny: false))
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 133, animated: true, shiny: false, female: true),
                       SpriteStore.cacheKey(speciesID: 133, animated: true, shiny: false))
    }

    func testFemaleIsPartOfEverySpriteIdentity() {
        XCTAssertTrue(SpriteView.needsReload(loadedID: 592, loadedShiny: false, id: 592, shiny: false,
                                             loadedFemale: false, female: true))
        XCTAssertFalse(SpriteView.needsReload(loadedID: 592, loadedShiny: false, id: 592, shiny: false,
                                              loadedFemale: true, female: true))
        XCTAssertNotEqual(SpriteView.frameTaskID(speciesID: 592, shiny: false, floor: 0.4),
                          SpriteView.frameTaskID(speciesID: 592, shiny: false, floor: 0.4, female: true))
        XCTAssertNotEqual(AppDelegate.menuSpriteKey(id: 592, shiny: false, floor: 0.4),
                          AppDelegate.menuSpriteKey(id: 592, shiny: false, floor: 0.4, female: true))
    }
}

@MainActor
final class GenderStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("poke-gender-\(UUID().uuidString).json")
    }

    private func store(_ line: EvoLine, seed: UInt64, url: URL? = nil) -> CompanionStore {
        CompanionStore(provider: StubProvider(value: line), clock: { now },
                       fileURL: url ?? tempURL(), rng: SeededRNG(seed: seed))
    }

    private func withRate(_ line: EvoLine, _ rate: Int?) -> EvoLine {
        EvoLine(baseID: line.baseID, tree: line.tree, rarity: line.rarity, names: line.names, genderRate: rate)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func finish(_ s: CompanionStore) {
        guard let active = s.state.active else { return }
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: active.rarity, totalForms: active.totalForms,
                                                   stageIndex: active.stageIndex))
    }

    func testHatchRollsGenderFromTheSpeciesRate() async {
        for (rate, expected) in [(0, PokemonGender.male), (8, .female), (-1, .genderless)] {
            let s = store(withRate(combee, rate), seed: 3)
            await s.hatch(baseID: 415)
            XCTAssertEqual(s.state.active?.profile?.gender, expected, "rate \(rate)")
        }
    }

    func testMaleCombeeNeverEvolves() async {
        for seed in UInt64(1)...25 {
            let s = store(withRate(combee, 0), seed: seed)
            await s.hatch(baseID: 415)
            XCTAssertEqual(s.state.active?.plannedPathIDs, [415], "seed \(seed)")
            XCTAssertEqual(s.state.active?.totalForms, 1)
            finish(s)
            XCTAssertEqual(s.state.dex.last?.finalID, 415, "seed \(seed): graduates as Combee")
        }
    }

    func testFemaleCombeeEvolvesToVespiquen() async {
        let s = store(withRate(combee, 8), seed: 5)
        await s.hatch(baseID: 415)
        XCTAssertEqual(s.state.active?.plannedPathIDs, [415, 416])
        finish(s)
        XCTAssertEqual(s.currentSpeciesID, 416)
    }

    func testFemaleKirliaNeverBecomesGalladeAndMaleCanStillChoose() async {
        var maleFinals: Set<Int> = []
        for seed in UInt64(1)...40 {
            let female = store(withRate(ralts, 8), seed: seed)
            await female.hatch(baseID: 280)
            XCTAssertEqual(female.state.active?.plannedPathIDs, [280, 281, 282], "seed \(seed)")

            let male = store(withRate(ralts, 0), seed: seed)
            await male.hatch(baseID: 280)
            maleFinals.insert(male.state.active?.plannedPathIDs.last ?? 0)
        }
        XCTAssertEqual(maleFinals, [282, 475])
    }

    func testBurmyFollowsGender() async {
        let female = store(withRate(burmy, 8), seed: 2)
        await female.hatch(baseID: 412)
        XCTAssertEqual(female.state.active?.plannedPathIDs, [412, 413])
        let male = store(withRate(burmy, 0), seed: 2)
        await male.hatch(baseID: 412)
        XCTAssertEqual(male.state.active?.plannedPathIDs, [412, 414])
    }

    func testOldSaveGetsAStableGenderAndMaleCombeeLeavesItsFemaleOnlyPlan() async throws {
        let url = tempURL()
        let first = store(withRate(combee, nil), seed: 9, url: url)
        await first.hatch(baseID: 415)
        XCTAssertNil(first.state.active?.profile?.gender, "no rate known: like a save from before genders")
        XCTAssertEqual(first.state.active?.plannedPathIDs, [415, 416])

        func reload() async -> CompanionStore {
            let s = CompanionStore(provider: StubProvider(value: withRate(combee, 0)), clock: { now },
                                   fileURL: url, rng: SeededRNG(seed: 1))
            s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                     burnTier: .idle, limitWarning: false, hasUsageData: true)
            let loaded = await waitUntil { s.currentLine != nil }
            XCTAssertTrue(loaded)
            return s
        }
        let second = await reload()
        XCTAssertEqual(second.state.active?.profile?.gender, .male)
        XCTAssertEqual(second.state.active?.plannedPathIDs, [415])
        let third = await reload()
        XCTAssertEqual(third.state.active?.profile?.gender, .male, "stable across launches")

        finish(second)
        XCTAssertEqual(second.state.dex.last?.finalID, 415)
    }

    func testDawnStoneOnlyEvolvesTheGenderTheBranchNames() async throws {
        let kirlia = EvoNode(speciesID: 281, children: [
            EvoNode(speciesID: 282, children: [], methods: [EvoMethod(trigger: "level-up")]),
            EvoNode(speciesID: 475, children: [], methods: [EvoMethod(trigger: "use-item", item: "dawn-stone")],
                    requiredGender: .male),
        ])
        for (rate, expected, species) in [(8, CompanionStore.StoneUseResult.wrongStone, 281),
                                          (0, .evolved, 475)] {
            var saved = CompanionState()
            saved.installBaselineSet = true
            saved.inventory[ItemKind.dawnStone.rawValue] = 1
            let url = tempURL()
            try JSONEncoder().encode(saved).write(to: url)
            let s = CompanionStore(provider: StubProvider(value: genderLine(base: 281, tree: kirlia, genderRate: rate)),
                                   clock: { now }, fileURL: url, rng: SeededRNG(seed: 4))
            await s.hatch(baseID: 281)
            XCTAssertEqual(s.useEvolutionStone(.dawnStone), expected, "rate \(rate)")
            XCTAssertEqual(s.currentSpeciesID, species, "rate \(rate)")
        }
    }

    func testEvolutionsAlreadyTakenSurviveGenderRules() async throws {
        let url = tempURL()
        let first = store(withRate(combee, nil), seed: 5, url: url)
        await first.hatch(baseID: 415)
        XCTAssertEqual(first.state.active?.plannedPathIDs, [415, 416])
        finish(first)
        XCTAssertEqual(first.state.active?.pathIDs, [415, 416])

        let s = CompanionStore(provider: StubProvider(value: withRate(combee, 0)), clock: { now },
                               fileURL: url, rng: SeededRNG(seed: 1))
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded)
        XCTAssertEqual(s.state.active?.pathIDs, [415, 416], "a taken evolution is never trimmed")
    }
}
