import XCTest
@testable import PokeTokenBar

/// Pins the companion save file: every field of `CompanionState` set, encoded, compared with a stored JSON fixture,
/// and read back through `CompanionStore`. A refactor that renames a key or drops a field fails here.
@MainActor
final class SaveFormatPinTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testEncodingAFullStateMatchesTheFixture() throws {
        XCTAssertEqual(try object(JSONEncoder().encode(Self.fullState())), try fixtureObject())
    }

    func testTheFixtureDecodesAndEncodesUnchanged() throws {
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(SaveFormatFixture.json.utf8))
        XCTAssertEqual(try object(JSONEncoder().encode(state)), try fixtureObject())
    }

    func testTheFixtureSetsEveryField() throws {
        let fixture = try XCTUnwrap(fixtureObject() as? [String: Any])
        let fields = Mirror(reflecting: CompanionState()).children.compactMap(\.label)
        XCTAssertEqual(Set(fixture.keys), Set(fields))
        for (key, value) in fixture {
            if let list = value as? [Any] { XCTAssertFalse(list.isEmpty, key) }
            if let map = value as? [String: Any] { XCTAssertFalse(map.isEmpty, key) }
        }
    }

    /// Loading settles what the full state leaves inconsistent (egg fields beside an active line, profile growth),
    /// so the store writes `SaveFormatFixture.savedJSON`.
    func testTheStoreLoadsTheFixtureAndSavesTheSettledState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-pin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "save-pin-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        let url = directory.appendingPathComponent("companion-state.json")
        try Data(SaveFormatFixture.json.utf8).write(to: url)

        let store = CompanionStore(provider: SavePinProvider(), clock: { Self.now }, fileURL: url,
                                   rng: SeededRNG(seed: 3), dittoDisguiseRollingEnabled: false, defaults: defaults)
        XCTAssertEqual(store.state.spentTokens, 30_000_000)
        XCTAssertEqual(store.availableTokens, 900_000_000 + 5_000_000 - 30_000_000)
        XCTAssertEqual(store.state.dex.count, 3)
        store.save()

        XCTAssertEqual(try object(Data(contentsOf: url)), try object(Data(SaveFormatFixture.savedJSON.utf8)))
    }

    private func fixtureObject() throws -> NSObject { try object(Data(SaveFormatFixture.json.utf8)) }

    private func object(_ data: Data) throws -> NSObject {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSObject)
    }

    static func fullState() -> CompanionState {
        var profile = PokemonProfile.generate(seed: 11, instanceID: "line-1")
        profile.abilityName = "static"
        profile.mirrorHerb = true
        var evolution = EvolutionProgress(spentBaseline: 1_000_000, seenBattles: ["b-1"], battleCursor: now)
        evolution.pets = 3
        evolution.tower = "waters"
        evolution.stuckNotified = "level"
        var active = MonState(baseID: 25, pathIDs: [172, 25], plannedPathIDs: [172, 25, 26], stageIndex: 1,
                              usedAtStage: 4_000, rarity: .uncommon, totalForms: 3, isShiny: true, nature: .jolly,
                              profile: profile, hasGrowthBoost: true, dittoDisguise: 25, dittoRevealed: true,
                              prayers: PrayerRecord(count: 2), tradeGated: true)
        active.evolution = evolution

        let graduate = DexEntry(id: "grad-1", baseID: 4, finalID: 6, chainOrder: [4, 5, 6], rarity: .rare,
                                caughtAt: now, isShiny: false, nature: .bold,
                                profile: PokemonProfile.generate(seed: 12, instanceID: "grad-1"),
                                names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"], 6: ["en": "Charizard"]],
                                prayers: PrayerRecord(count: 1), originalTrainer: "Trainer")
        var stored = DexEntry(id: "stored-1", baseID: 1, finalID: 2, chainOrder: [1, 2], rarity: .common,
                              caughtAt: now, profile: PokemonProfile.generate(seed: 13, instanceID: "stored-1"),
                              releasedAt: now)
        stored.tradeHeldItem = "metalCoat"
        let unown = DexEntry(id: "grad-2", baseID: 201, finalID: 201, chainOrder: [201], rarity: .uncommon,
                             caughtAt: now, profile: PokemonProfile.generate(seed: 14, instanceID: "grad-2"),
                             names: [201: ["en": "Unown"]], form: PokemonForm(rawValue: "c"))
        let storedMon = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 50, rarity: .common,
                                 totalForms: 3, nature: .calm,
                                 profile: PokemonProfile.generate(seed: 13, instanceID: "stored-1"))

        var badges = GymBadges()
        badges.update("kanto") { $0.gyms = [1]; $0.hallOfFame = true }

        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = 900_000_000
        state.spentTokens = 30_000_000
        state.eggUsage = 1_200
        state.clickGrowth = 77
        state.eggTier = .rare
        state.pendingHatchID = 201
        state.pendingForm = PokemonForm(rawValue: "b")
        state.eggPrayers = PrayerRecord(count: 4)
        state.claimedTodayTokensByProvider = ["claude_code": 123]
        state.lastDate = "2023-11-14"
        state.active = active
        state.representativeSpeciesID = 201
        state.representativeForm = PokemonForm(rawValue: "c")
        state.friendEntryIDs = ["grad-2"]
        state.raisedEntryID = "grad-1"
        state.parkedSpentTokens = 20_000_000
        state.graduateEvolution = ["grad-1": EvolutionProgress(spentBaseline: 20_000_000)]
        state.storedLines = ["stored-1": StoredLine(mon: storedMon, spentAtStore: 10_000_000)]
        state.expShareHolders = ["grad-1"]
        state.expShareTakenOff = ["stored-1"]
        state.stuckWatch = StuckWatch(id: "grad-1", since: now)
        state.keepWaiting = ["grad-1": 6]
        state.dex = [graduate, stored, unown]
        state.collectedFinals = ["4-6"]
        state.language = .ko
        state.inventory = ["rareCandy": 3, "mint": 1]
        state.scoutDraws = ["kanto": [1, 4, 7]]
        state.scoutedEgg = true
        state.shinyEgg = true
        state.heldItems = ["grad-1": "leftovers"]
        state.candyGrantTier = ["five_hour": 2]
        state.candyWindowEpoch = ["five_hour": "2023-11-14T10:00:00Z"]
        state.candyFeatureSeeded = true
        state.notifiedDexCompletions = ["kanto"]
        state.dexCompletionsSeeded = true
        state.rewardedDexRegions = ["kanto"]
        state.appliedTradeIDs = ["trade-1"]
        state.remoteOpsLastID = 42
        state.remoteOpResults = [RemoteOpResult(id: 41, reason: "no_tokens")]
        state.remoteOpsEpoch = "epoch-1"
        state.growthMode = .time
        state.timeCredit = 5_000_000
        state.tokenModeSince = now
        state.lastUsageAt = now
        state.idleHintDismissed = true
        state.leftoverEvolutionItemsReturned = true
        state.urshifuStylesRepaired = true
        state.unearnedTradeStepsReverted = true
        state.gymBadges = badges
        state.tower.bp = 120
        state.tower.entry = ["grad-1", "grad-2", "stored-1"]
        state.tower.records = ["entry": TowerModeRecord(streak: 3, best: 25, trophies: ["silver"]),
                               "rental": TowerModeRecord(best: 4)]
        return state
    }
}

private struct SavePinProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}
