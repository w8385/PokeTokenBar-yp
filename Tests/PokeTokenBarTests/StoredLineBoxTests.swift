import XCTest
@testable import PokeTokenBar

private func node(_ id: Int, time: String? = nil, _ children: [EvoNode] = []) -> EvoNode {
    EvoNode(speciesID: id, children: children, methods: [EvoMethod(trigger: "level-up", item: nil, timeOfDay: time)])
}

private struct BoxLineProvider: PokeProviding {
    static let trees: [Int: EvoNode] = [
        4: node(4, [node(5, [node(6)])]),
        704: node(704, [node(705, [node(706)])]),
        236: node(236, [node(106), node(107), node(237)]),
        891: node(891, [node(892)]),
        458: node(458, [node(226)]),
        10: node(10, [node(11, time: "day"), node(12, time: "night")]),
        446: node(446, [node(143)]),
        447: node(447, [node(448, time: "day")]),
    ]

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        let tree = Self.trees[baseSpeciesID] ?? node(baseSpeciesID)
        return EvoLine(baseID: tree.speciesID, tree: tree, rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Shared save and store setup: a raised line, two graduates and lines waiting in the Box.
@MainActor
class StoredLineHarness: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var fed: [ObjectIdentifier: Int] = [:]
    static let lineID = "line"
    static let gradID = "grad"
    static let otherGradID = "other-grad"
    static let keptID = "kept"

    func baseState() -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = .en
        state.claimedTodayTokensByProvider = ["test": 0]
        state.lastDate = "d1"
        state.usedSinceInstall = 90_000_000_000
        var profile = PokemonProfile.generate(seed: 4, instanceID: Self.lineID)
        profile.level = 20
        state.active = MonState(baseID: 4, pathIDs: [4, 5], plannedPathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 3, profile: profile)
        state.dex = [graduate(Self.gradID, species: 25, seed: 11, caught: 1_000),
                     graduate(Self.otherGradID, species: 133, seed: 12, caught: 2_000)]
        state.collectedFinals = ["25:25", "133:133"]
        return state
    }

    func graduate(_ id: String, species: Int, seed: UInt64, caught: TimeInterval) -> DexEntry {
        var profile = PokemonProfile.generate(seed: seed, instanceID: id)
        profile.level = 30
        return DexEntry(id: id, baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                        caughtAt: Date(timeIntervalSince1970: caught), profile: profile)
    }

    func storedMon(_ id: String, path: [Int], stage: Int = 0, seed: UInt64 = 21, used: Int = 0) -> MonState {
        var profile = PokemonProfile.generate(seed: seed, instanceID: id)
        profile.level = 20
        return MonState(baseID: path[0], pathIDs: Array(path.prefix(stage + 1)), plannedPathIDs: path, stageIndex: stage,
                        usedAtStage: used, rarity: .common, totalForms: path.count, nature: .hardy, profile: profile)
    }

    /// The Box record `storeActiveInBox` writes: the line itself plus its released Pokédex record.
    func store(_ mon: MonState, in state: inout CompanionState, holding: Bool = true) {
        let id = mon.profile!.instanceID
        state.storedLines[id] = StoredLine(mon: mon, spentAtStore: state.spentTokens)
        let chain = Array(mon.pathIDs.prefix(mon.stageIndex + 1))
        state.dex.append(DexEntry(id: id, baseID: mon.baseID, finalID: chain.last!, chainOrder: chain, rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 3_000), profile: mon.profile,
                                  releasedAt: Date(timeIntervalSince1970: 3_000)))
        if holding { state.expShareHolders.append(id) }
    }

    func keptState(holding: Bool = false) -> CompanionState {
        var state = baseState()
        store(storedMon(Self.keptID, path: [704, 705, 706]), in: &state, holding: holding)
        return state
    }

    func makeStore(_ state: CompanionState) throws -> CompanionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stored-line-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "stored-line-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(1.0, forKey: "growthDifficulty")
        defaults.set(true, forKey: PokemonBalance.difficultyMigratedKey)
        return CompanionStore(provider: BoxLineProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 3),
                              dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    func feed(_ store: CompanionStore, _ tokens: Int) {
        let total = fed[ObjectIdentifier(store), default: 0] + tokens
        fed[ObjectIdentifier(store)] = total
        store.update(todayTokensByProvider: ["test": total], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
    }

    func storedMon(_ store: CompanionStore, _ id: String) throws -> MonState {
        try XCTUnwrap(store.state.storedLines[id]?.mon)
    }
}

/// A Pokémon waiting in the Box walks with you as a friend, and a shop or scout egg makes the one it sends there a
/// friend while a slot is free.
final class StoredLineFriendsTests: StoredLineHarness {
    func testAStoredLineIsPickedShownAsItIsNowAndRemoved() throws {
        let store = try makeStore(keptState())
        XCTAssertTrue(store.friendCandidates.contains { $0.id == Self.keptID })
        XCTAssertTrue(store.addFriend(entryID: Self.keptID))
        XCTAssertEqual(store.state.friendEntryIDs, [CompanionState.friendKey(storedLine: Self.keptID)])
        XCTAssertEqual(store.friendSubjects.map(\.entryID), [Self.keptID])
        XCTAssertEqual(store.friendSubjects.first?.speciesID, 704)
        XCTAssertFalse(store.friendCandidates.contains { $0.id == Self.keptID })
        XCTAssertFalse(store.addFriend(entryID: Self.keptID), "once")
        let individual = try XCTUnwrap(store.boxIndividual(id: Self.keptID))
        XCTAssertEqual(individual.role, .stored)
        XCTAssertTrue(individual.isFriend)

        store.removeFriend(entryID: Self.keptID)
        XCTAssertEqual(store.state.friendEntryIDs, [])
        XCTAssertEqual(store.friendSubjects, [])
    }

    func testTheRaisedPokemonAndTheActiveLineCannotBeFriends() throws {
        let store = try makeStore(keptState())
        XCTAssertFalse(store.addFriend(entryID: Self.lineID), "the line being raised")
        XCTAssertFalse(store.friendCandidates.contains { $0.id == Self.lineID })
        XCTAssertTrue(store.raise(entryID: Self.gradID))
        XCTAssertFalse(store.addFriend(entryID: Self.gradID), "the raised graduate")
        XCTAssertFalse(store.addFriend(entryID: Self.lineID), "the resting line")
        XCTAssertTrue(store.addFriend(entryID: Self.keptID))
    }

    func testRaisingAStoredFriendDropsItAndKeepsTheGraduateFriend() throws {
        let store = try makeStore(keptState())
        XCTAssertTrue(store.addFriend(entryID: Self.keptID))
        XCTAssertTrue(store.addFriend(entryID: Self.gradID))
        XCTAssertTrue(store.raise(entryID: Self.keptID))
        XCTAssertEqual(store.state.friendEntryIDs, [Self.gradID])
        XCTAssertEqual(store.friendSubjects.map(\.entryID), [Self.gradID])
    }

    func testAStoredFriendWhoseLineLeftTheBoxIsDroppedOnLoad() throws {
        var state = keptState()
        state.friendEntryIDs = [CompanionState.friendKey(storedLine: "gone"), Self.gradID,
                                CompanionState.friendKey(storedLine: Self.keptID)]
        let store = try makeStore(state)
        XCTAssertEqual(store.state.friendEntryIDs, [Self.gradID, CompanionState.friendKey(storedLine: Self.keptID)])
    }

    // MARK: egg and scout swap

    func testAnEggSwapWithAFreeSlotAddsAFriendAndAttachesTheBagCopy() throws {
        var state = baseState()
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try makeStore(state)
        XCTAssertTrue(store.eggSwapAddsFriend)
        XCTAssertTrue(store.buyEgg(nil))
        XCTAssertNotNil(store.state.storedLines[Self.lineID])
        XCTAssertEqual(store.state.friendEntryIDs, [CompanionState.friendKey(storedLine: Self.lineID)])
        XCTAssertEqual(store.friendSubjects.map(\.speciesID), [5])
        XCTAssertTrue(store.holdsExpShare(Self.lineID))
        XCTAssertEqual(store.itemCount(.expShare), 0)
    }

    func testAnEggSwapWithFullSlotsAddsNoFriend() throws {
        var state = baseState()
        state.inventory[ItemKind.expShare.rawValue] = 1
        state.friendEntryIDs = [Self.gradID, Self.otherGradID]
        let store = try makeStore(state)
        XCTAssertFalse(store.eggSwapAddsFriend)
        XCTAssertTrue(store.buyEgg(nil))
        XCTAssertEqual(store.state.friendEntryIDs, [Self.gradID, Self.otherGradID])
        XCTAssertTrue(store.holdsExpShare(Self.lineID), "the Exp. Share still goes with it")
    }

    func testNeitherTheSwapNorTheFriendPickerTakesACopyFromAnotherHolder() throws {
        var state = baseState()
        state.expShareHolders = [Self.gradID]
        let store = try makeStore(state)
        XCTAssertTrue(store.buyEgg(nil))
        XCTAssertTrue(store.state.isFriend(boxID: Self.lineID))
        XCTAssertEqual(store.state.expShareHolders, [Self.gradID])
        XCTAssertTrue(store.removeFriendThenAdd(Self.lineID))
        XCTAssertEqual(store.state.expShareHolders, [Self.gradID])
    }

    // MARK: saves

    func testAnOldSaveDecodesUnchanged() throws {
        var state = keptState(holding: true)
        state.friendEntryIDs = [Self.gradID]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CompanionState.self, from: data)
        XCTAssertEqual(decoded.friendEntryIDs, [Self.gradID])
        XCTAssertEqual(Set(decoded.storedLines.keys), [Self.keptID])
        XCTAssertEqual(decoded.expShareHolders, [Self.keptID])
        let store = try makeStore(state)
        XCTAssertEqual(store.friendSubjects.map(\.entryID), [Self.gradID])
    }

    func testASaveWithAStoredFriendDecodesWithItsFriends() throws {
        var state = keptState()
        state.friendEntryIDs = [CompanionState.friendKey(storedLine: Self.keptID), Self.gradID]
        let decoded = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.friendEntryIDs, state.friendEntryIDs)
        let store = try makeStore(state)
        XCTAssertEqual(store.friendSubjects.map(\.entryID), [Self.keptID, Self.gradID])
    }

    // MARK: moving an Exp. Share

    func testACopyMovesOntoAStoredLineWithAnEmptyBag() throws {
        var state = keptState()
        state.expShareHolders = [Self.gradID]
        let store = try makeStore(state)
        XCTAssertFalse(store.canAttachExpShare(to: Self.keptID))
        XCTAssertEqual(store.expShareMoveSources(to: Self.keptID).map(\.id), [Self.gradID])
        XCTAssertTrue(store.moveExpShare(from: Self.gradID, to: Self.keptID))
        XCTAssertEqual(store.state.expShareHolders, [Self.keptID])
        XCTAssertEqual(store.itemCount(.expShare), 0)
    }

    func testACopyMovesEvenWithAFreeCopyInTheBag() throws {
        var state = keptState()
        state.expShareHolders = [Self.gradID]
        state.inventory[ItemKind.expShare.rawValue] = 1
        let store = try makeStore(state)
        XCTAssertTrue(store.canAttachExpShare(to: Self.otherGradID))
        XCTAssertEqual(store.expShareMoveSources(to: Self.otherGradID).map(\.id), [Self.gradID])
        XCTAssertTrue(store.moveExpShare(from: Self.gradID, to: Self.otherGradID))
        XCTAssertEqual(store.state.expShareHolders, [Self.otherGradID])
        XCTAssertEqual(store.itemCount(.expShare), 1, "the bag copy stays in the bag")
    }

    func testAMoveIsRefusedOntoTheRaisedPokemonOrAHolder() throws {
        var state = keptState()
        state.expShareHolders = [Self.gradID, Self.keptID]
        let store = try makeStore(state)
        XCTAssertEqual(store.expShareMoveSources(to: Self.lineID).map(\.id), [], "being raised")
        XCTAssertFalse(store.moveExpShare(from: Self.gradID, to: Self.lineID))
        XCTAssertEqual(store.expShareMoveSources(to: Self.keptID).map(\.id), [], "already holds one")
        XCTAssertFalse(store.moveExpShare(from: Self.gradID, to: Self.keptID))
        XCTAssertTrue(store.raise(entryID: Self.otherGradID))
        XCTAssertFalse(store.moveExpShare(from: Self.gradID, to: Self.otherGradID), "the raised graduate")
        XCTAssertFalse(store.moveExpShare(from: Self.gradID, to: Self.lineID), "the resting line")
        XCTAssertEqual(store.state.expShareHolders, [Self.gradID, Self.keptID])
    }

    func testAStoredLineKeepsWhatItBankedWhenItsCopyMovesAway() throws {
        let store = try makeStore(keptState(holding: true))
        feed(store, 4_000)
        let banked = try storedMon(store, Self.keptID).usedAtStage
        XCTAssertEqual(banked, 2_000)
        XCTAssertTrue(store.moveExpShare(from: Self.keptID, to: Self.gradID))
        XCTAssertEqual(try storedMon(store, Self.keptID).usedAtStage, banked)
        feed(store, 4_000)
        XCTAssertEqual(try storedMon(store, Self.keptID).usedAtStage, banked, "no share without the item")
    }
}

private extension CompanionStore {
    func removeFriendThenAdd(_ id: String) -> Bool {
        removeFriend(entryID: id)
        return addFriend(entryID: id)
    }
}

/// A stored line holding an Exp. Share takes the steps that open by themselves in the Box; the rest wait.
final class StoredLineEvolutionTests: StoredLineHarness {
    private func threshold(_ mon: MonState) -> Int { PokemonBalance.scaled(mon.phaseThreshold, by: 1.0) }

    func testAStoredHolderCrossesItsStageThresholdAndEvolvesInTheBox() async throws {
        var state = baseState()
        let goomy = storedMon(Self.keptID, path: [704, 705, 706])
        var ready = goomy
        ready.usedAtStage = threshold(goomy) - 2_000
        store(ready, in: &state)
        state.friendEntryIDs = [CompanionState.friendKey(storedLine: Self.keptID)]
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertEqual(try storedMon(store, Self.keptID).currentID, 704)
        let active = store.state.active

        feed(store, 4_002)
        let mon = try storedMon(store, Self.keptID)
        XCTAssertEqual(mon.currentID, 705)
        XCTAssertEqual(mon.usedAtStage, 1)
        XCTAssertEqual(store.boxIndividual(id: Self.keptID)?.role, .stored)
        let record = try XCTUnwrap(store.state.dex.first { $0.id == Self.keptID })
        XCTAssertEqual(record.finalID, 705)
        XCTAssertEqual(record.chainOrder, [704, 705])
        XCTAssertTrue(store.state.ownsSpecies(705), "the Pokédex records the new species")
        XCTAssertEqual(store.friendSubjects.map(\.speciesID), [705])
        XCTAssertNil(store.justEvolvedTo, "no celebration on Home")
        XCTAssertEqual(store.state.active?.currentID, active?.currentID)
    }

    func testAStepThatNeedsAnItemWaitsEvenWithTheItemInTheBag() async throws {
        var state = baseState()
        let kubfu = storedMon("kubfu", path: [891, 892], used: 0)
        var ready = kubfu
        ready.usedAtStage = threshold(kubfu) * 3
        store(ready, in: &state)
        state.inventory[ItemKind.scrollOfDarkness.rawValue] = 1
        let store = try makeStore(state)
        await store.checkExpShareEvolution()
        XCTAssertEqual(try storedMon(store, "kubfu").currentID, 891)
        XCTAssertEqual(store.itemCount(.scrollOfDarkness), 1)
        XCTAssertEqual(store.storedLineGate(id: "kubfu")?.rule.species, 892)
        let entry = try XCTUnwrap(store.boxIndividual(id: "kubfu")?.entry)
        XCTAssertTrue(store.evolutionCards(for: 891, individual: entry).contains { $0.rule.species == 892 && $0.isNextStep },
                      "the Box page shows what the step needs")
    }

    func testAFriendLineStepOpensByItselfInTheBox() async throws {
        var state = baseState()
        var mantyke = storedMon("mantyke", path: [458, 226])
        mantyke.usedAtStage = threshold(mantyke)
        store(mantyke, in: &state)
        state.dex.append(graduate("remoraid", species: 223, seed: 31, caught: 5_000))
        let store = try makeStore(state)
        store.autoMoveOn = false
        await store.checkExpShareEvolution()
        XCTAssertEqual(try storedMon(store, "mantyke").currentID, 458, "no Remoraid walks with you")
        XCTAssertTrue(store.addFriend(entryID: "remoraid"))
        await store.checkExpShareEvolution()
        XCTAssertEqual(try storedMon(store, "mantyke").currentID, 226)
    }

    func testTheClockPicksTheBoxBranchAndATimeOnlyPathOpensInItsPeriod() async throws {
        let calendar = Calendar.current
        let day = calendar.date(bySettingHour: 12, minute: 5, second: 0, of: now)!
        let night = calendar.date(bySettingHour: 12, minute: 15, second: 0, of: now)!
        for (clock, species) in [(day, 11), (night, 12)] {
            now = clock
            var state = baseState()
            var caterpie = storedMon("caterpie", path: [10, 11])
            caterpie.usedAtStage = threshold(caterpie)
            store(caterpie, in: &state)
            let store = try makeStore(state)
            await store.checkExpShareEvolution()
            XCTAssertEqual(try storedMon(store, "caterpie").currentID, species, "\(DayPeriod.at(clock))")
        }

        let timeOnly = EvolutionRule(species: 1, covers: [], original: [], paths: [[.time(.night)]])
        var context = EvolutionContext()
        context.period = DayPeriod.at(day)
        XCTAssertNil(timeOnly.pathOpenByItself(in: context))
        context.period = DayPeriod.at(night)
        XCTAssertNotNil(timeOnly.pathOpenByItself(in: context))
    }

    func testABranchPicksTheWayTheRaisedLineWould() async throws {
        for seed in 21...26 as ClosedRange<UInt64> {
            let probe = storedMon("tyrogue", path: [236, 106], seed: seed)
            let traits = EvolutionTraits(seed: probe.profile!.seed, ivs: probe.profile!.ivs, nature: probe.nature)
            let wrong = try XCTUnwrap([106, 107, 237].first { EvolutionRules.rule(for: $0)?.selector?.matches(traits) == false })
            var mon = storedMon("tyrogue", path: [236, wrong], seed: seed)
            mon.usedAtStage = threshold(mon)

            var raisedState = baseState()
            raisedState.active = mon
            let raised = try makeStore(raisedState)
            feed(raised, 0)
            try await waitUntil("the raised line to load") { raised.currentLine != nil }
            raised.applyUsage(0)
            let raisedSpecies = try XCTUnwrap(raised.state.active?.currentID)
            XCTAssertNotEqual(raisedSpecies, 236, "seed \(seed)")

            var storedState = baseState()
            store(mon, in: &storedState)
            let stored = try makeStore(storedState)
            await stored.checkExpShareEvolution()
            XCTAssertEqual(try storedMon(stored, "tyrogue").currentID, raisedSpecies, "seed \(seed)")
            XCTAssertNotEqual(raisedSpecies, wrong, "seed \(seed)")
        }
    }
}
