import XCTest
@testable import PokeTokenBar

private func entry(_ id: Int, _ ko: String, _ en: String, rarityCapture: Int = 255, legendary: Bool = false,
                   from parent: Int? = nil, types: [String] = ["normal"]) -> SpeciesIndexEntry {
    SpeciesIndexEntry(id: id, names: ["ko": ko, "en": en], types: types, captureRate: rarityCapture,
                      isLegendary: legendary, isMythical: false, evolvesFromID: parent)
}

private let fixtureEntries = [
    entry(16, "구구", "Pidgey"),
    entry(25, "피카츄", "Pikachu", from: 172),
    entry(26, "라이츄", "Raichu", from: 25),
    entry(132, "메타몽", "Ditto", rarityCapture: 35),
    entry(133, "이브이", "Eevee", rarityCapture: 45),
    entry(134, "샤미드", "Vaporeon", rarityCapture: 45, from: 133),
    entry(150, "뮤츠", "Mewtwo", rarityCapture: 3, legendary: true),
    entry(172, "피츄", "Pichu", rarityCapture: 190),
    entry(900, "고아", "Orphan", from: 5000),
]

private struct UnownedIndexProvider: PokeProviding, SpeciesIndexProviding {
    var entries: [SpeciesIndexEntry]? = fixtureEntries
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func speciesIndex() async throws -> SpeciesIndex {
        guard let entries else { throw URLError(.notConnectedToInternet) }
        return SpeciesIndex(entries: entries)
    }
}

@MainActor
final class DexUnownedSearchTests: XCTestCase {
    private func store(provider: UnownedIndexProvider = UnownedIndexProvider()) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dex-unowned-\(UUID().uuidString).json")
        var state = CompanionState()
        state.language = .ko
        state.dex = [DexEntry(id: "e1", baseID: 25, finalID: 26, chainOrder: [25, 26], rarity: .rare,
                              caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false,
                              names: [25: ["ko": "피카츄", "en": "Pikachu"], 26: ["ko": "라이츄", "en": "Raichu"]])]
        try? JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: provider, fileURL: url, rng: SeededRNG(seed: 1))
    }

    func testQueryFindsUnownedSpeciesByKoreanName() async {
        let s = store()
        await s.loadSpeciesIndexIfNeeded()
        let found = s.filteredDexSpecies(query: "이브이")
        XCTAssertEqual(found.map(\.id), [133])
        XCTAssertEqual(found.first?.isOwned, false)
        XCTAssertEqual(found.first?.name, "이브이")
    }

    func testQueryFindsUnownedSpeciesByNumberAndEnglishName() async {
        let s = store()
        await s.loadSpeciesIndexIfNeeded()
        XCTAssertEqual(s.filteredDexSpecies(query: "133").map(\.id), [133])
        XCTAssertEqual(s.filteredDexSpecies(query: "#150").map(\.id), [150])
        XCTAssertEqual(s.filteredDexSpecies(query: "vapor").map(\.id), [134])
    }

    func testEmptyQueryStaysOwnedOnly() async {
        let s = store()
        await s.loadSpeciesIndexIfNeeded()
        XCTAssertEqual(s.filteredDexSpecies().map(\.id), [25, 26])
        XCTAssertEqual(s.filteredDexSpecies(query: "   ").map(\.id), [25, 26])
    }

    func testSearchStaysOwnedOnlyBeforeIndexLoadsAndWhenOffline() async {
        let s = store(provider: UnownedIndexProvider(entries: nil))
        XCTAssertEqual(s.filteredDexSpecies(query: "이브이").map(\.id), [])
        XCTAssertEqual(s.filteredDexSpecies(query: "피카츄").map(\.id), [25])
        await s.loadSpeciesIndexIfNeeded()
        XCTAssertEqual(s.speciesIndexStatus, .unavailable)
        XCTAssertEqual(s.filteredDexSpecies(query: "이브이").map(\.id), [])
    }

    func testRarityFilterAppliesToUnownedResults() async {
        let s = store()
        await s.loadSpeciesIndexIfNeeded()
        XCTAssertEqual(Set(s.filteredDexSpecies(query: "e").map(\.id)), [16, 133, 134, 150])
        XCTAssertEqual(s.filteredDexSpecies(query: "e", rarity: .rare).map(\.id), [133, 134])
        XCTAssertEqual(s.filteredDexSpecies(query: "e", rarity: .common).map(\.id), [16])
        XCTAssertEqual(s.filteredDexSpecies(query: "e", rarity: .legendary).map(\.id), [150])
    }

    func testRegionAndShinyFiltersApplyToUnownedResults() async {
        let s = store()
        await s.loadSpeciesIndexIfNeeded()
        XCTAssertEqual(s.filteredDexSpecies(query: "e", region: .kanto).map(\.id), [16, 133, 134, 150])
        XCTAssertEqual(s.filteredDexSpecies(query: "e", shinyOnly: true).map(\.id), [])
    }

    func testOwnedAndUnownedWithSameIDDoNotDuplicate() async {
        let s = store()
        await s.loadSpeciesIndexIfNeeded()
        let found = s.filteredDexSpecies(query: "25")
        XCTAssertEqual(found.map(\.id), [25])
        XCTAssertEqual(found.first?.isOwned, true)
        XCTAssertEqual(s.unownedDexSpecies.map(\.id).filter { [25, 26].contains($0) }, [])
    }

    func testResultsFollowTheNormalSortOrder() async {
        let s = store()
        await s.loadSpeciesIndexIfNeeded()
        XCTAssertEqual(s.filteredDexSpecies(query: "e", sort: .numberDesc).map(\.id), [150, 134, 133, 16])
        XCTAssertEqual(s.filteredDexSpecies(query: "e", sort: .rarityDesc).map(\.id).first, 150)
    }

    func testIndexLoadsOnlyWhenAsked() {
        XCTAssertEqual(store().speciesIndexStatus, .idle)
    }
}

final class SpeciesIndexTests: XCTestCase {
    private let index = SpeciesIndex(entries: fixtureEntries)

    func testLineTakesTheRarityOfItsBase() {
        XCTAssertEqual(index.rarity(of: 26), .common, "Pichu is 190 → common, and Raichu follows it")
        XCTAssertEqual(index.rarity(of: 134), .rare)
        XCTAssertEqual(index.rarity(of: 150), .legendary)
    }

    func testAcquisitionByPosition() {
        XCTAssertEqual(index.acquisition(of: 172), .hatch(.common))
        XCTAssertEqual(index.acquisition(of: 133), .hatch(.rare))
        XCTAssertEqual(index.acquisition(of: 26), .evolve(fromID: 25))
        XCTAssertEqual(index.acquisition(of: 132), .ditto)
    }

    func testLineLeavingTheIndexIsUnavailable() {
        XCTAssertEqual(index.acquisition(of: 900), .unavailable)
        XCTAssertNil(index.rarity(of: 900))
        XCTAssertEqual(index.acquisition(of: 777), .unavailable)
    }

    func testEvolutionLineRunsFromBaseThroughSpeciesToItsEvolutions() {
        XCTAssertEqual(index.lineItems(of: 25), [.species(172), .species(25), .species(26)])
        XCTAssertEqual(index.lineItems(of: 172), [.species(172), .species(25), .species(26)])
        XCTAssertEqual(index.lineItems(of: 133), [.species(133), .species(134)])
        XCTAssertEqual(index.lineItems(of: 16), [.species(16)])
        XCTAssertEqual(index.lineItems(of: 777), [])
    }

    func testBranchingBaseEndsTheLineWithAMysteryMarker() {
        let branching = SpeciesIndex(entries: [
            entry(133, "이브이", "Eevee"),
            entry(134, "샤미드", "Vaporeon", from: 133),
            entry(135, "쥬피썬더", "Jolteon", from: 133),
        ])
        XCTAssertEqual(branching.lineItems(of: 133), [.species(133), .mystery])
        XCTAssertEqual(branching.lineItems(of: 135), [.species(133), .species(135)])
    }

    func testBranchInTheMiddleOfALineKeepsThePathToTheSpeciesAndMarksTheBranch() {
        let line = SpeciesIndex(entries: [
            entry(1, "가", "A"),
            entry(2, "나", "B", from: 1),
            entry(3, "다", "C", from: 2),
            entry(4, "라", "D", from: 2),
        ])
        XCTAssertEqual(line.lineItems(of: 2), [.species(1), .species(2), .mystery])
        XCTAssertEqual(line.lineItems(of: 3), [.species(1), .species(2), .species(3)])
    }

    func testEvolutionCycleDoesNotHangOrRepeatAnId() {
        let cyclic = SpeciesIndex(entries: [entry(1, "가", "A", from: 2), entry(2, "나", "B", from: 1)])
        XCTAssertNil(cyclic.baseID(of: 1))
        XCTAssertEqual(cyclic.acquisition(of: 1), .unavailable)
        XCTAssertEqual(cyclic.lineItems(of: 1), [.species(2), .species(1)])
    }
}

private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []
    func record(_ url: String) { lock.lock(); urls.append(url); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return urls }
}

final class SpeciesIndexClientTests: XCTestCase {
    private let graphQL = """
    {"data":{"pokemonspecies":[
      {"id":1,"capture_rate":45,"is_legendary":false,"is_mythical":false,"evolves_from_species_id":null,
       "pokemonspeciesnames":[{"name":"이상해씨","language":{"name":"ko"}},{"name":"Bulbasaur","language":{"name":"en"}}],
       "pokemons":[{"pokemontypes":[{"type":{"name":"grass"}},{"type":{"name":"poison"}}]}]},
      {"id":2,"capture_rate":45,"is_legendary":false,"is_mythical":false,"evolves_from_species_id":1,
       "pokemonspeciesnames":[{"name":"이상해풀","language":{"name":"ko"}}],"pokemons":[]}]}}
    """

    private func fileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("species-index-\(UUID().uuidString).json")
    }

    private func client(file: URL, now: @escaping @Sendable () -> Date = Date.init, log: CallLog = CallLog(),
                        fetch: @escaping @Sendable (URLRequest) async throws -> Data) -> SpeciesIndexClient {
        SpeciesIndexClient(file: file, now: now, maxSpeciesID: 2, minimumCount: 1,
                           fetch: { request in
                               log.record(request.url?.absoluteString ?? "")
                               return try await fetch(request)
                           })
    }

    func testGraphQLResponseBecomesIndexAndIsCachedOnDisk() async throws {
        let file = fileURL()
        let log = CallLog()
        let data = Data(graphQL.utf8)
        let first = try await client(file: file, log: log) { _ in data }.index()
        XCTAssertEqual(first.entry(1)?.types, ["grass", "poison"])
        XCTAssertEqual(first.entry(1)?.names["ko"], "이상해씨")
        XCTAssertEqual(first.entry(2)?.evolvesFromID, 1)
        XCTAssertEqual(log.all.count, 1)

        let second = try await client(file: file, log: log) { _ in throw URLError(.notConnectedToInternet) }.index()
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(log.all.count, 1, "fresh disk cache means no request")
    }

    func testStaleDiskCacheIsUsedWhenOffline() async throws {
        let file = fileURL()
        let data = Data(graphQL.utf8)
        _ = try await client(file: file, now: { Date(timeIntervalSince1970: 0) }) { _ in data }.index()
        let later: @Sendable () -> Date = { Date(timeIntervalSince1970: 60 * 86400) }
        let offline = try await client(file: file, now: later) { _ in throw URLError(.notConnectedToInternet) }.index()
        XCTAssertEqual(offline.count, 2)
    }

    func testRESTFallbackBuildsTheIndexWhenGraphQLIsDown() async throws {
        let species1 = #"{"id":1,"capture_rate":45,"is_legendary":false,"is_mythical":false,"names":[{"name":"Bulbasaur","language":{"name":"en"}}],"evolves_from_species":null}"#
        let species2 = #"{"id":2,"capture_rate":45,"is_legendary":false,"is_mythical":false,"names":[],"evolves_from_species":{"name":"bulbasaur","url":"https://pokeapi.co/api/v2/pokemon-species/1/"}}"#
        let grass = #"{"pokemon":[{"slot":1,"pokemon":{"url":"https://pokeapi.co/api/v2/pokemon/1/"}},{"slot":1,"pokemon":{"url":"https://pokeapi.co/api/v2/pokemon/10001/"}}]}"#
        let poison = #"{"pokemon":[{"slot":2,"pokemon":{"url":"https://pokeapi.co/api/v2/pokemon/1/"}}]}"#
        let empty = #"{"pokemon":[]}"#
        let built = try await client(file: fileURL()) { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("graphql") { throw URLError(.cannotConnectToHost) }
            if url.hasSuffix("pokemon-species/1") { return Data(species1.utf8) }
            if url.hasSuffix("pokemon-species/2") { return Data(species2.utf8) }
            if url.hasSuffix("type/grass") { return Data(grass.utf8) }
            if url.hasSuffix("type/poison") { return Data(poison.utf8) }
            return Data(empty.utf8)
        }.index()
        XCTAssertEqual(built.count, 2)
        XCTAssertEqual(built.entry(1)?.types, ["grass", "poison"])
        XCTAssertEqual(built.entry(2)?.evolvesFromID, 1)
    }

    func testTooFewSpeciesIsRejected() async {
        let tiny = Data(#"{"data":{"pokemonspecies":[]}}"#.utf8)
        let strict = SpeciesIndexClient(file: fileURL(), maxSpeciesID: 2, minimumCount: 2,
                                        fetch: { request in
                                            if request.url?.host == "graphql.pokeapi.co" { return tiny }
                                            throw URLError(.cannotConnectToHost)
                                        })
        do {
            _ = try await strict.index()
            XCTFail("an empty index must not be accepted")
        } catch {}
    }
}
