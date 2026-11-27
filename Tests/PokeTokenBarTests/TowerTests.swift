import XCTest
@testable import PokeTokenBar

private struct TowerProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Bot-shaped tower replies, as `bot/ypoke/tower_battle.py` writes them.
enum TowerFixtures {
    static func run(_ mode: String = "entry", streak: Int, best: Int, trophies: [String] = [],
                    extra: [String: Any] = [:]) -> [String: Any] {
        let battle = streak + 1
        let set = (battle - 1) / 10 + 1
        var run: [String: Any] = ["mode": mode, "streak": streak, "best": best, "trophies": trophies,
                                  "next": ["battle": battle, "set": set, "owner": battle == 20 || battle == 50]]
        run.merge(extra) { _, new in new }
        return run
    }

    static func fighter(_ id: Int, hp: Int) -> [String: Any] {
        ["pokemon_id": id, "name": "#\(id)", "level": 50, "types": ["normal"], "shiny": false, "hp": hp]
    }

    static func battle(won: Bool, battle: Int, best: Int, bp: Int, trophy: String? = nil, mode: String = "entry",
                       extra: [String: Any] = [:]) -> Data {
        let streak = won ? battle : 0
        var tower = run(mode, streak: streak, best: best, trophies: trophy.map { [$0] } ?? [], extra: extra)
        tower["battle"] = battle
        tower["set"] = (battle - 1) / 10 + 1
        tower["bp"] = bp
        tower["trophy"] = trophy ?? NSNull()
        let trainer: [String: Any] = trophy == nil
            ? ["name": ["ko": "등반가 하람", "en": "Climber Haram", "ja": "クライマーのハラム"],
               "line": ["ko": "정상까지 같이 가 볼까?", "en": "Shall we climb to the top together?", "ja": "頂上まで一緒に行こうか？"]]
            : ["name": ["ko": "타워 주인 솔라", "en": "Tower Keeper Sola", "ja": "タワーキーパーのソラ"],
               "line": ["ko": "여기까지 올라온 건 오랜만이야.", "en": "It's been a while since anyone climbed this far.",
                        "ja": "ここまで来たのは久しぶりだね。"]]
        let kind = trophy == nil ? "tower" : "tower-owner"
        let sprite = trophy == nil ? "tower-1" : "tower-owner"
        let body: [String: Any] = [
            "ok": true, "gym_id": sprite, "kind": kind, "trainer": trainer, "won": won, "turns": 7, "seed": 11,
            "player_team": [fighter(25, hp: won ? 40 : 0), fighter(6, hp: won ? 100 : 0), fighter(9, hp: won ? 100 : 0)],
            "foe_team": [fighter(143, hp: won ? 0 : 50), fighter(130, hp: won ? 0 : 100), fighter(65, hp: won ? 0 : 100)],
            "log": [["turn": 1, "lines": [["side": 0, "text": "…"]]]], "events": [], "run": NSNull(),
            "opponent": ["id": sprite, "kind": kind, "index": battle, "types": [], "level": 50, "trainer": trainer,
                         "team": [143, 130, 65], "finale": 0, "run": NSNull()],
            "tower": tower,
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func record(entry: [String: Any], rental: [String: Any],
                       ranking: [String: Any] = ["entry": [["name": "두리", "best": 30]], "rental": []]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["ok": true, "modes": ["entry": entry, "rental": rental],
                                                     "ranking": ranking])
    }

    static func entry(_ species: Int, id: String) -> DexEntry {
        var profile = PokemonProfile.generate(seed: 7, instanceID: id)
        profile.level = 30
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common, caughtAt: nil,
                             profile: profile)
        entry.id = id
        return entry
    }
}

/// Replies by path, and the requests it saw.
final class TowerFakeBot: @unchecked Sendable {
    var replies: [String: [(Data, Int)]] = [:]
    var requests: [URLRequest] = []

    var exchange: GymService.Exchange {
        { [self] request in
            requests.append(request)
            let path = request.url!.path
            guard var queue = replies[path], !queue.isEmpty else { return (Data(), 500) }
            let reply = queue.removeFirst()
            replies[path] = queue.isEmpty ? [reply] : queue
            return reply
        }
    }

    func body(of index: Int) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[index].httpBody)) as? [String: Any])
    }
}

@MainActor
final class TowerTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tower-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func store(_ state: CompanionState = CompanionState()) throws -> CompanionStore {
        var state = state
        state.installBaselineSet = true
        let file = scratch.appendingPathComponent("state-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: TowerProvider(), fileURL: file)
    }

    private func service(_ bot: TowerFakeBot, store: CompanionStore) -> TowerService {
        TowerService(link: { GymService.Link(server: "http://bot-host:8790", token: "synthetic") }, exchange: bot.exchange,
                     apply: { run, gain in store.applyTower(run, gain: gain) })
    }

    private func reload(_ store: CompanionStore) -> CompanionStore {
        CompanionStore(provider: TowerProvider(), fileURL: store.fileURL)
    }

    // MARK: Save

    func testASaveFromBeforeTheTowerDecodesWithNoBPAndNoRecords() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(CompanionState())) as? [String: Any])
        json.removeValue(forKey: "tower")
        let old = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.tower, TowerProgress())
    }

    func testABrokenTowerFieldKeepsTheRestOfTheSaveAndRepairsItself() throws {
        let tower = #"{"bp": -5, "entry": ["a", "a", "b", "c", "d"], "records": {"entry": {"streak": 9, "best": 2}}}"#
        let progress = try JSONDecoder().decode(TowerProgress.self, from: Data(tower.utf8))
        XCTAssertEqual(progress.bp, 0)
        XCTAssertEqual(progress.entry, ["a", "b", "c"])
        XCTAssertEqual(progress.record(.entry), TowerModeRecord(streak: 9, best: 9))
        let huge = try JSONDecoder().decode(TowerProgress.self, from: Data(#"{"bp": 5000000}"#.utf8))
        XCTAssertEqual(huge.bp, TowerProgress.maxBP)
        let broken = #"{"tower": "nonsense", "gymBadges": {"regions": {"kanto": {"gyms": [1]}}}}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(broken.utf8))
        XCTAssertEqual(state.tower, TowerProgress())
        XCTAssertTrue(state.gymBadges.hasGymBadge("kanto", index: 1))
    }

    // MARK: Replies

    func testABattleReplyDecodesAsAGymOutcomeWithTheRunAndWhatItPaid() throws {
        let outcome = try TowerOutcome.decode(TowerFixtures.battle(won: true, battle: 20, best: 20, bp: 10, trophy: "silver"))
        XCTAssertTrue(outcome.battle.won)
        XCTAssertEqual(outcome.battle.gymId, "tower-owner")
        XCTAssertEqual(outcome.opponent.team, [143, 130, 65])
        XCTAssertEqual(outcome.run.streak, 20)
        XCTAssertEqual(outcome.run.next, TowerRun.Next(battle: 21, set: 3, owner: false))
        XCTAssertEqual(outcome.gain, TowerGain(battle: 20, set: 2, bp: 10, trophy: "silver"))
    }

    // MARK: Entry

    func testTheEntryTeamNeedsThreeOwnedPokemonOfDifferentSpecies() {
        var state = CompanionState()
        state.dex = [TowerFixtures.entry(25, id: "a"), TowerFixtures.entry(6, id: "b"), TowerFixtures.entry(9, id: "c"),
                     TowerFixtures.entry(25, id: "d")]
        XCTAssertEqual(TowerEntry.team(state: state, ids: ["a", "b", "c"], moveChoices: [:])?.map(\.pokemonID), [25, 6, 9])
        XCTAssertNil(TowerEntry.team(state: state, ids: ["a", "b"], moveChoices: [:]))
        XCTAssertNil(TowerEntry.team(state: state, ids: ["a", "b", "d"], moveChoices: [:]))
        XCTAssertNil(TowerEntry.team(state: state, ids: ["a", "b", "gone"], moveChoices: [:]))
        XCTAssertEqual(TowerEntry.sameSpecies(state: state, ids: ["a", "b"], replacing: "b"), ["d"])
        XCTAssertEqual(TowerEntry.sameSpecies(state: state, ids: ["a", "b"], replacing: "a"), [])
    }

    func testTheEntryIsSavedApartFromTheBattleEntryAndLockedWhileARunIsLive() throws {
        var state = CompanionState()
        state.dex = [TowerFixtures.entry(25, id: "a"), TowerFixtures.entry(6, id: "b"), TowerFixtures.entry(9, id: "c")]
        let store = try store(state)
        store.setTowerEntry("a", at: 0)
        store.setTowerEntry("b", at: 1)
        store.setTowerEntry("gone", at: 2)
        XCTAssertEqual(reload(store).state.tower.entry, ["a", "b"])
        store.state.tower.records["entry"] = TowerModeRecord(streak: 4, best: 4)
        store.setTowerEntry("c", at: 2)
        XCTAssertEqual(store.state.tower.entry, ["a", "b"], "a live run keeps its team")
    }

    // MARK: Service

    func testAWinMirrorsTheRunAndAddsItsBPToTheSaveOnce() async throws {
        let store = try store()
        let bot = TowerFakeBot()
        bot.replies["/v1/tower/battle"] = [(TowerFixtures.battle(won: true, battle: 20, best: 20, bp: 10, trophy: "silver"), 200)]
        let service = service(bot, store: store)
        let team = [PartyMember(pokemonID: 25, level: 30, shiny: false, ivs: nil)]
        await service.fight(.entry, team: team)
        XCTAssertEqual(try bot.body(of: 0)["mode"] as? String, "entry")
        XCTAssertEqual((try bot.body(of: 0)["team"] as? [[String: Any]])?.first?["pokemon_id"] as? Int, 25)
        XCTAssertNotNil(service.last)
        let saved = reload(store).state.tower
        XCTAssertEqual(saved.bp, 10)
        XCTAssertEqual(saved.record(.entry), TowerModeRecord(streak: 20, best: 20, trophies: ["silver"]))
        await service.load()
        XCTAssertEqual(store.state.tower.bp, 10, "loading the record never pays BP")
    }

    func testALossEndsTheStreakKeepsTheBestAndPaysNothing() async throws {
        var state = CompanionState()
        state.tower.bp = 7
        state.tower.records["entry"] = TowerModeRecord(streak: 5, best: 12)
        let store = try store(state)
        let bot = TowerFakeBot()
        bot.replies["/v1/tower/battle"] = [(TowerFixtures.battle(won: false, battle: 6, best: 12, bp: 0), 200)]
        await service(bot, store: store).fight(.entry, team: [])
        XCTAssertEqual(store.state.tower.bp, 7)
        XCTAssertEqual(store.state.tower.record(.entry), TowerModeRecord(streak: 0, best: 12))
        XCTAssertFalse(store.state.tower.entryLocked)
    }

    func testARentalBattleSendsNoTeam() async throws {
        let store = try store()
        let bot = TowerFakeBot()
        bot.replies["/v1/tower/battle"] = [(TowerFixtures.battle(won: true, battle: 1, best: 1, bp: 1, mode: "rental"), 200)]
        await service(bot, store: store).fight(.rental, team: [PartyMember(pokemonID: 25, level: 30, shiny: false, ivs: nil)])
        XCTAssertEqual(try bot.body(of: 0)["mode"] as? String, "rental")
        XCTAssertNil(try bot.body(of: 0)["team"])
        XCTAssertEqual(store.state.tower.record(.rental).streak, 1)
    }

    func testARunTheBotKeptElsewhereIsReadBackAfterA409() async throws {
        let store = try store()
        let bot = TowerFakeBot()
        bot.replies["/v1/tower/battle"] = [(Data(#"{"ok": false, "error": "team_locked"}"#.utf8), 409)]
        bot.replies["/v1/tower/record"] = [(TowerFixtures.record(entry: TowerFixtures.run(streak: 8, best: 8),
                                                                 rental: TowerFixtures.run("rental", streak: 0, best: 3)), 200)]
        let service = service(bot, store: store)
        await service.fight(.entry, team: [])
        XCTAssertEqual(service.failure, .refused("team_locked"))
        XCTAssertEqual(store.state.tower.record(.entry).streak, 8)
        XCTAssertEqual(store.state.tower.record(.rental).best, 3)
        XCTAssertEqual(service.ranking[.entry], [TowerRank(name: "두리", best: 30)])
        XCTAssertNotEqual(store.l.towerFailure(.refused("team_locked")), store.l.gymFailure(.refused("team_locked")))
    }

    func testQuittingEndsTheRunAndFreesTheEntry() async throws {
        var state = CompanionState()
        state.tower.records["entry"] = TowerModeRecord(streak: 3, best: 3)
        let store = try store(state)
        let bot = TowerFakeBot()
        bot.replies["/v1/tower/quit"] = [(try JSONSerialization.data(withJSONObject: TowerFixtures.run(streak: 0, best: 3)), 200)]
        await service(bot, store: store).quit(.entry)
        XCTAssertEqual(try bot.body(of: 0)["mode"] as? String, "entry")
        XCTAssertFalse(store.state.tower.entryLocked)
    }

    // MARK: Rental

    static func rentals(_ ids: [Int], item: String? = "life-orb") -> [[String: Any]] {
        ids.map { ["pokemon_id": $0, "moves": [85, 89], "held_item": item ?? NSNull(), "ivs": 15, "nature": NSNull()] }
    }

    private func reply(_ run: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: run)
    }

    func testARentalRunGetsSixPicksThreeAndSwapsOneAfterAWin() async throws {
        let store = try store()
        let bot = TowerFakeBot()
        let offer = Self.rentals([25, 6, 9, 3, 143, 130])
        bot.replies["/v1/tower/rental"] = [
            (try reply(TowerFixtures.run("rental", streak: 0, best: 0, extra: ["offer": offer])), 200),
            (try reply(TowerFixtures.run("rental", streak: 0, best: 0, extra: ["team": Self.rentals([6, 143, 9])])), 200),
            (try reply(TowerFixtures.run("rental", streak: 1, best: 1, extra: ["team": Self.rentals([65, 143, 9])])), 200),
        ]
        let service = service(bot, store: store)
        await service.rental()
        XCTAssertEqual(service.runs[.rental]?.offer?.map(\.pokemonId), [25, 6, 9, 3, 143, 130])
        XCTAssertEqual(try bot.body(of: 0).count, 0)

        await service.rental(.pick([1, 4, 2]))
        XCTAssertEqual(try bot.body(of: 1)["pick"] as? [Int], [1, 4, 2])
        XCTAssertNil(service.runs[.rental]?.offer)
        XCTAssertEqual(service.runs[.rental]?.team?.map(\.pokemonId), [6, 143, 9])

        await service.rental(.swap(give: 0, take: 2))
        XCTAssertEqual(try bot.body(of: 2)["swap"] as? [String: Int], ["give": 0, "take": 2])
        XCTAssertEqual(service.runs[.rental]?.team?.first?.pokemonId, 65)
        XCTAssertEqual(store.state.tower.record(.rental).streak, 1)
    }

    func testAWonRentalBattleOpensTheSwapWithTheBeatenTrainersTeam() throws {
        let data = TowerFixtures.battle(won: true, battle: 3, best: 3, bp: 1, mode: "rental",
                                        extra: ["team": Self.rentals([6, 143, 9]), "beaten": Self.rentals([65, 130, 3])])
        let outcome = try TowerOutcome.decode(data)
        XCTAssertEqual(outcome.run.beaten?.map(\.pokemonId), [65, 130, 3])
    }

    func testARentalsHeldItemIsTheAppsItemOrMegaStoneByItsSlug() throws {
        let decode = { (item: String?) throws -> HeldItemRef? in
            let data = try JSONSerialization.data(withJSONObject: Self.rentals([25], item: item)[0])
            return try TowerJSON.decoder.decode(TowerRental.self, from: data).item
        }
        XCTAssertEqual(try decode("life-orb"), .item(.lifeOrb))
        XCTAssertEqual(try decode("metagrossite"), MegaStone.stone(slug: "metagrossite").map { .stone($0) })
        XCTAssertNotNil(try decode("metagrossite"))
        XCTAssertNil(try decode(nil))
        XCTAssertNil(try decode("not-an-item"))
    }

    func testEveryItemTheBotCanHandARentalHasAnAppIcon() throws {
        let items = GymRepo.trainerAssets.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("bot/ypoke/items.py")
        let source = try String(contentsOf: items, encoding: .utf8)
        let slugs = source.split(separator: "\n").compactMap { line -> String? in
            guard let match = line.firstMatch(of: /^[A-Z_]+ = "([a-z0-9-]+)"$/) else { return nil }
            return String(match.1)
        }
        XCTAssertFalse(slugs.isEmpty)
        let known = Set(ItemKind.allCases.compactMap(\.heldItemSlug))
        XCTAssertEqual(slugs.filter { !known.contains($0) && MegaStone.stone(slug: $0) == nil }, [])
    }

    func testABotWithoutTheTowerSaysSo() async throws {
        let store = try store()
        let bot = TowerFakeBot()
        bot.replies["/v1/tower/record"] = [(Data(#"{"ok": false, "error": "not_found"}"#.utf8), 404)]
        let service = service(bot, store: store)
        await service.load()
        XCTAssertEqual(service.unavailable, .botTooOld)
    }
}
