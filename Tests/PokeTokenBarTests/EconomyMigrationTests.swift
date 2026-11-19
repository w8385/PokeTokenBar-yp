import XCTest
@testable import PokeTokenBar

private struct EconomyProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [
            EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                rarity: .common, names: [:])
    }
}

@MainActor
final class EconomyMigrationTests: XCTestCase {
    private static let storedID = "stored-line"
    private static let graduateID = "graduate"

    private struct Fixture {
        let store: CompanionStore
        let url: URL
        let defaults: UserDefaults
    }

    private struct Slider {
        var stored: Double?
        var marker = true
        var v1: Double?
    }

    /// The level a profile has with `growth` current-table tokens.
    private func level(for growth: Int) -> Int {
        var probe = PokemonProfile.generate(seed: 7, growthTokens: growth)
        probe.applyGrowth(0, rarity: .common)
        return probe.level
    }

    /// A save from an older economy. Its thresholds were `scale` times today's, slider included.
    private func oldSave(version: Int, scale: Double, egg: Bool = false, fraction: Double = 0.5) -> CompanionState {
        let factor = version <= 1 ? 50 : 10
        func credits(_ base: Int) -> Int { Int(Double(Int((Double(base) * scale).rounded())) * fraction) }
        func profile(_ id: String) -> PokemonProfile {
            var profile = PokemonProfile.generate(seed: 7, growthTokens: PokemonBalance.graduationTotal(.common) / 2 * factor,
                                                  instanceID: id)
            profile.level = level(for: PokemonBalance.graduationTotal(.common) / 2)
            return profile
        }
        var state = CompanionState()
        state.economyVersion = version
        state.installBaselineSet = true
        state.lastDate = "2026-09-11"
        state.usedSinceInstall = 900_000_000
        state.spentTokens = 123_000_000
        state.timeCredit = 45_000_000
        if egg {
            state.eggUsage = credits(PokemonBalance.eggHatchThreshold)
            return state
        }
        var mon = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1, 2, 3], stageIndex: 0,
                           usedAtStage: 0, rarity: .common, totalForms: 3)
        mon.usedAtStage = credits(mon.phaseThreshold)
        mon.profile = profile("active")
        state.active = mon
        var boxed = mon
        boxed.profile = profile(Self.storedID)
        state.storedLines[Self.storedID] = StoredLine(mon: boxed, spentAtStore: 0)
        state.dex.append(DexEntry(id: Self.storedID, baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 3_000), profile: boxed.profile,
                                  releasedAt: Date(timeIntervalSince1970: 3_000)))
        state.dex.append(DexEntry(id: Self.graduateID, baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 4_000), profile: profile(Self.graduateID)))
        var progress = EvolutionProgress()
        progress.graduateXP = Int(1_000_000 * scale)
        state.graduateEvolution[Self.graduateID] = progress
        return state
    }

    private func fixture(_ state: CompanionState, _ slider: Slider) throws -> Fixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("economy-\(UUID())").appendingPathComponent("companion-state.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "economy-\(UUID())"))
        if let stored = slider.stored {
            defaults.set(stored, forKey: LegacyGrowthDifficulty.growthKey)
            defaults.set(stored, forKey: LegacyGrowthDifficulty.shopKey)
        }
        if slider.marker { defaults.set(true, forKey: LegacyGrowthDifficulty.movedToV2Key) }
        if let v1 = slider.v1 { defaults.set(v1, forKey: LegacyGrowthDifficulty.v1GrowthKey) }
        let store = CompanionStore(provider: EconomyProvider(), fileURL: url,
                                   dittoDisguiseRollingEnabled: false, defaults: defaults)
        return Fixture(store: store, url: url, defaults: defaults)
    }

    private func storedFraction(_ store: CompanionStore) throws -> Double {
        let mon = try XCTUnwrap(store.state.storedLines[Self.storedID]?.mon)
        return Double(mon.usedAtStage) / Double(store.stageThreshold(for: mon))
    }

    private func assertLevelsAndWalletKept(_ store: CompanionStore,
                                           file: StaticString = #filePath, line: UInt = #line) throws {
        let half = PokemonBalance.graduationTotal(.common) / 2
        let profiles = [store.state.active?.profile, store.state.storedLines[Self.storedID]?.mon.profile]
            + store.state.dex.map(\.profile)
        for profile in profiles {
            var after = try XCTUnwrap(profile, file: file, line: line)
            XCTAssertEqual(after.growthTokens, half, "growth moves to the current tables", file: file, line: line)
            XCTAssertEqual(after.level, level(for: half), file: file, line: line)
            after.applyGrowth(0, rarity: .common)
            XCTAssertEqual(after.level, level(for: half), "the next growth step keeps the level", file: file, line: line)
        }
        XCTAssertEqual(store.state.usedSinceInstall, 900_000_000, file: file, line: line)
        XCTAssertEqual(store.state.spentTokens, 123_000_000, file: file, line: line)
        XCTAssertEqual(store.state.timeCredit, 45_000_000, file: file, line: line)
        XCTAssertEqual(store.state.economyVersion, PokemonBalance.economyVersion, file: file, line: line)
    }

    // MARK: v2 saves

    func testLowestSliderSaveKeepsThresholdsProgressPricesAndLevels() throws {
        let old = oldSave(version: 2, scale: 10 * 0.1)
        let f = try fixture(old, Slider(stored: 0.1))
        let mon = try XCTUnwrap(f.store.state.active)
        XCTAssertEqual(mon.usedAtStage, old.active?.usedAtStage)
        XCTAssertEqual(f.store.state.storedLines[Self.storedID]?.mon.usedAtStage,
                       old.storedLines[Self.storedID]?.mon.usedAtStage)
        XCTAssertEqual(f.store.state.graduateEvolution[Self.graduateID]?.graduateXP, 1_000_000)
        XCTAssertEqual(f.store.stageThreshold(for: mon), Int((Double(mon.phaseThreshold * 10) * 0.1).rounded()))
        XCTAssertEqual(f.store.eggHatchThreshold, Int((1_000_000 * 0.1).rounded()))
        XCTAssertEqual(f.store.price(of: .rareCandy), Int((100_000_000 * 0.1).rounded()))
        XCTAssertEqual(f.store.tmPrice(power: 120, isWeather: false), Int((120_000_000 * 0.1).rounded()))
        try assertLevelsAndWalletKept(f.store)

        let egg = try fixture(oldSave(version: 2, scale: 1, egg: true), Slider(stored: 0.1))
        XCTAssertEqual(egg.store.state.eggUsage, oldSave(version: 2, scale: 1, egg: true).eggUsage)
    }

    func testFullSliderSaveKeepsEachStageFractionLevelsAndWallet() throws {
        let f = try fixture(oldSave(version: 2, scale: 10 * 1.0), Slider(stored: 1.0))
        XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(try storedFraction(f.store), 0.5, accuracy: 0.001)
        XCTAssertEqual(f.store.state.graduateEvolution[Self.graduateID]?.graduateXP, 1_000_000)
        try assertLevelsAndWalletKept(f.store)

        let egg = try fixture(oldSave(version: 2, scale: 10, egg: true), Slider(stored: 1.0))
        XCTAssertEqual(egg.store.eggProgress, 0.5, accuracy: 0.001)
    }

    func testMidRangeSliderKeepsTheFraction() throws {
        let f = try fixture(oldSave(version: 2, scale: 10 * 0.5), Slider(stored: 0.5))
        XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(try storedFraction(f.store), 0.5, accuracy: 0.001)
        try assertLevelsAndWalletKept(f.store)
    }

    func testOutOfRangeSliderIsReadTheWayTheV2AppClampedIt() throws {
        for (stored, effective) in [(50.0, 2.0), (0.0, 0.1), (-3.0, 0.1)] {
            let f = try fixture(oldSave(version: 2, scale: 10 * effective), Slider(stored: stored))
            XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001, "stored \(stored)")
            try assertLevelsAndWalletKept(f.store)
        }
    }

    func testMissingSliderMeansTheDefault() throws {
        let f = try fixture(oldSave(version: 2, scale: 10), Slider(stored: nil))
        XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
        try assertLevelsAndWalletKept(f.store)
    }

    func testAnIncompleteStageNeverCompletes() throws {
        let f = try fixture(oldSave(version: 2, scale: 10 * 2, fraction: 0.99999), Slider(stored: 2))
        let mon = try XCTUnwrap(f.store.state.active)
        XCTAssertLessThan(mon.usedAtStage, f.store.stageThreshold(for: mon))
    }

    // MARK: v1 saves

    func testV1SaveFromBeforeTheV2SliderMove() throws {
        let f = try fixture(oldSave(version: 1, scale: 50 * 0.1), Slider(stored: 0.1, marker: false))
        XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
        try assertLevelsAndWalletKept(f.store)
    }

    func testV1SaveAfterTheV2SliderMoveUsesTheRecordedV1Slider() throws {
        let f = try fixture(oldSave(version: 1, scale: 50 * 0.1), Slider(stored: 0.5, v1: 0.1))
        XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
        try assertLevelsAndWalletKept(f.store)
    }

    func testV2SaveWithoutTheMarkerReadsTheSliderTheV2AppWouldHaveMoved() throws {
        let f = try fixture(oldSave(version: 2, scale: 10 * 0.5), Slider(stored: 0.1, marker: false))
        XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
    }

    // MARK: once

    func testSecondLaunchDoesNotMigrateAgainAndDefaultsAreNotWritten() throws {
        let f = try fixture(oldSave(version: 2, scale: 10), Slider(stored: 1.0))
        let credits = f.store.state.active?.usedAtStage
        let growth = f.store.state.active?.profile?.growthTokens
        let again = CompanionStore(provider: EconomyProvider(), fileURL: f.url,
                                   dittoDisguiseRollingEnabled: false, defaults: f.defaults)
        XCTAssertEqual(again.state.active?.usedAtStage, credits)
        XCTAssertEqual(again.state.active?.profile?.growthTokens, growth)

        let fresh = try fixture(CompanionState(), Slider(stored: nil, marker: false))
        for key in [LegacyGrowthDifficulty.growthKey, LegacyGrowthDifficulty.shopKey,
                    LegacyGrowthDifficulty.movedToV2Key, LegacyGrowthDifficulty.v1GrowthKey] {
            XCTAssertNil(fresh.defaults.object(forKey: key), key)
        }
    }

    func testPreMigrationBackupIsWrittenOnce() throws {
        let f = try fixture(oldSave(version: 2, scale: 10), Slider(stored: 1.0))
        let backup = f.url.deletingLastPathComponent().appendingPathComponent("companion-state.pre-economy-v3.json")
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: backup)).economyVersion, 2)
        var later = oldSave(version: 2, scale: 10)
        later.usedSinceInstall = 1
        try JSONEncoder().encode(later).write(to: f.url)
        _ = CompanionStore(provider: EconomyProvider(), fileURL: f.url,
                           dittoDisguiseRollingEnabled: false, defaults: f.defaults)
        let kept = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: backup))
        XCTAssertEqual(kept.usedSinceInstall, 900_000_000, "the first backup is never overwritten")
    }

    func testNewSaveStartsAtCurrentVersionAndOldJSONDecodesAsV1() throws {
        XCTAssertEqual(CompanionState().economyVersion, 3)
        let legacy = try JSONDecoder().decode(CompanionState.self, from: Data(#"{"usedSinceInstall":1}"#.utf8))
        XCTAssertEqual(legacy.economyVersion, 1)
    }

    // MARK: import

    func testImportingAnOldSaveMigratesIt() throws {
        let f = try fixture(CompanionState(), Slider(stored: 0.5))
        let data = try SaveTransfer.encode(state: oldSave(version: 2, scale: 10 * 0.5), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: Date(timeIntervalSince1970: 1_700_000_000))
        try f.store.applySave(try SaveTransfer.decode(data), todayTokensByProvider: [:],
                              todayDate: "2026-09-11", hasUsageData: false)
        XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(f.store.state.economyVersion, PokemonBalance.economyVersion)
        XCTAssertEqual(f.store.state.active?.profile?.growthTokens, PokemonBalance.graduationTotal(.common) / 2)
    }

    // MARK: a real save, on a copy

    /// Opt-in: migrates a copy of a real save with the slider it was played at and prints what changed.
    ///
    ///     PTB_ECONOMY_DRY_RUN=/path/to/copy.json PTB_ECONOMY_DRY_RUN_SLIDER=0.1 \
    ///         swift test --filter EconomyMigrationTests
    func testDryRunOnACopyOfARealSave() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let source = environment["PTB_ECONOMY_DRY_RUN"] else {
            throw XCTSkip("Set PTB_ECONOMY_DRY_RUN to a copy of a save")
        }
        let slider = environment["PTB_ECONOMY_DRY_RUN_SLIDER"].flatMap(Double.init)
        let before = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: URL(fileURLWithPath: source)))
        let f = try fixture(before, Slider(stored: slider, marker: true, v1: slider))
        let after = f.store.state
        func levels(_ state: CompanionState) -> [Int] { state.dex.compactMap { $0.profile?.level } }
        func growth(_ state: CompanionState) -> Int { state.dex.compactMap { $0.profile?.growthTokens }.reduce(0, +) }
        func stages(_ state: CompanionState) -> [String] {
            ([state.active].compactMap { $0 } + state.storedLines.values.map(\.mon)).map {
                "\($0.stageIndex):\($0.usedAtStage)/\(f.store.stageThreshold(for: $0))"
            }
        }
        print("dry run: economyVersion \(before.economyVersion) -> \(after.economyVersion)")
        print("dry run: dex \(before.dex.count) -> \(after.dex.count), growthTokens \(growth(before)) -> \(growth(after))")
        print("dry run: stages before \(stages(before)) after \(stages(after))")
        print("dry run: egg \(before.eggUsage) -> \(after.eggUsage)")
        print("dry run: wallet used \(after.usedSinceInstall) spent \(after.spentTokens) time \(after.timeCredit)")
        XCTAssertEqual(after.economyVersion, PokemonBalance.economyVersion)
        XCTAssertEqual(levels(after), levels(before), "levels never move")
        XCTAssertEqual(after.usedSinceInstall, before.usedSinceInstall)
        XCTAssertEqual(after.spentTokens, before.spentTokens)
        XCTAssertEqual(after.timeCredit, before.timeCredit)
    }
}
