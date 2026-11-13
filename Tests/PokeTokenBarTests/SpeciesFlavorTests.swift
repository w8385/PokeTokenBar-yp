import XCTest
@testable import PokeTokenBar

final class SpeciesFlavorTests: XCTestCase {
    private final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        var all: [URL] { lock.withLock { urls } }
        func add(_ url: URL) { lock.withLock { urls.append(url) } }
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("flavor-\(UUID().uuidString)", isDirectory: true)
    }

    private func lang(_ name: String) -> NamedRef { NamedRef(name: name, url: nil) }

    private func flavor(genera: [(String, String)] = [], entries: [(String, String)]) -> SpeciesFlavor {
        SpeciesFlavor(genera: genera.map { GenusDTO(genus: $0.1, language: lang($0.0)) },
                      flavorEntries: entries.map { FlavorEntryDTO(flavor_text: $0.1, language: lang($0.0)) })
    }

    private let bulbasaurJSON = """
    {"genera":[{"genus":"Seed Pokémon","language":{"name":"en"}},{"genus":"씨앗포켓몬","language":{"name":"ko"}}],
     "flavor_text_entries":[
       {"flavor_text":"A strange seed was\\nplanted on its\\nback at birth.\\fThe plant sprouts.","language":{"name":"en"}},
       {"flavor_text":"옛 도감 설명","language":{"name":"ko"}},
       {"flavor_text":"태어나서 얼마 동안\\n등의 씨앗에 담긴\\n영양을 섭취하며 자란다.","language":{"name":"ko"}}]}
    """

    private func client(_ requests: Requests, directory: URL, body: String? = nil) -> SpeciesFlavorClient {
        let payload = body ?? bulbasaurJSON
        return SpeciesFlavorClient(directory: directory) { url in
            requests.add(url)
            return (Data(payload.utf8), 200)
        }
    }

    func test_picksTheAppLanguageEntry() {
        let flavor = flavor(genera: [("en", "Seed Pokémon"), ("ko", "씨앗포켓몬")],
                            entries: [("en", "English text"), ("ko", "한국어 설명")])
        XCTAssertEqual(flavor.genus(in: .ko), "씨앗포켓몬")
        XCTAssertEqual(flavor.flavorText(in: .ko), "한국어 설명")
        XCTAssertEqual(flavor.flavorText(in: .en), "English text")
    }

    func test_fallsBackToEnglishWhenTheLanguageHasNoEntry() {
        let flavor = flavor(genera: [("en", "Seed Pokémon")], entries: [("en", "English text")])
        XCTAssertEqual(flavor.genus(in: .ko), "Seed Pokémon")
        XCTAssertEqual(flavor.flavorText(in: .ko), "English text")
        XCTAssertNil(self.flavor(entries: []).flavorText(in: .en))
    }

    func test_newestGameOfTheLanguageWins() {
        let flavor = flavor(entries: [("ko", "엑스"), ("en", "Red"), ("ko", "소드"), ("ko", "실드")])
        XCTAssertEqual(flavor.flavorText(in: .ko), "실드")
    }

    func test_japanesePrefersTheKanaEntry() {
        let flavor = flavor(entries: [("ja", "漢字"), ("ja-Hrkt", "かな\n二行目")])
        XCTAssertEqual(flavor.flavorText(in: .ja), "かな二行目")
    }

    func test_normalizeJoinsHardWrappedLinesAndPageBreaks() {
        XCTAssertEqual(SpeciesFlavor.normalize("A strange seed was\nplanted on its\nback at birth.\u{000C}The plant sprouts.",
                                               language: "en"),
                       "A strange seed was planted on its back at birth. The plant sprouts.")
        XCTAssertEqual(SpeciesFlavor.normalize("태어나서 얼마 동안\n등의 씨앗에\n영양을 섭취한다.", language: "ko"),
                       "태어나서 얼마 동안 등의 씨앗에 영양을 섭취한다.")
    }

    func test_normalizeRemovesSoftHyphensAndRejoinsHyphenatedBreaks() {
        XCTAssertEqual(SpeciesFlavor.normalize("It is fe\u{00AD}\nrocious and sun-\nlight loving.", language: "en"),
                       "It is ferocious and sun-light loving.")
        XCTAssertEqual(SpeciesFlavor.normalize("  spaced   out \n text \n", language: "en"), "spaced out text")
    }

    func test_normalizeKeepsJapaneseWithoutInsertedSpaces() {
        XCTAssertEqual(SpeciesFlavor.normalize("生まれたときから\u{3000}背中に\n植物の\u{3000}タネが", language: "ja"),
                       "生まれたときから\u{3000}背中に植物の\u{3000}タネが")
    }

    func test_fetchParsesGenusAndNewestKoreanEntry() async {
        let result = await client(Requests(), directory: tempDir()).flavor(speciesID: 1)
        XCTAssertEqual(result?.genus(in: .ko), "씨앗포켓몬")
        XCTAssertEqual(result?.flavorText(in: .ko), "태어나서 얼마 동안 등의 씨앗에 담긴 영양을 섭취하며 자란다.")
        XCTAssertEqual(result?.flavorText(in: .en), "A strange seed was planted on its back at birth. The plant sprouts.")
    }

    func test_secondRequestFromTheSameClientDoesNotFetchAgain() async {
        let requests = Requests()
        let client = client(requests, directory: tempDir())
        _ = await client.flavor(speciesID: 1)
        _ = await client.flavor(speciesID: 1)
        XCTAssertEqual(requests.all.map(\.lastPathComponent), ["1"])
    }

    func test_diskCacheServesANewClientWithoutFetching() async {
        let directory = tempDir()
        let first = Requests()
        let original = await client(first, directory: directory).flavor(speciesID: 1)
        XCTAssertEqual(first.all.count, 1)

        let second = Requests()
        let cached = await client(second, directory: directory).flavor(speciesID: 1)
        XCTAssertEqual(cached, original)
        XCTAssertTrue(second.all.isEmpty)
    }

    func test_offlineAndNotFoundGiveNilAndCacheNothing() async {
        let directory = tempDir()
        let offline = SpeciesFlavorClient(directory: directory) { _ in nil }
        let none = await offline.flavor(speciesID: 1)
        XCTAssertNil(none)
        let missing = SpeciesFlavorClient(directory: directory) { _ in (Data("{}".utf8), 404) }
        let notFound = await missing.flavor(speciesID: 1)
        XCTAssertNil(notFound)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("1.json").path))

        let requests = Requests()
        let online = await client(requests, directory: directory).flavor(speciesID: 1)
        XCTAssertNotNil(online, "a failed fetch must not poison later opens")
    }
}
