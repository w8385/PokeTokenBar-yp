import XCTest
@testable import PokeTokenBar

private let fullReply = """
{"ok": true, "party_size": 1,
 "recent_battles": [
   {"opponent_name": "민수", "my_pokemon_id": 25, "opponent_pokemon_id": 7, "result": "win", "turns": 6,
    "at": "2026-11-13T05:20:11+00:00", "future_field": 1},
   {"opponent_name": null, "my_pokemon_id": null, "opponent_pokemon_id": null, "result": "loss", "turns": null,
    "at": "2026-11-12T01:00:00+00:00"}],
 "coworkers": [
   {"name": "은정", "pokemon_id": 6, "level": 55, "shiny": true},
   {"name": null, "pokemon_id": 10007, "level": 30, "shiny": false}]}
"""

private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _body: String
    init(_ body: String) { _body = body }
    var body: String {
        get { lock.withLock { _body } }
        set { lock.withLock { _body = newValue } }
    }
}

final class BattleInfoDecodingTests: XCTestCase {
    func testDecodesBothListsAndIgnoresUnknownKeys() throws {
        let info = try XCTUnwrap(BattleInfo.decode(Data(fullReply.utf8)))
        XCTAssertEqual(info.recentBattles.count, 2)
        XCTAssertEqual(info.recentBattles[0].opponentName, "민수")
        XCTAssertEqual(info.recentBattles[0].myPokemonId, 25)
        XCTAssertEqual(info.recentBattles[0].opponentPokemonId, 7)
        XCTAssertTrue(info.recentBattles[0].isWin)
        XCTAssertEqual(info.recentBattles[0].turns, 6)
        XCTAssertNotNil(info.recentBattles[0].date)
        XCTAssertFalse(info.recentBattles[1].isWin)
        XCTAssertNil(info.recentBattles[1].opponentName)
        XCTAssertNil(info.recentBattles[1].turns)
        XCTAssertEqual(info.coworkers, [
            BattleInfo.Coworker(name: "은정", pokemonId: 6, level: 55, shiny: true),
            BattleInfo.Coworker(name: nil, pokemonId: 10007, level: 30, shiny: false)])
    }

    func testAReplyWithoutTheNewFieldsDecodesToNil() {
        XCTAssertNil(BattleInfo.decode(Data(#"{"ok": true, "party_size": 1}"#.utf8)))
        XCTAssertNil(BattleInfo.decode(Data()))
        XCTAssertNil(BattleInfo.decode(Data("not json".utf8)))
    }

    func testAReplyWithEmptyListsIsKnownButEmpty() {
        let info = BattleInfo.decode(Data(#"{"ok": true, "recent_battles": [], "coworkers": []}"#.utf8))
        XCTAssertEqual(info, BattleInfo())
    }

    func testAReplyWithOnlyOneListFillsTheOtherWithNothing() throws {
        let info = try XCTUnwrap(BattleInfo.decode(Data(#"{"coworkers": [{"pokemon_id": 6, "level": 5, "shiny": false}]}"#.utf8)))
        XCTAssertTrue(info.recentBattles.isEmpty)
        XCTAssertEqual(info.coworkers.count, 1)
    }

    func testEncodedFormDecodesBackToTheSameInfo() throws {
        let info = try XCTUnwrap(BattleInfo.decode(Data(fullReply.utf8)))
        XCTAssertEqual(BattleInfo.decode(try info.encoded()), info)
    }

    func testSpriteTargetMapsFormIDsAndRejectsUnknownOnes() {
        XCTAssertEqual(BattleInfo.spriteTarget(pokemonID: 25)?.speciesID, 25)
        XCTAssertNil(BattleInfo.spriteTarget(pokemonID: 25)?.form)
        let sky = BattleInfo.spriteTarget(pokemonID: 10006)
        XCTAssertEqual(sky?.speciesID, 492)
        XCTAssertEqual(sky?.form, PokemonForm("sky"))
        XCTAssertNil(BattleInfo.spriteTarget(pokemonID: 10999))
        XCTAssertNil(BattleInfo.spriteTarget(pokemonID: 0))
    }

    @MainActor
    func testEmptyStatesSayPendingBeforeAnyReplyAndEmptyAfterOne() {
        let l = L(.en)
        XCTAssertEqual(BattleInfoSections.recentEmptyText(nil, l), l.battleInfoPending)
        XCTAssertEqual(BattleInfoSections.coworkersEmptyText(nil, l), l.battleInfoPending)
        XCTAssertEqual(BattleInfoSections.recentEmptyText(BattleInfo(), l), l.battleRecentEmpty)
        XCTAssertEqual(BattleInfoSections.coworkersEmptyText(BattleInfo(), l), l.battleCoworkersEmpty)
        let full = BattleInfo.decode(Data(fullReply.utf8))
        XCTAssertNil(BattleInfoSections.recentEmptyText(full, l))
        XCTAssertNil(BattleInfoSections.coworkersEmptyText(full, l))
    }
}

@MainActor
final class BattleInfoUploaderTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BattleInfo-\(UUID().uuidString)")
        suite = "BattleInfo-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeUploader(_ reply: ReplyBox, status: Int = 200) -> PartyUploader {
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: directory.appendingPathComponent("token")),
            defaults: defaults, appVersion: "test",
            exchange: { _ in (Data(reply.body.utf8), status) },
            partySource: { [PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)] })
        uploader.serverURL = "http://example.local:8790"
        return uploader
    }

    func testTheUploadReplyFillsTheInfoAndASecondUploaderRestoresIt() async throws {
        let uploader = makeUploader(ReplyBox(fullReply))
        XCTAssertNil(uploader.battleInfo)
        uploader.saveToken("token")
        await uploader.tick()
        XCTAssertEqual(uploader.battleInfo?.recentBattles.count, 2)
        XCTAssertEqual(uploader.battleInfo?.coworkers.count, 2)

        let restarted = makeUploader(ReplyBox(#"{"ok": true}"#))
        XCTAssertEqual(restarted.battleInfo, uploader.battleInfo)
    }

    func testAReplyFromAnOldBotKeepsTheLastInfo() async throws {
        let reply = ReplyBox(fullReply)
        let uploader = makeUploader(reply)
        uploader.saveToken("token")
        await uploader.tick()
        let before = uploader.battleInfo
        reply.body = #"{"ok": true, "party_size": 1}"#
        await uploader.tick(now: Date().addingTimeInterval(PartyUploader.resendInterval + 1))
        XCTAssertNotNil(before)
        XCTAssertEqual(uploader.battleInfo, before)
    }

    func testANewReplyReplacesTheListsEvenWhenTheyBecomeEmpty() async throws {
        let reply = ReplyBox(fullReply)
        let uploader = makeUploader(reply)
        uploader.saveToken("token")
        await uploader.tick()
        reply.body = #"{"ok": true, "recent_battles": [], "coworkers": []}"#
        await uploader.tick(now: Date().addingTimeInterval(PartyUploader.resendInterval + 1))
        XCTAssertEqual(uploader.battleInfo, BattleInfo())
    }

    func testAFailedUploadDoesNotTouchTheInfo() async throws {
        let uploader = makeUploader(ReplyBox(fullReply), status: 503)
        uploader.saveToken("token")
        await uploader.tick()
        XCTAssertNil(uploader.battleInfo)
    }

    func testClearingTheTokenForgetsTheInfoAcrossARestart() async throws {
        let uploader = makeUploader(ReplyBox(fullReply))
        uploader.saveToken("token")
        await uploader.tick()
        uploader.clearToken()
        XCTAssertNil(uploader.battleInfo)
        uploader.saveToken("token")
        XCTAssertNil(makeUploader(ReplyBox("{}")).battleInfo)
    }
}
