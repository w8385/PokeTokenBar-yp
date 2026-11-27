import XCTest
@testable import PokeTokenBar

private func levelUp(_ id: Int, _ children: [EvoNode] = []) -> EvoNode {
    EvoNode(speciesID: id, children: children, methods: [EvoMethod(trigger: "level-up")])
}

private struct LeftoverProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        switch baseSpeciesID {
        case 704:
            return EvoLine(baseID: 704, tree: levelUp(704, [levelUp(705, [levelUp(706)])]), rarity: .common,
                           names: [704: ["en": "Goomy"], 705: ["en": "Sliggoo"], 706: ["en": "Goodra"]])
        case 25:
            return EvoLine(baseID: 25, tree: levelUp(25), rarity: .common, names: [25: ["en": "Pikachu"]])
        case 150:
            return EvoLine(baseID: 150, tree: levelUp(150), rarity: .legendary, names: [150: ["en": "Mewtwo"]])
        default:
            return EvoLine(baseID: 4, tree: levelUp(4, [levelUp(5, [levelUp(6)])]), rarity: .common,
                           names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"], 6: ["en": "Charizard"]])
        }
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Rare Candy XP past graduation goes in full to the Exp. Share holders instead of being discarded.
@MainActor
final class CandyLeftoverExpShareTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    nonisolated(unsafe) private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let lineID = "line"
    private static let pikachuID = "pika"
    private static let sliggooID = "sliggoo"

    private func state(holders: [String], usedAtStage: Int = 0, candies: Int = 3,
                       language: AppLanguage = .en) -> CompanionState {
        var state = CompanionState()
        state.installBaselineSet = true
        state.language = language
        state.claimedTodayTokensByProvider = ["test": 0]
        state.lastDate = "d1"
        state.usedSinceInstall = 90_000_000_000
        var profile = PokemonProfile.generate(seed: 4, instanceID: Self.lineID)
        profile.level = 20
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 1, usedAtStage: usedAtStage, rarity: .common,
                                totalForms: 3, profile: profile)
        var pikachu = PokemonProfile.generate(seed: 11, instanceID: Self.pikachuID)
        pikachu.level = 30
        var sliggoo = PokemonProfile.generate(seed: 12, instanceID: Self.sliggooID)
        sliggoo.level = 40
        state.dex = [
            DexEntry(id: Self.pikachuID, baseID: 25, finalID: 25, chainOrder: [25], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_000), profile: pikachu, names: [25: ["en": "Pikachu"]]),
            DexEntry(id: Self.sliggooID, baseID: 704, finalID: 705, chainOrder: [704, 705], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 2_000), profile: sliggoo,
                     names: [704: ["en": "Goomy"], 705: ["en": "Sliggoo"]]),
        ]
        state.collectedFinals = ["25:25", "704:705"]
        state.expShareHolders = holders
        state.inventory[ItemKind.rareCandy.rawValue] = candies
        return state
    }

    private func makeStore(_ state: CompanionState) async throws -> CompanionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("candy-leftover-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let url = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "candy-leftover-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = CompanionStore(provider: LeftoverProvider(), clock: { self.now }, fileURL: url,
                                   rng: SeededRNG(seed: 3), dittoDisguiseRollingEnabled: false, defaults: defaults)
        await store.loadCurrentLine()
        await store.checkExpShareEvolution()
        return store
    }

    private func entry(_ store: CompanionStore, _ id: String) throws -> DexEntry {
        try XCTUnwrap(store.state.dex.first { $0.id == id })
    }

    private func growth(_ store: CompanionStore, _ id: String) throws -> Int {
        try XCTUnwrap(entry(store, id).profile?.growthTokens)
    }

    private func graduatingLeftover(_ store: CompanionStore) throws -> Int {
        let preview = try XCTUnwrap(store.planRareCandyUse(count: 3))
        XCTAssertTrue(preview.graduates)
        XCTAssertGreaterThan(preview.discardedXP, 0)
        return preview.discardedXP
    }

    func testGraduationLeftoverGoesInFullToTheOnlyHolder() async throws {
        let store = try await makeStore(state(holders: [Self.pikachuID]))
        let plain = try await makeStore(state(holders: []))
        let leftover = try graduatingLeftover(store)
        let before = try growth(store, Self.pikachuID)
        XCTAssertEqual(store.candyLeftoverRecipientCount, 1)

        XCTAssertEqual(store.useRareCandy(count: 3), .graduated)
        XCTAssertEqual(plain.useRareCandy(count: 3), .graduated)

        XCTAssertEqual(try growth(store, Self.pikachuID), before + leftover, "not halved by the share divisor")
        XCTAssertEqual(store.rareCandyCount, plain.rareCandyCount, "the holder takes no extra candy")
        XCTAssertEqual(store.candyLeftoverShared?.xp, leftover)
        XCTAssertEqual(store.candyLeftoverShared?.holders, 1)
    }

    func testThePickerNamesTheHoldersAndWarnsOnlyWithoutThem() async throws {
        let expected: [AppLanguage: (shared: String, wasted: String)] = [
            .ko: ("졸업 시 남는 경험치 12.5M XP → 학습장치 2마리", "졸업 시 남는 12.5M XP는 사라져요."),
            .en: ("On graduation, leftover 12.5M XP → 2 Exp. Share holders",
                  "On graduation, 12.5M leftover XP will be discarded."),
            .ja: ("卒業時の余り経験値 12.5M XP → がくしゅうそうち 2匹", "卒業時、余った12.5M XPは失われます。"),
        ]
        for (language, lines) in expected {
            let shared = try await makeStore(state(holders: [Self.pikachuID, Self.sliggooID], language: language))
            let alone = try await makeStore(state(holders: [], language: language))
            let sharedLine = try XCTUnwrap(shared.candyLeftoverLine(for: XCTUnwrap(shared.planRareCandyUse(count: 3))))
            let aloneLine = try XCTUnwrap(alone.candyLeftoverLine(for: XCTUnwrap(alone.planRareCandyUse(count: 3))))
            XCTAssertEqual(sharedLine.text, lines.shared)
            XCTAssertFalse(sharedLine.wasted)
            XCTAssertEqual(aloneLine.text, lines.wasted)
            XCTAssertTrue(aloneLine.wasted)
        }
    }

    func testThePickerHasNoLeftoverLineBeforeGraduation() async throws {
        var legendary = state(holders: [Self.pikachuID])
        legendary.active = MonState(baseID: 150, pathIDs: [150], stageIndex: 0, usedAtStage: 0, rarity: .legendary,
                                    totalForms: 1, profile: PokemonProfile.generate(seed: 5, instanceID: Self.lineID))
        let store = try await makeStore(legendary)
        XCTAssertNil(store.candyLeftoverLine(for: try XCTUnwrap(store.planRareCandyUse(count: 1))))
    }

    func testTheHomeLineSaysWhereTheLeftoverWentUntilTheEventEnds() async throws {
        let expected: [AppLanguage: String] = [
            .ko: "남은 경험치 12.5M XP를 학습장치 2마리에게 나눠줬어요.",
            .en: "Leftover 12.5M XP went to 2 Exp. Share holders.",
            .ja: "余った経験値 12.5M XPをがくしゅうそうちの2匹に分けました。",
        ]
        for (language, line) in expected {
            let store = try await makeStore(state(holders: [Self.pikachuID, Self.sliggooID], language: language))
            XCTAssertNil(store.candyLeftoverHomeLine)
            XCTAssertEqual(store.useRareCandy(count: 3), .graduated)
            XCTAssertEqual(store.candyLeftoverHomeLine, line)

            now = now.addingTimeInterval(60)
            XCTAssertTrue(store.expireEventWindow())
            XCTAssertNil(store.candyLeftoverHomeLine)
        }
    }

    func testTheNextGraduationWithoutCandyClearsTheLeftoverLine() async throws {
        let store = try await makeStore(state(holders: [Self.pikachuID]))
        XCTAssertEqual(store.useRareCandy(count: 3), .graduated)
        XCTAssertNotNil(store.candyLeftoverShared)

        var profile = PokemonProfile.generate(seed: 6, instanceID: "next")
        profile.level = 20
        store.state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], stageIndex: 2, usedAtStage: 0, rarity: .common,
                                      totalForms: 3, profile: profile)
        await store.loadCurrentLine()
        store.applyUsage(PokemonBalance.graduationTotal(.common))

        XCTAssertNil(store.state.active)
        XCTAssertNotNil(store.justGraduated)
        XCTAssertNil(store.candyLeftoverShared)
    }

    func testAnOddLeftoverSplitsEvenlyWithTheRemainderToTheFirstHolder() async throws {
        for order in [[Self.sliggooID, Self.pikachuID], [Self.pikachuID, Self.sliggooID]] {
            let store = try await makeStore(state(holders: order, usedAtStage: 1))
            let leftover = try graduatingLeftover(store)
            XCTAssertEqual(leftover % 2, 1)
            let before = try order.map { try growth(store, $0) }

            XCTAssertEqual(store.useRareCandy(count: 3), .graduated)

            XCTAssertEqual(try growth(store, order[0]), before[0] + leftover / 2 + 1)
            XCTAssertEqual(try growth(store, order[1]), before[1] + leftover / 2)
            XCTAssertEqual(store.candyLeftoverShared?.holders, 2)
        }
    }

    func testWithoutHoldersTheLeftoverIsDiscardedAsBefore() async throws {
        let store = try await makeStore(state(holders: []))
        _ = try graduatingLeftover(store)
        let before = try [Self.pikachuID, Self.sliggooID].map { try growth(store, $0) }
        XCTAssertEqual(store.candyLeftoverRecipientCount, 0)

        XCTAssertEqual(store.useRareCandy(count: 3), .graduated)

        XCTAssertEqual(try [Self.pikachuID, Self.sliggooID].map { try growth(store, $0) }, before)
        XCTAssertNil(store.candyLeftoverShared)
    }

    func testAHolderAtTheTokenCapLosesItsPartWithoutPassingItOn() async throws {
        var capped = state(holders: [Self.pikachuID, Self.sliggooID])
        capped.dex[0].profile?.growthTokens = SaveTransfer.maxTokenValue - 1
        let store = try await makeStore(capped)
        let leftover = try graduatingLeftover(store)
        let sliggooBefore = try growth(store, Self.sliggooID)

        XCTAssertEqual(store.useRareCandy(count: 3), .graduated)

        XCTAssertEqual(try growth(store, Self.pikachuID), SaveTransfer.maxTokenValue)
        XCTAssertEqual(try growth(store, Self.sliggooID), sliggooBefore + leftover / 2)
    }

    func testACandyThatDoesNotGraduateGivesHoldersNothing() async throws {
        var legendary = state(holders: [Self.pikachuID])
        var profile = PokemonProfile.generate(seed: 5, instanceID: Self.lineID)
        profile.level = 20
        legendary.active = MonState(baseID: 150, pathIDs: [150], stageIndex: 0, usedAtStage: 0, rarity: .legendary,
                                    totalForms: 1, profile: profile)
        let store = try await makeStore(legendary)
        let before = try growth(store, Self.pikachuID)

        XCTAssertEqual(store.useRareCandy(count: 1), .progressed)

        XCTAssertEqual(try growth(store, Self.pikachuID), before)
        XCTAssertNil(store.candyLeftoverShared)
    }

    func testAHolderWhosePartRoundsToZeroIsLeftUntouched() async throws {
        var legendary = state(holders: [Self.pikachuID, Self.sliggooID], usedAtStage: 1, candies: 6)
        var profile = PokemonProfile.generate(seed: 5, instanceID: Self.lineID)
        profile.level = 20
        legendary.active = MonState(baseID: 150, pathIDs: [150], stageIndex: 0, usedAtStage: 1, rarity: .legendary,
                                    totalForms: 1, profile: profile)
        let store = try await makeStore(legendary)
        XCTAssertEqual(try XCTUnwrap(store.planRareCandyUse(count: 6)).discardedXP, 1)
        let before = try [Self.pikachuID, Self.sliggooID].map { try growth(store, $0) }
        XCTAssertNil(store.state.graduateEvolution[Self.sliggooID])

        XCTAssertEqual(store.useRareCandy(count: 6), .graduated)

        XCTAssertEqual(try growth(store, Self.pikachuID), before[0] + 1)
        XCTAssertEqual(try growth(store, Self.sliggooID), before[1])
        XCTAssertNil(store.state.graduateEvolution[Self.sliggooID], "no progress opened for 0 XP")
    }

    func testTheGraduatingPokemonDoesNotTakeItsOwnLeftover() async throws {
        let store = try await makeStore(state(holders: [Self.lineID, Self.pikachuID]))
        XCTAssertTrue(store.holdsExpShare(Self.lineID))
        let leftover = try graduatingLeftover(store)
        let before = try growth(store, Self.pikachuID)
        XCTAssertEqual(store.candyLeftoverRecipientCount, 1)

        XCTAssertEqual(store.useRareCandy(count: 3), .graduated)

        XCTAssertEqual(try growth(store, Self.pikachuID), before + leftover)
        XCTAssertEqual(try growth(store, Self.lineID), PokemonBalance.graduationTotal(.common))
    }
}
