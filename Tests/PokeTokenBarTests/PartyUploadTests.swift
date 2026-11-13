import Foundation
import XCTest
@testable import PokeTokenBar

private final class SendRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var status: Int
    var requests: [URLRequest] { lock.withLock { _requests } }

    init(status: Int = 200) { self.status = status }

    func send(_ request: URLRequest) -> Int {
        lock.withLock {
            _requests.append(request)
            return status
        }
    }
}

final class PartyBuilderTests: XCTestCase {
    private func profile(level: Int) -> PokemonProfile {
        var profile = PokemonProfile.generate(seed: 7)
        profile.level = level
        return profile
    }

    private func entry(_ id: Int, caught: TimeInterval, released: Bool = false, shiny: Bool = false,
                       form: PokemonForm? = nil) -> DexEntry {
        DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: .common,
                 caughtAt: Date(timeIntervalSince1970: caught), isShiny: shiny,
                 profile: profile(level: 30), releasedAt: released ? Date(timeIntervalSince1970: caught) : nil,
                 form: form)
    }

    func testPartyIsOnlyThePokemonBeingRaised() {
        var state = CompanionState()
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: profile(level: 42))
        state.dex = [entry(10, caught: 100), entry(12, caught: 600)]

        let party = PartyBuilder.party(from: state)

        XCTAssertEqual(party.map(\.pokemonID), [5])
        XCTAssertEqual(party.first?.level, 42)
    }

    func testEggHasNoPartyEvenWithCatches() {
        var state = CompanionState()
        state.dex = [entry(25, caught: 1, shiny: true)]

        XCTAssertTrue(PartyBuilder.party(from: state).isEmpty)
    }

    func testFormWithItsOwnVarietyUsesTheVarietyID() {
        let sky = PartyBuilder.member(speciesID: 492, form: PokemonForm("sky"), shiny: false, profile: nil)
        let unownB = PartyBuilder.member(speciesID: 201, form: PokemonForm("b"), shiny: false, profile: nil)

        XCTAssertEqual(sky.pokemonID, 10006)
        XCTAssertEqual(unownB.pokemonID, 201)
    }

    func testMissingProfileSendsLevelOneWithoutIVsAndLevelIsClamped() {
        let bare = PartyBuilder.member(speciesID: 1, form: nil, shiny: false, profile: nil)
        let over = PartyBuilder.member(speciesID: 1, form: nil, shiny: false, profile: profile(level: 250))

        XCTAssertEqual(bare.level, 1)
        XCTAssertNil(bare.ivs)
        XCTAssertEqual(over.level, 100)
    }

    func testMemberCarriesTheNatureAsItsLowercaseName() throws {
        let member = PartyBuilder.member(speciesID: 25, form: nil, shiny: false, profile: profile(level: 30),
                                         nature: .adamant)
        XCTAssertEqual(member.nature, "adamant")

        let data = try PartyPayload(appVersion: nil, party: [member]).encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["party"] as? [[String: Any]])?.first?["nature"] as? String, "adamant")
    }

    func testMemberWithoutANatureLeavesTheFieldOut() throws {
        let member = PartyBuilder.member(speciesID: 25, form: nil, shiny: false, profile: profile(level: 30))
        XCTAssertNil(member.nature)

        let data = try PartyPayload(appVersion: nil, party: [member]).encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil((json["party"] as? [[String: Any]])?.first?["nature"])
    }

    func testMemberCarriesTheRolledAbilityName() throws {
        var rolled = profile(level: 30)
        rolled.abilityName = "huge-power"
        let member = PartyBuilder.member(speciesID: 25, form: nil, shiny: false, profile: rolled)
        XCTAssertEqual(member.ability, "huge-power")

        let data = try PartyPayload(appVersion: nil, party: [member]).encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["party"] as? [[String: Any]])?.first?["ability"] as? String, "huge-power")
    }

    func testMemberWithoutARolledAbilityLeavesTheFieldOut() throws {
        let member = PartyBuilder.member(speciesID: 25, form: nil, shiny: false, profile: profile(level: 30))
        XCTAssertNil(member.ability)

        let data = try PartyPayload(appVersion: nil, party: [member]).encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil((json["party"] as? [[String: Any]])?.first?["ability"])
    }

    func testRaisedPokemonSendsItsNature() {
        var state = CompanionState()
        var active = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 1, profile: profile(level: 12))
        active.nature = .timid
        state.active = active
        XCTAssertEqual(PartyBuilder.party(from: state).first?.nature, "timid")
    }

    func testPayloadUsesTheBotFieldNames() throws {
        let ivs = PokemonIVs(hp: 31, attack: 20, defense: 15, specialAttack: 31, specialDefense: 10, speed: 28)
        let data = try PartyPayload(appVersion: "2.5.7",
                                    party: [PartyMember(pokemonID: 25, level: 42, shiny: false, ivs: ivs)]).encoded()

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["app_version"] as? String, "2.5.7")
        let member = try XCTUnwrap((json["party"] as? [[String: Any]])?.first)
        XCTAssertEqual(member["pokemon_id"] as? Int, 25)
        XCTAssertEqual(member["level"] as? Int, 42)
        XCTAssertEqual(member["shiny"] as? Bool, false)
        XCTAssertEqual(member["ivs"] as? [String: Int],
                       ["hp": 31, "attack": 20, "defense": 15, "special_attack": 31, "special_defense": 10, "speed": 28])
    }
}

final class PartyRequestTests: XCTestCase {
    func testRequestPostsJSONWithBearerToken() throws {
        let request = try XCTUnwrap(PartyUploader.request(
            serverURL: " http://example.local:8790/ ", token: "tok", body: Data("{}".utf8)))

        XCTAssertEqual(request.url?.absoluteString, "http://example.local:8790/v1/party")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 5)
    }

    func testRejectsServerURLsThatAreNotHTTP() {
        for url in ["", "example.local:8790", "ftp://example.local", "http://"] {
            XCTAssertNil(PartyUploader.request(serverURL: url, token: "tok", body: Data()), url)
        }
    }

    func testResendsUnchangedPartyOnlyAfterFiveMinutes() {
        let body = Data("a".utf8)
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(PartyUploader.shouldSend(body: body, lastBody: nil, lastAttemptAt: nil, now: start))
        XCTAssertFalse(PartyUploader.shouldSend(body: body, lastBody: body, lastAttemptAt: start,
                                                now: start.addingTimeInterval(299)))
        XCTAssertTrue(PartyUploader.shouldSend(body: body, lastBody: body, lastAttemptAt: start,
                                               now: start.addingTimeInterval(300)))
        XCTAssertTrue(PartyUploader.shouldSend(body: Data("b".utf8), lastBody: body, lastAttemptAt: start,
                                               now: start.addingTimeInterval(1)))
    }

    func testRegistrationLinkCarriesTheTokenAndServer() throws {
        let url = try XCTUnwrap(URL(string:
            "poketokenbar://ypoke-register?token=abc-_123&server=http%3A%2F%2Fexample.local%3A8790"))

        XCTAssertEqual(PartyRegistrationLink(url: url)?.token, "abc-_123")
        XCTAssertEqual(PartyRegistrationLink(url: url)?.server, "http://example.local:8790")
        XCTAssertNil(AgentActivityEvent(url: url))
    }

    func testRegistrationLinkWithoutAValidServerKeepsOnlyTheToken() {
        for raw in ["poketokenbar://ypoke-register?token=abc",
                    "poketokenbar://ypoke-register?token=abc&server=example.local:8790",
                    "poketokenbar://ypoke-register?token=abc&server=ftp://example.local"] {
            let link = URL(string: raw).flatMap(PartyRegistrationLink.init(url:))
            XCTAssertEqual(link?.token, "abc", raw)
            XCTAssertNil(link?.server, raw)
        }
    }

    func testRegistrationLinkIgnoresOtherURLsAndBadTokens() {
        for raw in ["poketokenbar://agent?state=done&token=abc", "https://ypoke-register?token=abc",
                    "poketokenbar://ypoke-register", "poketokenbar://ypoke-register?token=a%20b",
                    "poketokenbar://ypoke-register?server=http://example.local:8790"] {
            XCTAssertNil(URL(string: raw).flatMap(PartyRegistrationLink.init(url:)), raw)
        }
    }

    func testTokenNormalizationTrimsAndRejectsInnerWhitespace() {
        XCTAssertEqual(PartyTokenStore.normalize("  abc123\n"), "abc123")
        XCTAssertNil(PartyTokenStore.normalize("   "))
        XCTAssertNil(PartyTokenStore.normalize("abc 123"))
        XCTAssertNil(PartyTokenStore.normalize("abc\n123"))
    }
}

@MainActor
final class PartyUploaderTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PartyUpload-\(UUID().uuidString)")
        suite = "PartyUpload-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeUploader(_ recorder: SendRecorder,
                              server: String? = "http://example.local:8790",
                              party: @escaping @MainActor () -> [PartyMember] = {
                                  [PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)]
                              }) -> PartyUploader {
        let uploader = PartyUploader(tokenStore: PartyTokenStore(fileURL: directory.appendingPathComponent("token")),
                                     defaults: defaults, appVersion: "test",
                                     send: { recorder.send($0) }, partySource: party)
        if let server { uploader.serverURL = server }
        return uploader
    }

    func testTokenWithoutAServerSendsNothingUntilALinkBringsOne() async throws {
        let recorder = SendRecorder()
        let uploader = makeUploader(recorder, server: nil)
        XCTAssertTrue(uploader.saveToken("old"))

        await uploader.tick()
        XCTAssertFalse(uploader.hasServer)
        XCTAssertTrue(recorder.requests.isEmpty)

        let link = try XCTUnwrap(URL(string: "poketokenbar://ypoke-register?token=new&server=http://example.local:8790")
            .flatMap(PartyRegistrationLink.init(url:)))
        XCTAssertTrue(uploader.register(link))
        await uploader.tick()

        XCTAssertTrue(uploader.hasServer)
        XCTAssertEqual(recorder.requests.first?.url?.absoluteString, "http://example.local:8790/v1/party")
        XCTAssertEqual(recorder.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertEqual(makeUploader(SendRecorder(), server: nil).serverURL, "http://example.local:8790")
    }

    func testLinkWithoutAServerKeepsTheCurrentServer() throws {
        let uploader = makeUploader(SendRecorder(), server: "http://10.0.0.5:8790")
        let link = try XCTUnwrap(URL(string: "poketokenbar://ypoke-register?token=new")
            .flatMap(PartyRegistrationLink.init(url:)))

        XCTAssertTrue(uploader.register(link))
        XCTAssertEqual(uploader.serverURL, "http://10.0.0.5:8790")
    }

    func testDoesNothingWithoutAToken() async {
        let recorder = SendRecorder()
        let uploader = makeUploader(recorder)

        await uploader.tick()

        XCTAssertFalse(uploader.hasToken)
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testSendsOnceThenWaitsForChangeOrFiveMinutes() async throws {
        let recorder = SendRecorder()
        let uploader = makeUploader(recorder)
        try PartyTokenStore(fileURL: directory.appendingPathComponent("token")).save("tok")
        let start = Date(timeIntervalSince1970: 5_000)

        await uploader.tick(now: start)
        await uploader.tick(now: start.addingTimeInterval(60))
        await uploader.tick(now: start.addingTimeInterval(300))

        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertEqual(uploader.lastSuccessAt, start.addingTimeInterval(300))
        XCTAssertEqual(recorder.requests.first?.url?.absoluteString, "http://example.local:8790/v1/party")
    }

    func testEmptyPartyIsNotSent() async throws {
        let recorder = SendRecorder()
        let uploader = makeUploader(recorder, party: { [] })
        try PartyTokenStore(fileURL: directory.appendingPathComponent("token")).save("tok")

        await uploader.tick()

        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testUnauthorizedMarksTheTokenRejectedUntilANewOneIsSaved() async {
        let recorder = SendRecorder(status: 401)
        let uploader = makeUploader(recorder)
        XCTAssertTrue(uploader.saveToken("old"))

        await uploader.tick()
        XCTAssertTrue(uploader.tokenRejected)
        XCTAssertNil(uploader.lastSuccessAt)

        recorder.status = 200
        XCTAssertTrue(uploader.saveToken("new"))
        XCTAssertFalse(uploader.tokenRejected)
        await uploader.tick()
        XCTAssertEqual(recorder.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertNotNil(uploader.lastSuccessAt)
    }

    func testInvalidTokenKeepsTheSavedOneAndClearTurnsUploadOff() async throws {
        let recorder = SendRecorder()
        let uploader = makeUploader(recorder)
        XCTAssertTrue(uploader.saveToken("tok"))

        XCTAssertFalse(uploader.saveToken("has space"))
        XCTAssertTrue(uploader.hasToken)

        uploader.clearToken()
        let countAfterClear = recorder.requests.count
        await uploader.tick()
        XCTAssertFalse(uploader.hasToken)
        XCTAssertEqual(recorder.requests.count, countAfterClear)
    }

    func testTokenFileIsOwnerOnly() throws {
        let store = PartyTokenStore(fileURL: directory.appendingPathComponent("token"))
        try store.save("tok")

        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(store.load(), "tok")
    }

    func testChangingServerSendsTheUnchangedPartyAgainRightAway() async {
        let recorder = SendRecorder()
        let uploader = makeUploader(recorder)
        XCTAssertTrue(uploader.saveToken("tok"))
        let start = Date(timeIntervalSince1970: 9_000)

        await uploader.tick(now: start)
        uploader.serverURL = "http://10.0.0.5:8790"
        await uploader.tick(now: start.addingTimeInterval(60))

        XCTAssertEqual(recorder.requests.map { $0.url?.host() }, ["example.local", "10.0.0.5"])
    }

    func testServerURLPersists() {
        let uploader = makeUploader(SendRecorder())
        uploader.serverURL = "http://10.0.0.5:8790"

        XCTAssertEqual(makeUploader(SendRecorder(), server: nil).serverURL, "http://10.0.0.5:8790")
    }

    func testNoRouteMarksTheUploadFailedUntilTheNextSuccess() async {
        let tokenStore = PartyTokenStore(fileURL: directory.appendingPathComponent("token"))
        let offline = PartyUploader(tokenStore: tokenStore, defaults: defaults, appVersion: "test",
                                    send: { _ in throw URLError(.cannotConnectToHost) },
                                    partySource: { [PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)] })
        offline.serverURL = "http://example.local:8790"
        XCTAssertTrue(offline.saveToken("tok"))

        await offline.tick()
        XCTAssertTrue(offline.lastAttemptFailed)
        XCTAssertNil(offline.lastSuccessAt)

        let recorder = SendRecorder(status: 503)
        let uploader = makeUploader(recorder)
        await uploader.tick()
        XCTAssertTrue(uploader.lastAttemptFailed)
        recorder.status = 200
        uploader.serverURL = uploader.serverURL
        await uploader.tick()
        XCTAssertFalse(uploader.lastAttemptFailed)
    }

    func testLastSuccessSurvivesARestartButNotATokenChange() async {
        let uploader = makeUploader(SendRecorder())
        XCTAssertTrue(uploader.saveToken("tok"))
        let sent = Date(timeIntervalSince1970: 7_000)
        await uploader.tick(now: sent)

        XCTAssertEqual(makeUploader(SendRecorder()).lastSuccessAt, sent)
        makeUploader(SendRecorder()).clearToken()
        XCTAssertNil(makeUploader(SendRecorder()).lastSuccessAt)
    }
}
