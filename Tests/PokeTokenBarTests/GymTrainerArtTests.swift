import AppKit
import Foundation
import XCTest
@testable import PokeTokenBar

enum GymRepo {
    /// `assets/trainers` of this checkout, two directories above `Tests/PokeTokenBarTests`.
    static let trainerAssets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("assets/trainers")
    /// The bot's Kanto catalog; `bot/tests/test_gym_api.py` fails when it drifts from `gyms.catalog()`.
    static let kantoCatalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/kanto-gym-catalog.json")
}

@MainActor
final class GymTrainerArtTests: XCTestCase {
    private var original: URL?

    override func setUp() {
        original = GymTrainerArt.directory
        GymTrainerArt.directory = GymRepo.trainerAssets
        GymTrainerArt.clearCache()
    }

    override func tearDown() {
        GymTrainerArt.directory = original
        GymTrainerArt.clearCache()
    }

    func testEveryBattleOfTheNineRegionsHasBundledArt() {
        let regions = ["kanto", "johto", "hoenn", "sinnoh", "unova", "kalos", "alola", "galar", "paldea"]
        var ids: [String] = []
        for region in regions {
            ids += (1...8).map { "\(region)-\($0)" }
            ids += (1...4).map { "\(region)-elite-\($0)" }
            ids += ["\(region)-champion"]
            ids += (1...4).map { "\(region)-hideout-\($0)" }
        }

        XCTAssertEqual(ids.count, 153)
        XCTAssertEqual(ids.filter { GymTrainerArt.image($0) == nil }, [])
    }

    func testTheFixtureCatalogBattlesAllResolveToArt() throws {
        let region = try XCTUnwrap(GymFixtures.catalog().region("kanto"))
        let missing = (region.gyms + region.elite.battles + region.hideout.battles).filter { GymTrainerArt.image($0.id) == nil }

        XCTAssertEqual(missing.map(\.id), [])
    }

    func testAnUnknownIdHasNoArtAndTheSilhouetteStandsIn() {
        XCTAssertNil(GymTrainerArt.image("atlantis-1"))
        GymTrainerArt.directory = nil
        XCTAssertNil(GymTrainerArt.image("kanto-1"))
    }

    func testBuildScriptCopiesTheTrainerArtIntoTheBundle() throws {
        let script = GymRepo.trainerAssets.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)

        XCTAssertTrue(text.contains("assets/trainers/*.png"))
        XCTAssertTrue(text.contains("Contents/Resources/trainers"))
    }
}
