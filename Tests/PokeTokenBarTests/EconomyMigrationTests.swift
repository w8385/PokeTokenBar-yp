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
    private let divisor = PokemonBalance.economyDivisor

    private struct Fixture {
        let store: CompanionStore
        let url: URL
        let defaults: UserDefaults
    }

    /// A save written before the ÷5 tables: credits and profile growth are in the old (5×) units.
    /// `oldMultiplier` is the effective growth difficulty the player had under the old tables.
    private func oldSave(egg: Bool, oldMultiplier: Double, fraction: Double = 0.5) -> CompanionState {
        var state = CompanionState()
        state.economyVersion = 1
        state.installBaselineSet = true
        state.lastDate = "2026-09-11"
        state.usedSinceInstall = 900_000_000
        state.spentTokens = 123_000_000
        let scale = Double(divisor) * oldMultiplier
        if egg {
            state.eggUsage = Int(Double(PokemonBalance.eggHatchThreshold) * scale * fraction)
        } else {
            var mon = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1, 2, 3], stageIndex: 0,
                               usedAtStage: 0, rarity: .common, totalForms: 3)
            mon.usedAtStage = Int(Double(mon.phaseThreshold) * scale * fraction)
            mon.profile = PokemonProfile.generate(
                seed: 7, growthTokens: PokemonBalance.graduationTotal(.common) * divisor / 2)
            state.active = mon
        }
        return state
    }

    private func fixture(_ state: CompanionState, stored: Double?, marker: Bool = false) throws -> Fixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("economy-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: url)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "economy-\(UUID())"))
        if let stored {
            defaults.set(stored, forKey: "growthDifficulty")
            defaults.set(stored, forKey: "shopDifficulty")
        }
        if marker { defaults.set(true, forKey: PokemonBalance.difficultyMigratedKey) }
        let store = CompanionStore(provider: EconomyProvider(), fileURL: url,
                                   dittoDisguiseRollingEnabled: false, defaults: defaults)
        return Fixture(store: store, url: url, defaults: defaults)
    }

    // MARK: slider rule

    func testMigratedDifficultyRule() {
        XCTAssertEqual(PokemonBalance.migratedDifficulty(nil), 1)
        XCTAssertEqual(PokemonBalance.migratedDifficulty(1), 1, "a stored 1.0 is the launch-time rewrite of the default")
        XCTAssertEqual(PokemonBalance.migratedDifficulty(.nan), 1)
        XCTAssertEqual(PokemonBalance.migratedDifficulty(0.1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PokemonBalance.migratedDifficulty(0.5), 2)
        XCTAssertEqual(PokemonBalance.migratedDifficulty(20), 2, "clamped to the slider maximum")
    }

    // MARK: default path

    func testDefaultUserKeepsHalfGrownActiveAndLevel() throws {
        let state = oldSave(egg: false, oldMultiplier: 1)
        var reference = PokemonProfile.generate(seed: 7, growthTokens: PokemonBalance.graduationTotal(.common) / 2)
        reference.applyGrowth(0, rarity: .common)
        XCTAssertGreaterThan(reference.level, 5)
        let f = try fixture(state, stored: nil)
        XCTAssertEqual(f.store.growthDifficulty, 1)
        XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(f.store.state.active?.profile?.growthTokens,
                       PokemonBalance.graduationTotal(.common) / 2)
        XCTAssertEqual(f.store.state.active?.profile?.level, reference.level, "level stays at the half-grown value, not 100")
        XCTAssertEqual(f.store.state.economyVersion, PokemonBalance.economyVersion)
        XCTAssertEqual(f.store.state.usedSinceInstall, 900_000_000, "real usage and wallet never change")
        XCTAssertEqual(f.store.state.spentTokens, 123_000_000)
    }

    func testDefaultUserKeepsHalfHatchedEgg() throws {
        let f = try fixture(oldSave(egg: true, oldMultiplier: 1), stored: 1)
        XCTAssertEqual(f.store.eggProgress, 0.5, accuracy: 0.001)
    }

    // MARK: level never drops

    func testLevel60StaysLevel60ForDefaultAndExplicitSliders() throws {
        let total = PokemonBalance.graduationTotal(.common)
        var newUnits = 0
        var probe = PokemonProfile.generate(seed: 7)
        while probe.level < 60 {
            newUnits += total / 400
            probe = PokemonProfile.generate(seed: 7, growthTokens: newUnits)
            probe.applyGrowth(0, rarity: .common)
        }
        XCTAssertEqual(probe.level, 60)

        for (stored, multiplier) in [(nil, 1.0), (Optional(0.1), 0.1)] as [(Double?, Double)] {
            var state = oldSave(egg: false, oldMultiplier: multiplier)
            var profile = PokemonProfile.generate(seed: 7, growthTokens: newUnits * divisor)
            profile.level = 60
            state.active?.profile = profile
            let f = try fixture(state, stored: stored)
            let after = try XCTUnwrap(f.store.state.active?.profile)
            XCTAssertEqual(after.level, 60, "slider \(String(describing: stored))")
            XCTAssertEqual(after.growthTokens, newUnits)
            XCTAssertEqual(after.ivs, profile.ivs)
        }
    }

    // MARK: explicit path

    func testExplicitDifficultyIsMultipliedAndCreditsStay() throws {
        for egg in [false, true] {
            let state = oldSave(egg: egg, oldMultiplier: 0.1)
            let f = try fixture(state, stored: 0.1)
            XCTAssertEqual(f.store.growthDifficulty, 0.5, accuracy: 1e-9)
            XCTAssertEqual(f.store.shopDifficulty, 0.5, accuracy: 1e-9)
            XCTAssertEqual(f.defaults.double(forKey: "growthDifficulty"), 0.5, accuracy: 1e-9)
            if egg {
                XCTAssertEqual(f.store.state.eggUsage, state.eggUsage, "×5 slider and ÷5 tables cancel")
                XCTAssertEqual(f.store.eggProgress, 0.5, accuracy: 0.001)
            } else {
                XCTAssertEqual(f.store.state.active?.usedAtStage, state.active?.usedAtStage)
                XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
                XCTAssertEqual(f.store.state.active?.profile?.growthTokens,
                               PokemonBalance.graduationTotal(.common) / 2)
            }
        }
    }

    // MARK: clamp path

    func testClampedExplicitDifficultyKeepsTheEarnedFraction() throws {
        for egg in [false, true] {
            let f = try fixture(oldSave(egg: egg, oldMultiplier: 0.5), stored: 0.5)
            XCTAssertEqual(f.store.growthDifficulty, 2, "0.5 × 5 clamps to the 2.0 maximum")
            XCTAssertEqual(egg ? f.store.eggProgress : f.store.progress, 0.5, accuracy: 0.001)
        }
    }

    // MARK: marker

    func testSecondLaunchDoesNotMigrateAgain() throws {
        let f = try fixture(oldSave(egg: false, oldMultiplier: 0.1), stored: 0.1)
        let credits = f.store.state.active?.usedAtStage
        let growth = f.store.state.active?.profile?.growthTokens
        XCTAssertTrue(f.defaults.bool(forKey: PokemonBalance.difficultyMigratedKey))
        let again = CompanionStore(provider: EconomyProvider(), fileURL: f.url,
                                   dittoDisguiseRollingEnabled: false, defaults: f.defaults)
        XCTAssertEqual(again.growthDifficulty, 0.5, accuracy: 1e-9)
        XCTAssertEqual(again.state.active?.usedAtStage, credits)
        XCTAssertEqual(again.state.active?.profile?.growthTokens, growth)
    }

    func testPreMigrationBackupIsWrittenOnce() throws {
        let f = try fixture(oldSave(egg: false, oldMultiplier: 1), stored: nil)
        let backup = f.url.deletingLastPathComponent().appendingPathComponent("companion-state.pre-economy-v2.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let old = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: backup))
        XCTAssertEqual(old.economyVersion, 1)
    }

    func testNewSaveStartsAtCurrentVersionAndOldJSONDecodesAsV1() throws {
        XCTAssertEqual(CompanionState().economyVersion, PokemonBalance.economyVersion)
        let legacy = try JSONDecoder().decode(CompanionState.self, from: Data(#"{"usedSinceInstall":1}"#.utf8))
        XCTAssertEqual(legacy.economyVersion, 1)
    }

    // MARK: import

    func testRestoringAnOldSaveKeepsTheFractionForAMigratedExplicitSlider() throws {
        let f = try fixture(CompanionState(), stored: 0.1)
        XCTAssertEqual(f.store.growthDifficulty, 0.5, accuracy: 1e-9)
        for egg in [false, true] {
            let old = oldSave(egg: egg, oldMultiplier: 0.1)
            let data = try SaveTransfer.encode(state: old, appVersion: "2.5.0", deviceName: "Old Mac",
                                               now: Date(timeIntervalSince1970: 1_700_000_000))
            try f.store.applySave(try SaveTransfer.decode(data), todayTokensByProvider: [:],
                                  todayDate: "2026-09-11", hasUsageData: false)
            XCTAssertEqual(egg ? f.store.eggProgress : f.store.progress, 0.5, accuracy: 0.001)
        }
    }

    func testImportingAnOldSaveMigratesIt() throws {
        let f = try fixture(CompanionState(), stored: nil)
        let old = oldSave(egg: false, oldMultiplier: 1)
        let data = try SaveTransfer.encode(state: old, appVersion: "2.5.0", deviceName: "Old Mac",
                                           now: Date(timeIntervalSince1970: 1_700_000_000))
        let envelope = try SaveTransfer.decode(data)
        try f.store.applySave(envelope, todayTokensByProvider: [:], todayDate: "2026-09-11", hasUsageData: false)
        XCTAssertEqual(f.store.state.economyVersion, PokemonBalance.economyVersion)
        XCTAssertEqual(f.store.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(f.store.state.active?.profile?.growthTokens, PokemonBalance.graduationTotal(.common) / 2)
    }
}
