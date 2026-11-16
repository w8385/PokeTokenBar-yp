import Foundation
import XCTest
@testable import PokeTokenBar

private final class ExchangeScript: @unchecked Sendable {
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
final class GymServiceTests: XCTestCase {
    private let link = GymService.Link(server: "http://bot-host:8790", token: "synthetic-token")
    private var badges = GymBadges()
    private var owned = Set<Int>()
    private var applied: [GymReward] = []
    private var linked = true

    override func setUp() {
        badges = GymBadges()
        owned = []
        applied = []
        linked = true
    }

    private func service(_ script: ExchangeScript, session: GymSession = GymSession()) -> GymService {
        GymService(link: { [self] in linked ? link : nil }, exchange: script.exchange,
                   badges: { [self] in badges }, ownedTMs: { [self] in owned },
                   applyReward: { [self] reward, _, _ in
                       applied.append(reward)
                       badges = reward.badges
                       if let move = reward.tmMoveID { owned.insert(move) }
                   },
                   session: session)
    }

    private let kanto = GymFixtures.catalog().region("kanto")!
    private let team = GymTeam.Team(ids: ["a", "b"], members: [
        PartyMember(pokemonID: 25, level: 50, shiny: false, ivs: nil, moves: [85]),
        PartyMember(pokemonID: 6, level: 50, shiny: false, ivs: nil, moves: [53]),
    ])

    private func eliteStep(_ step: Int, won: Bool, next: String?, carry: [[String: Any]?]?) -> (Data, Int) {
        let id = step == 5 ? "kanto-champion" : "kanto-elite-\(step)"
        return (GymFixtures.outcomeData(gymID: id, kind: step == 5 ? "champion" : "elite", won: won,
                                        run: ("kanto-elite", step, 5, "kanto-elite-1", next), carry: carry), 200)
    }

    private let carry: [[String: Any]?] = [GymFixtures.carryJSON(hp: 60), GymFixtures.carryJSON(hp: 20, status: "psn")]

    // MARK: Catalog

    func testCatalogLoadsOnceAndIsKept() async {
        let script = ExchangeScript([(GymFixtures.catalogData(), 200)])
        let session = GymSession()
        let first = service(script, session: session)
        await first.loadCatalog()
        await first.loadCatalog()

        XCTAssertEqual(first.catalog?.regions.count, 2)
        XCTAssertNil(first.unavailable)
        XCTAssertEqual(script.requests.count, 1)
        XCTAssertEqual(script.requests[0].url?.path, "/v1/gyms")
        XCTAssertEqual(script.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
        XCTAssertEqual(service(ExchangeScript([]), session: session).catalog?.regions.count, 2)
    }

    func testUnlinkedStaysUnavailableWithoutAnyRequest() async {
        linked = false
        let script = ExchangeScript([])
        let service = service(script)
        await service.loadCatalog()

        XCTAssertEqual(service.unavailable, .notLinked)
        XCTAssertTrue(script.requests.isEmpty)
    }

    func testCatalogFailuresNameTheirReason() async {
        let cases: [(Data, Int, GymService.Unavailable)] = [
            (Data(), 401, .rejected), (Data(), 404, .botTooOld), (Data(), 503, .unreachable),
            (Data(#"{"ok":true,"regions":[]}"#.utf8), 200, .botTooOld), (Data("nope".utf8), 200, .botTooOld),
        ]
        for (data, status, reason) in cases {
            let service = service(ExchangeScript([(data, status)]))
            await service.loadCatalog()
            XCTAssertEqual(service.unavailable, reason, "\(status)")
            XCTAssertNil(service.catalog)
        }
        let offline = service(ExchangeScript([]))
        await offline.loadCatalog()
        XCTAssertEqual(offline.unavailable, .unreachable)
    }

    func testUnreachableCatalogLoadsOnRetry() async {
        let script = ExchangeScript([(Data(), 503), (GymFixtures.catalogData(), 200)])
        let service = service(script)
        await service.loadCatalog()
        XCTAssertEqual(service.unavailable, .unreachable)
        await service.loadCatalog()

        XCTAssertNil(service.unavailable)
        XCTAssertNotNil(service.catalog)
    }

    // MARK: Gyms and rewards

    func testGymWinSendsTheTeamAndRewardsOnce() async throws {
        let gym = kanto.gyms[0]
        let win = (GymFixtures.outcomeData(gymID: gym.id, kind: "gym", won: true), 200)
        let script = ExchangeScript([win, win])
        let service = service(script)

        await service.fightGym(gym, region: kanto, team: team)
        let body = try script.body(0)
        XCTAssertEqual(body["gym_id"] as? String, "kanto-1")
        XCTAssertEqual((body["team"] as? [Any])?.count, 2)
        XCTAssertNil(body["carried"])
        XCTAssertEqual(script.requests[0].url?.path, "/v1/gym/battle")
        XCTAssertEqual(script.requests[0].httpMethod, "POST")
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(service.last?.reward?.kind, .gymBadge(index: 1))

        await service.fightGym(gym, region: kanto, team: team)
        XCTAssertEqual(applied.count, 1)
        XCTAssertNil(service.last?.reward)
        XCTAssertTrue(service.last?.outcome.won == true)
    }

    func testGymLossRewardsNothing() async {
        let gym = kanto.gyms[2]
        let service = service(ExchangeScript([(GymFixtures.outcomeData(gymID: gym.id, kind: "gym", won: false), 200)]))
        await service.fightGym(gym, region: kanto, team: team)

        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(service.last?.outcome.won, false)
        XCTAssertEqual(badges, GymBadges())
    }

    // MARK: Runs

    func testEliteRunCarriesHpAndStatusIntoTheNextBattle() async throws {
        let script = ExchangeScript([
            eliteStep(1, won: true, next: "kanto-elite-2", carry: carry),
            eliteStep(2, won: true, next: "kanto-elite-3", carry: carry),
        ])
        let service = service(script)
        let battles = kanto.elite.battles

        XCTAssertEqual(service.nextStep(of: "kanto-elite", battles: battles, team: team), 1)
        await service.fightRun("kanto-elite", battles: battles, region: kanto, team: team)
        XCTAssertNil(try script.body(0)["carried"])
        XCTAssertEqual(service.nextStep(of: "kanto-elite", battles: battles, team: team), 2)

        await service.fightRun("kanto-elite", battles: battles, region: kanto, team: team)
        let second = try script.body(1)
        XCTAssertEqual(second["gym_id"] as? String, "kanto-elite-2")
        let carried = try XCTUnwrap(second["carried"] as? [[String: Any]])
        XCTAssertEqual(carried.map { $0["hp"] as? Int }, [60, 20])
        XCTAssertEqual(carried[1]["status"] as? String, "psn")
        XCTAssertTrue(applied.isEmpty)
    }

    func testLosingARunStartsItOverWithFullHealth() async throws {
        let script = ExchangeScript([
            eliteStep(1, won: true, next: "kanto-elite-2", carry: carry),
            eliteStep(2, won: false, next: nil, carry: nil),
            eliteStep(1, won: true, next: "kanto-elite-2", carry: carry),
        ])
        let service = service(script)
        let battles = kanto.elite.battles
        for _ in 0..<3 { await service.fightRun("kanto-elite", battles: battles, region: kanto, team: team) }

        XCTAssertEqual(try script.body(2)["gym_id"] as? String, "kanto-elite-1")
        XCTAssertNil(try script.body(2)["carried"])
    }

    func testChangingTheTeamMidRunRestartsIt() async throws {
        let script = ExchangeScript([eliteStep(1, won: true, next: "kanto-elite-2", carry: carry),
                                     eliteStep(1, won: true, next: "kanto-elite-2", carry: carry)])
        let service = service(script)
        let battles = kanto.elite.battles
        await service.fightRun("kanto-elite", battles: battles, region: kanto, team: team)
        let other = GymTeam.Team(ids: ["a", "c"], members: team.members)

        XCTAssertEqual(service.nextStep(of: "kanto-elite", battles: battles, team: other), 1)
        await service.fightRun("kanto-elite", battles: battles, region: kanto, team: other)
        XCTAssertEqual(try script.body(1)["gym_id"] as? String, "kanto-elite-1")
        XCTAssertNil(try script.body(1)["carried"])
    }

    func testClearingTheWholeEliteRunRewardsTheChampionOnceAndEndsTheRun() async throws {
        let champion = (GymFixtures.outcomeData(gymID: "kanto-champion", kind: "champion", won: true,
                                                run: ("kanto-elite", 5, 5, "kanto-elite-1", nil)), 200)
        var steps = (1...4).map { eliteStep($0, won: true, next: $0 == 4 ? "kanto-champion" : "kanto-elite-\($0 + 1)", carry: carry) }
        steps.append(champion)
        let service = service(ExchangeScript(steps))
        let battles = kanto.elite.battles
        for _ in 0..<5 { await service.fightRun("kanto-elite", battles: battles, region: kanto, team: team) }

        XCTAssertEqual(applied.map(\.kind), [.hallOfFame])
        XCTAssertTrue(badges.region("kanto").hallOfFame)
        XCTAssertEqual(service.nextStep(of: "kanto-elite", battles: battles, team: team), 1)
        XCTAssertNotNil(applied[0].tmMoveID)
    }

    func testTheHideoutBossGivesTheOrgBadgeOnItsFirstClear() async {
        let boss = kanto.hideout.battles[3]
        let service = service(ExchangeScript([(GymFixtures.outcomeData(
            gymID: boss.id, kind: "boss", won: true, run: ("kanto-hideout", 4, 4, "kanto-hideout-1", nil)), 200)]))
        await service.fightRun("kanto-hideout", battles: [boss], region: kanto, team: team)

        XCTAssertEqual(applied.map(\.kind), [.orgBadge])
        XCTAssertTrue(badges.region("kanto").orgBeaten)
    }

    // MARK: Failures

    func testFailuresKeepTheLastResultAndTheRun() async {
        let gym = kanto.gyms[0]
        let ok = (GymFixtures.outcomeData(gymID: gym.id, kind: "gym", won: true), 200)
        let cases: [((Data, Int), GymService.Failure)] = [
            ((Data(#"{"ok":false,"error":"rate_limited","retry_after":2.2}"#.utf8), 429), .rateLimited(retryAfter: 2.2)),
            ((Data(#"{"ok":false,"error":"unknown_gym"}"#.utf8), 404), .botTooOld),
            ((Data(#"{"ok":false,"error":"too_many_members"}"#.utf8), 400), .refused("too_many_members")),
            ((Data(), 503), .failed),
            ((GymFixtures.outcomeData(gymID: "kanto-2", kind: "gym", won: true), 200), .failed),
        ]
        for (reply, expected) in cases {
            let service = service(ExchangeScript([ok, reply]))
            await service.fightGym(gym, region: kanto, team: team)
            let before = service.last
            await service.fightGym(gym, region: kanto, team: team)

            XCTAssertEqual(service.failure, expected)
            XCTAssertEqual(service.last, before)
            XCTAssertNil(service.inFlight)
        }
    }

    func testAnUnreachableBotIsAFailureNotACrash() async {
        let service = service(ExchangeScript([]))
        await service.fightGym(kanto.gyms[0], region: kanto, team: team)

        XCTAssertEqual(service.failure, .unreachable)
        XCTAssertNil(service.last)
        XCTAssertTrue(applied.isEmpty)
    }

    func testRejectedTokenDuringAFightDisablesTheSection() async {
        let service = service(ExchangeScript([(Data(), 401)]))
        await service.fightGym(kanto.gyms[0], region: kanto, team: team)

        XCTAssertEqual(service.unavailable, .rejected)
    }

    func testDismissClearsTheResultAndTheFailure() async {
        let gym = kanto.gyms[0]
        let service = service(ExchangeScript([(GymFixtures.outcomeData(gymID: gym.id, kind: "gym", won: false), 200)]))
        await service.fightGym(gym, region: kanto, team: team)
        service.dismissResult()

        XCTAssertNil(service.last)
        XCTAssertNil(service.failure)
    }
}
