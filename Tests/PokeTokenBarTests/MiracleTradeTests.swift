import SwiftUI
import XCTest
@testable import PokeTokenBar

private final class MiracleBotStub: @unchecked Sendable {
    private let lock = NSLock()
    private var posts: [[String: String]] = []
    private var cancels = 0
    var miracleStatus = 200
    var openOffer: String?
    var postStatus = 200
    var postBody = ""

    var postedBodies: [[String: String]] {
        lock.lock(); defer { lock.unlock() }
        return posts
    }

    var cancelCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cancels
    }

    func reply(_ request: URLRequest) -> (Data, Int) {
        let path = request.url?.path ?? ""
        lock.lock(); defer { lock.unlock() }
        switch (request.httpMethod ?? "GET", path) {
        case ("GET", "/v1/miracle"):
            return (Data(#"{"ok":true,"offer":\#(openOffer ?? "null")}"#.utf8), miracleStatus)
        case ("POST", "/v1/miracle"):
            posts.append(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:])
            return (Data(postBody.utf8), postStatus)
        case ("POST", "/v1/miracle/cancel"):
            cancels += 1
            openOffer = nil
            return (Data(#"{"ok":true}"#.utf8), 200)
        default:
            return (Data("{}".utf8), 404)
        }
    }
}

private let eeveeOffer = #"{"offer_id":"m1","give_id":"eevee","name":"Eevee","expires_at":"2026-11-20T09:00:00Z"}"#
private let listed = MiracleOffer(offerID: "m1", giveID: BoxDexFixture.eeveeID, name: "Eevee",
                                  expiresAt: "2026-11-20T09:00:00Z")

@MainActor
final class MiracleTradeTests: XCTestCase {
    // MARK: Route model

    func testLoadReadsTheOpenOfferNoOfferAndAnUnavailableBot() async {
        let bot = MiracleBotStub()
        let model = MiracleTradeModel(uploader: uploader(bot))
        await model.load()
        XCTAssertEqual(model.availability, .available)
        XCTAssertNil(model.offer)

        bot.openOffer = eeveeOffer
        await model.load()
        XCTAssertEqual(model.offer, listed)
        XCTAssertTrue(model.isOffered(BoxDexFixture.eeveeID))
        XCTAssertFalse(model.isOffered(BoxDexFixture.pikachuID))

        bot.miracleStatus = 404
        await model.load()
        XCTAssertEqual(model.availability, .unavailable)
    }

    func testPostSendsThePokemonAndKeepsTheOfferThenCancelTakesItDown() async {
        let bot = MiracleBotStub()
        bot.postBody = #"{"ok":true,"offer":\#(eeveeOffer)}"#
        let model = MiracleTradeModel(uploader: uploader(bot), availability: .available)
        await model.post(BoxDexFixture.eeveeID)
        XCTAssertEqual(bot.postedBodies, [["give": BoxDexFixture.eeveeID]])
        XCTAssertEqual(model.offer, listed)
        XCTAssertEqual(model.phase, .idle)

        await model.cancel()
        XCTAssertEqual(bot.cancelCount, 1)
        XCTAssertNil(model.offer)
        XCTAssertEqual(model.phase, .idle)
    }

    func testARefusalKeepsTheBotsReasonAndAnUnavailableBotHidesTheFeature() async {
        let bot = MiracleBotStub()
        bot.postStatus = 400
        bot.postBody = #"{"ok":false,"message":"이미 미라클 교환에 올린 포켓몬이 있어요."}"#
        let model = MiracleTradeModel(uploader: uploader(bot), availability: .available)
        await model.post(BoxDexFixture.eeveeID)
        XCTAssertEqual(model.phase, .refused("이미 미라클 교환에 올린 포켓몬이 있어요."))
        XCTAssertNil(model.offer)

        bot.postStatus = 404
        bot.postBody = #"{"ok":false,"error":"unavailable"}"#
        await model.post(BoxDexFixture.eeveeID)
        XCTAssertEqual(model.availability, .unavailable)

        bot.postStatus = 500
        await model.post(BoxDexFixture.eeveeID)
        XCTAssertEqual(model.phase, .failed)
    }

    func testThePostButtonNeedsTheFeatureNoOpenOfferAndATradablePokemon() {
        XCTAssertTrue(MiracleTradeModel.showsPostButton(availability: .available, offer: nil, refusal: nil))
        XCTAssertFalse(MiracleTradeModel.showsPostButton(availability: .unavailable, offer: nil, refusal: nil))
        XCTAssertFalse(MiracleTradeModel.showsPostButton(availability: .unknown, offer: nil, refusal: nil))
        XCTAssertFalse(MiracleTradeModel.showsPostButton(availability: .available, offer: listed, refusal: nil))
        for refusal in [TradeRefusal.raising, .parked, .fighting, .arriving, .unavailable] {
            XCTAssertFalse(MiracleTradeModel.showsPostButton(availability: .available, offer: nil, refusal: refusal))
        }
    }

    // MARK: Box detail

    func testThePostButtonShowsOnlyForATradablePokemonWhileTheFeatureIsOn() throws {
        let (store, cleanup) = try BoxDexFixture.makeStore(language: .en)
        defer { cleanup() }
        let bot = MiracleBotStub()
        let uploader = uploader(bot)
        let suite = "miracle-battle-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let battle = BattleEntryStore(defaults: defaults)
        _ = battle.add(BoxDexFixture.pikachuID)
        let fightingIDs = TradePool.fightingIDs(state: store.state, slots: battle.slots)
        func height(_ id: String, _ availability: MiracleTradeModel.Availability,
                    offer: MiracleOffer? = nil) throws -> CGFloat {
            let entry = try XCTUnwrap(store.boxIndividuals.first { $0.id == id }).entry
            let model = MiracleTradeModel(uploader: uploader, availability: availability, offer: offer)
            return LayoutMeasure.size(MiraclePostButton(
                model: model, individualID: id, refusal: store.tradeRefusal(for: entry, fightingIDs: fightingIDs),
                l: store.l)).height
        }
        XCTAssertGreaterThan(try height(BoxDexFixture.eeveeID, .available), 0, "eevee is tradable")
        XCTAssertEqual(try height(BoxDexFixture.eeveeID, .unavailable), 0, "no battle channel")
        XCTAssertEqual(try height(BoxDexFixture.eeveeID, .unknown), 0, "the bot hasn't answered")
        XCTAssertEqual(try height(BoxDexFixture.eeveeID, .available, offer: listed), 0, "one offer at a time")
        XCTAssertEqual(try height(BoxDexFixture.pikachuID, .available), 0, "the battle Pokémon")
        XCTAssertEqual(try height(BoxDexFixture.raisedID, .available), 0, "the raised Pokémon")
        XCTAssertTrue(bot.postedBodies.isEmpty)
    }

    func testOnlyTheListedPokemonShowsTheOpenOfferPanel() throws {
        let (store, cleanup) = try BoxDexFixture.makeStore(language: .en)
        defer { cleanup() }
        let uploader = uploader(MiracleBotStub())
        func height(_ id: String, offer: MiracleOffer?) -> CGFloat {
            let model = MiracleTradeModel(uploader: uploader, availability: .available, offer: offer)
            return LayoutMeasure.size(MiracleOfferStatus(model: model, individualID: id, l: store.l),
                                      width: PopoverMetrics.contentWidth).height
        }
        XCTAssertGreaterThan(height(BoxDexFixture.eeveeID, offer: listed), 40)
        XCTAssertEqual(height(BoxDexFixture.onixID, offer: listed), 0)
        XCTAssertEqual(height(BoxDexFixture.eeveeID, offer: nil), 0)
    }

    func testTheBoxDetailWiresBothControlsToItsRefusalGate() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/BoxDetailView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("MiraclePostButton(model: miracle, individualID: individual.id, refusal: tradeRefusal"))
        XCTAssertTrue(source.contains("MiracleOfferStatus(model: miracle, individualID: individual.id"))
    }

    private func uploader(_ bot: MiracleBotStub) -> PartyUploader {
        let suite = "miracle-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: scratch)
        }
        let uploader = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
            appVersion: "test", send: { _ in 200 }, fetch: { bot.reply($0) }, partySource: { [] })
        uploader.saveToken("synthetic-token")
        uploader.serverURL = "http://bot-host:8790"
        return uploader
    }
}

/// Opt-in captures for the PR: synthetic save, the real Box detail before and after posting.
///
///     PTB_MIRACLE_SCREENSHOT_DIR=/tmp/shots swift test --filter MiracleTradeShotTests
@MainActor
final class MiracleTradeShotTests: XCTestCase {
    func testCaptureBoxDetailBeforeAndAfterPosting() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_MIRACLE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_MIRACLE_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.ko, .en] {
            let (store, cleanup) = try BoxDexFixture.makeStore(language: language)
            defer { cleanup() }
            let suite = "miracle-shot-\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let uploader = PartyUploader(
                tokenStore: PartyTokenStore(fileURL: scratch.appendingPathComponent("token")), defaults: defaults,
                appVersion: "shot", send: { _ in 200 }, fetch: { _ in (Data("{}".utf8), 404) }, partySource: { [] })
            uploader.saveToken("synthetic-token")
            uploader.serverURL = "http://bot-host:8790"
            let battle = BattleEntryStore(defaults: defaults)
            _ = battle.add(BoxDexFixture.pikachuID)
            let eevee = try XCTUnwrap(store.boxIndividuals.first { $0.id == BoxDexFixture.eeveeID })
            for (state, offer) in [("before", nil), ("after", listed)] as [(String, MiracleOffer?)] {
                let model = MiracleTradeModel(uploader: uploader, availability: .available, offer: offer)
                try await capture(BoxDetailView(store: store, individual: eevee, navigation: PopoverNavigation(),
                                                onBack: {}, initialMiracle: model)
                    .environment(uploader).environment(battle).environment(store), language: language,
                                  to: directory.appendingPathComponent("miracle-box-detail-\(state)-\(language.rawValue).png"))
            }
        }
    }

    private func capture<V: View>(_ view: V, language: AppLanguage, to file: URL) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 720)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale),
            size: size, appearance: .aqua, scale: 2, to: file)
    }
}
