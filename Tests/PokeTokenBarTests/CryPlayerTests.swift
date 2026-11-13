import XCTest
@testable import PokeTokenBar

@MainActor
final class CryPlayerTests: XCTestCase {
    private final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        var all: [URL] { lock.withLock { urls } }
        func add(_ url: URL) { lock.withLock { urls.append(url) } }
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cries-\(UUID().uuidString)", isDirectory: true)
    }

    /// Serves PokéAPI species names and the Showdown files listed in `cries`; anything else is a 404.
    private func store(_ requests: Requests, identifiers: [Int: String], cries: Set<String>,
                       directory: URL? = nil) -> CryStore {
        CryStore(directory: directory ?? tempDir()) { url in
            requests.add(url)
            if url.host == "pokeapi.co", let id = Int(url.lastPathComponent), let name = identifiers[id] {
                return (Data("{\"name\":\"\(name)\"}".utf8), 200)
            }
            if cries.contains(url.lastPathComponent) { return (Data("mp3:\(url.lastPathComponent)".utf8), 200) }
            return (Data("not found".utf8), 404)
        }
    }

    func test_showdownIDDropsPunctuation() {
        XCTAssertEqual(CryStore.showdownID("nidoran-f"), "nidoranf")
        XCTAssertEqual(CryStore.showdownID("type-null"), "typenull")
        XCTAssertEqual(CryStore.showdownID("blue-striped"), "bluestriped")
    }

    func test_baseFormUsesSpeciesCryOnly() {
        let urls = CryStore.cryURLs(identifier: "mr-mime", speciesID: 122, form: nil)
        XCTAssertEqual(urls.map(\.absoluteString), ["https://play.pokemonshowdown.com/audio/cries/mrmime.mp3"])
        let shaymin = CryStore.cryURLs(identifier: "shaymin", speciesID: 492, form: PokemonForm("land"))
        XCTAssertEqual(shaymin.map(\.lastPathComponent), ["shaymin.mp3"])
    }

    func test_formTriesItsOwnCryBeforeTheSpecies() {
        let urls = CryStore.cryURLs(identifier: "shaymin", speciesID: 492, form: PokemonForm("sky"))
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://play.pokemonshowdown.com/audio/cries/shaymin-sky.mp3",
            "https://play.pokemonshowdown.com/audio/cries/shaymin.mp3",
        ])
    }

    func test_formWithoutItsOwnCryFallsBackAndCaches() async {
        let requests = Requests()
        let dir = tempDir()
        let cries = store(requests, identifiers: [479: "rotom"], cries: ["rotom.mp3"], directory: dir)
        let first = await cries.data(speciesID: 479, form: PokemonForm("wash"))
        XCTAssertEqual(first, Data("mp3:rotom.mp3".utf8))
        XCTAssertEqual(requests.all.map(\.lastPathComponent), ["479", "rotom-wash.mp3", "rotom.mp3"])

        let again = await cries.data(speciesID: 479, form: PokemonForm("wash"))
        XCTAssertEqual(again, first)
        XCTAssertEqual(requests.all.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("479-wash.mp3").path))
    }

    func test_clickPlaysTheFetchedCry() async {
        let requests = Requests()
        var played: [Data] = []
        let player = CryPlayer(store: store(requests, identifiers: [25: "pikachu"], cries: ["pikachu.mp3"]),
                               isEnabled: { true }, output: { played.append($0) })
        await player.play(speciesID: 25, form: nil)?.value
        XCTAssertEqual(played, [Data("mp3:pikachu.mp3".utf8)])
    }

    func test_eggMakesNoRequest() async {
        let requests = Requests()
        let player = CryPlayer(store: store(requests, identifiers: [:], cries: []), isEnabled: { true },
                               output: { _ in XCTFail("an egg has no cry") })
        XCTAssertNil(player.play(speciesID: nil, form: nil))
        XCTAssertTrue(requests.all.isEmpty)
    }

    func test_toggleOffMakesNoRequest() async {
        let requests = Requests()
        let player = CryPlayer(store: store(requests, identifiers: [25: "pikachu"], cries: ["pikachu.mp3"]),
                               isEnabled: { false }, output: { _ in XCTFail("cries are off") })
        XCTAssertNil(player.play(speciesID: 25, form: nil))
        XCTAssertTrue(requests.all.isEmpty)
    }

    func test_settingDefaultsToOn() {
        let defaults = UserDefaults(suiteName: "cry-\(UUID().uuidString)")!
        XCTAssertTrue(CryPlayer.isEnabledInSettings(defaults))
        defaults.set(false, forKey: CryPlayer.enabledKey)
        XCTAssertFalse(CryPlayer.isEnabledInSettings(defaults))
    }

    func test_offlineIsSilent() async {
        let player = CryPlayer(store: CryStore(directory: tempDir()) { _ in nil }, isEnabled: { true },
                               output: { _ in XCTFail("nothing to play offline") })
        await player.play(speciesID: 25, form: nil)?.value
    }
}
