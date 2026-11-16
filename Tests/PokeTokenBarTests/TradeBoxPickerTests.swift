import SwiftUI
import XCTest
@testable import PokeTokenBar

private final class BotStub: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(path: String, body: [String: String])] = []
    var proposeStatus = 200
    var proposeBody = "{}"

    var proposals: [[String: String]] {
        lock.lock(); defer { lock.unlock() }
        return recorded.filter { $0.path == "/v1/trades" }.map(\.body)
    }

    func reply(_ request: URLRequest) -> (Data, Int) {
        let path = request.url?.path ?? ""
        if request.httpMethod == "POST", path == "/v1/trades" {
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
            lock.lock(); recorded.append((path, body)); lock.unlock()
            return (Data(proposeBody.utf8), proposeStatus)
        }
        if path == "/v1/coworkers" {
            return (Data(#"{"coworkers":[{"id":"u1","name":"Alex Kim"},{"id":"u2","name":"Sam Lee"}]}"#.utf8), 200)
        }
        return (Data("{}".utf8), 404)
    }
}

@MainActor
final class TradeBoxPickerTests: XCTestCase {
    private let coworkers = [TradeCoworker(id: "u1", name: "Alex Kim"), TradeCoworker(id: "u2", name: "Sam Lee")]

    private func store() throws -> CompanionStore {
        let (store, cleanup) = try BoxDexFixture.makeStore(language: .en)
        addTeardownBlock { cleanup() }
        return store
    }

    private func uploader(_ bot: BotStub) -> PartyUploader {
        let suite = "trade-box-\(UUID())"
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

    // MARK: Shared model

    func testSendingPostsTheBoxPokemonToThePickedFriendAndClearsThePick() async {
        let bot = BotStub()
        let model = TradeOfferModel(uploader: uploader(bot), give: BoxDexFixture.eeveeID)
        await model.load()
        XCTAssertEqual(model.coworkers, coworkers)
        model.pickTarget("u2")
        XCTAssertEqual(model.targetName, "Sam Lee")
        await model.send()
        XCTAssertEqual(bot.proposals, [["to": "u2", "give": BoxDexFixture.eeveeID]])
        XCTAssertEqual(model.phase, .sent("Sam Lee"))
        XCTAssertNil(model.target)
        XCTAssertNil(model.give)
    }

    func testARefusalAndAFailureAreKeptAsTheResultAndTheOfferStaysSendable() async {
        let bot = BotStub()
        bot.proposeStatus = 400
        bot.proposeBody = #"{"message":"Sam Lee has no free slot"}"#
        let model = TradeOfferModel(uploader: uploader(bot), give: BoxDexFixture.eeveeID, coworkers: coworkers)
        model.pickTarget("u2")
        await model.send()
        XCTAssertEqual(model.phase, .refused("Sam Lee has no free slot"))
        XCTAssertTrue(model.canSend)

        bot.proposeStatus = 500
        await model.send()
        XCTAssertEqual(model.phase, .failed)
        XCTAssertEqual(model.give, BoxDexFixture.eeveeID)
    }

    func testNothingIsSentWithoutAFriend() async {
        let bot = BotStub()
        let model = TradeOfferModel(uploader: uploader(bot), give: BoxDexFixture.eeveeID, coworkers: coworkers)
        XCTAssertFalse(model.canSend)
        await model.send()
        XCTAssertTrue(bot.proposals.isEmpty)
        XCTAssertEqual(model.phase, .idle)
    }

    func testAnUnreachableBotLeavesTheListUnavailable() async {
        let bot = BotStub()
        let down = PartyUploader(
            tokenStore: PartyTokenStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("trade-box-\(UUID())")),
            defaults: UserDefaults(suiteName: "trade-box-\(UUID())")!, appVersion: "test", send: { _ in 200 },
            fetch: { _ in (Data(), 404) }, partySource: { [] })
        down.saveToken("synthetic-token")
        down.serverURL = "http://bot-host:8790"
        let model = TradeOfferModel(uploader: down)
        await model.load()
        XCTAssertNil(model.coworkers)
        XCTAssertTrue(model.loadFailed)
        XCTAssertTrue(bot.proposals.isEmpty)
    }

    // MARK: Box panel

    func testTheBoxPanelGrowsAConfirmRowOnlyOnceAFriendIsPicked() throws {
        let store = try store()
        func height(target: String?) -> CGFloat {
            LayoutMeasure.size(BoxTradePanel(store: store, uploader: uploader(BotStub()),
                                             individualID: BoxDexFixture.eeveeID, pokemonName: "Eevee",
                                             initialTarget: target, initialCoworkers: coworkers),
                               width: PopoverMetrics.contentWidth).height
        }
        XCTAssertGreaterThan(height(target: "u1"), height(target: nil) + 10)
        XCTAssertEqual(store.l.tradeConfirmLine(friend: "Alex Kim", pokemon: "Eevee"), "Offer Eevee to Alex Kim")
    }

    func testTheBoxDetailKeepsTheRefusalGateAndNeverLeavesForTheFriendsTab() throws {
        let store = try store()
        let eevee = try XCTUnwrap(store.state.dex.first { $0.id == BoxDexFixture.eeveeID })
        XCTAssertEqual(store.tradeRefusal(for: eevee, fightingIDs: [BoxDexFixture.eeveeID]), .fighting)

        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/BoxDetailView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(".disabled(tradeRefusal != nil)"), "the refused states keep the button off")
        XCTAssertFalse(source.contains("openTradeOffer"), "the Box page no longer leaves for the Friends tab")
    }

    // MARK: Friends tab


    // MARK: Friends tab

    func testOnlyAPreselectedPokemonCollapsesTheGridUntilChangeIsTapped() throws {
        let store = try store()
        let collapse = TradeOfferView.collapsesGrid
        XCTAssertTrue(collapse(true, false, true))
        XCTAssertFalse(collapse(false, false, true), "no preselection keeps today's grid")
        XCTAssertFalse(collapse(true, true, true), "Change reopens the grid")
        XCTAssertFalse(collapse(true, false, false), "nothing left to summarize after a send")
        XCTAssertEqual(store.l.tradeGivingSummary("Eevee"), "Sending: Eevee")
    }
}
