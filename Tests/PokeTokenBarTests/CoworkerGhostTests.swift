import Foundation
import XCTest
@testable import PokeTokenBar

private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private final class GhostExchange: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Data, Int)]
    private var log: [URLRequest] = []

    init(_ replies: [(Data, Int)]) { self.replies = replies }

    var requests: [URLRequest] { lock.withLock { log } }

    var exchange: GymService.Exchange {
        { [self] request in
            try lock.withLock {
                log.append(request)
                guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
                return replies.removeFirst()
            }
        }
    }

    func body(_ index: Int) throws -> [String: Any] {
        let data = try XCTUnwrap(requests[index].httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
final class CoworkerGhostTests: XCTestCase {
    private let link = GymService.Link(server: "http://bot-host:8790", token: "synthetic-token")
    private var trophies = Set<String>()
    private var rewards = 0
    private let l = L(.en)
    private let coworker = BattleInfo.Coworker(name: "Mina", pokemonId: 6, level: 55, shiny: false, id: "c0ffee")
    private let team = GymTeam.Team(ids: ["a"], members: [
        PartyMember(pokemonID: 25, level: 50, shiny: false, ivs: nil, moves: [85]),
    ])

    override func setUp() {
        trophies = []
        rewards = 0
    }

    private func service(_ exchange: GhostExchange) -> GymService {
        GymService(link: { [self] in link }, exchange: exchange.exchange, badges: { GymBadges() }, ownedTMs: { [] },
                   applyReward: { [self] _, _, _ in rewards += 1 },
                   claimCoworkerTrophy: { [self] in trophies.insert($0).inserted },
                   session: GymSession())
    }

    private func outcome(won: Bool) -> (Data, Int) {
        (GymFixtures.outcomeData(gymID: GymOpponent.ghostID, kind: GymOpponent.ghostID, won: won), 200)
    }

    private func error(_ message: String, status: Int) -> (Data, Int) {
        (try! JSONSerialization.data(withJSONObject: ["ok": false, "error": message]), status)
    }

    // MARK: Fights

    func testAGhostFightSendsTheCoworkerIdInsteadOfAGym() async throws {
        let exchange = GhostExchange([outcome(won: true)])
        await service(exchange).fightCoworker(coworker, l: l, team: team)

        XCTAssertEqual(exchange.requests.count, 1)
        XCTAssertEqual(exchange.requests[0].url?.path, "/v1/gym/battle")
        XCTAssertEqual(exchange.requests[0].httpMethod, "POST")
        let body = try exchange.body(0)
        XCTAssertEqual(body["coworker_id"] as? String, "c0ffee")
        XCTAssertNil(body["gym_id"], "an old bot must see no gym_id and refuse, not fight a gym")
        XCTAssertEqual((body["team"] as? [Any])?.count, 1)
    }

    func testTheFirstWinKeepsTheTrophyAndRematchesGiveNothing() async {
        let service = service(GhostExchange([outcome(won: true), outcome(won: true)]))

        await service.fightCoworker(coworker, l: l, team: team)
        XCTAssertEqual(service.last?.trophy, true)
        XCTAssertEqual(service.last?.coworkerID, "c0ffee")
        XCTAssertNil(service.last?.reward)
        XCTAssertEqual(trophies, ["c0ffee"])

        await service.fightCoworker(coworker, l: l, team: team)
        XCTAssertEqual(service.last?.trophy, false)
        XCTAssertEqual(service.last?.outcome.won, true)
        XCTAssertEqual(rewards, 0, "a ghost never pays a gym reward")
    }

    func testALossKeepsNoTrophy() async {
        let service = service(GhostExchange([outcome(won: false)]))
        await service.fightCoworker(coworker, l: l, team: team)

        XCTAssertEqual(service.last?.trophy, false)
        XCTAssertTrue(trophies.isEmpty)
    }

    func testTheGhostIsNamedAsOnTheCoworkersListAtLevelFifty() async {
        let unnamed = BattleInfo.Coworker(name: nil, pokemonId: 6, level: 55, shiny: false, id: "anon")
        let service = service(GhostExchange([outcome(won: true)]))
        await service.fightCoworker(unnamed, l: l, team: team)

        let opponent = GymOpponent.ghost(unnamed, l: l)
        XCTAssertEqual(service.last?.opponent.trainer.displayName(.en), unnamed.label(l))
        XCTAssertEqual(opponent.trainer.displayName(.en), l.battleUnnamed)
        XCTAssertEqual(GymOpponent.ghost(coworker, l: l).trainer.displayName(.en), "Mina")
        XCTAssertEqual(opponent.level, 50)
    }

    func testRefusalsNameTheirReason() async {
        let cases: [((Data, Int), GymService.Failure)] = [
            (error(GymService.unknownCoworker, status: 404), .unknownCoworker),
            (error(GymService.gymIDMissing, status: 400), .botTooOld),
            (error("coworker_id is your own", status: 400), .refused("coworker_id is your own")),
            ((Data(), 404), .botTooOld),
        ]
        for (reply, failure) in cases {
            let service = service(GhostExchange([reply]))
            await service.fightCoworker(coworker, l: l, team: team)
            XCTAssertEqual(service.failure, failure, "\(reply.1)")
            XCTAssertNil(service.last)
        }
        XCTAssertTrue(trophies.isEmpty)
    }

    func testAGymReplyToAGhostFightIsAFailure() async {
        let service = service(GhostExchange([(GymFixtures.outcomeData(gymID: "kanto-1", kind: "gym", won: true), 200)]))
        await service.fightCoworker(coworker, l: l, team: team)

        XCTAssertEqual(service.failure, .failed)
        XCTAssertTrue(trophies.isEmpty)
    }

    func testACoworkerWithoutAnIdSendsNothing() async {
        let exchange = GhostExchange([outcome(won: true)])
        let old = BattleInfo.Coworker(name: "Mina", pokemonId: 6, level: 55, shiny: false)
        await service(exchange).fightCoworker(old, l: l, team: team)

        XCTAssertTrue(exchange.requests.isEmpty)
    }

    // MARK: The list

    func testTheIdDecodesAndAReplyWithoutItStaysFightless() throws {
        let reply = #"{"coworkers": [{"id": "c0ffee", "name": "Mina", "pokemon_id": 6, "level": 55, "shiny": false}]}"#
        let info = try XCTUnwrap(BattleInfo.decode(Data(reply.utf8)))
        XCTAssertEqual(info.coworkers, [coworker])
        XCTAssertEqual(CoworkerGhostSection.fightable(info), [coworker])
        XCTAssertNil(CoworkerGhostSection.emptyText(info, l))

        let old = try XCTUnwrap(BattleInfo.decode(Data(#"{"coworkers": [{"pokemon_id": 6, "level": 55, "shiny": false}]}"#.utf8)))
        XCTAssertTrue(CoworkerGhostSection.fightable(old).isEmpty)
        XCTAssertEqual(CoworkerGhostSection.emptyText(old, l), l.ghostBotTooOld)
    }

    func testTheEmptyLineSaysPendingThenNobody() {
        XCTAssertEqual(CoworkerGhostSection.emptyText(nil, l), l.battleInfoPending)
        XCTAssertEqual(CoworkerGhostSection.emptyText(BattleInfo(), l), l.ghostEmpty)
    }

    // MARK: The save

    func testTheTrophyIsSavedOnceAndSurvivesARelaunch() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ghost-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode(CompanionState()).write(to: file)
        let store = CompanionStore(provider: OfflineProvider(), fileURL: file)

        XCTAssertTrue(store.claimCoworkerTrophy("c0ffee"))
        XCTAssertFalse(store.claimCoworkerTrophy("c0ffee"))
        XCTAssertEqual(CompanionStore(provider: OfflineProvider(), fileURL: file).state.coworkerTrophies, ["c0ffee"])
    }

    func testASaveWithoutTrophiesOrWithABadValueKeepsTheRest() throws {
        var state = CompanionState()
        state.collectedFinals = ["4-6"]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])

        json["coworkerTrophies"] = nil
        let old = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.coworkerTrophies.isEmpty)
        XCTAssertEqual(old.collectedFinals, ["4-6"])

        json["coworkerTrophies"] = 5
        let corrupt = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(corrupt.coworkerTrophies.isEmpty)
        XCTAssertEqual(corrupt.collectedFinals, ["4-6"])
    }
}
