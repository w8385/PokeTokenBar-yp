import XCTest
@testable import PokeTokenBar

/// The PokéAPI gender data the app follows, from `scripts/generate-gender-fixture.py`.
struct GenderFixture: Decodable {
    struct Variety: Decodable {
        let pokemonID: Int
        let name: String
        let speciesID: Int
    }

    let spriteFolders: [String: [Int]]
    let femaleVarieties: [Variety]

    static func load() throws -> GenderFixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/gender-differences.json")
        return try JSONDecoder().decode(GenderFixture.self, from: Data(contentsOf: url))
    }

    /// Species with a female file in every folder the app draws from: still and animated, front and back, plain and shiny.
    func speciesWithEveryFemaleSprite() throws -> Set<Int> {
        let variants = ["female", "shiny/female", "back/female", "back/shiny/female"]
        var ids = Set(PokemonAssets.supportedSpeciesIDs)
        for variant in variants {
            ids.formIntersection(try XCTUnwrap(spriteFolders[variant], variant))
            let blackWhite = Set(try XCTUnwrap(spriteFolders["versions/generation-v/black-white/animated/" + variant]))
            let showdown = Set(try XCTUnwrap(spriteFolders["other/showdown/" + variant]))
            ids = ids.filter { PokemonAssets.blackWhiteAnimatedIDs.contains($0) ? blackWhite.contains($0) : showdown.contains($0) }
        }
        return ids
    }
}

final class GenderArtTests: XCTestCase {
    private static let variants: [(shiny: Bool, back: Bool)] = [(false, false), (true, false), (false, true), (true, true)]

    private func file(_ speciesID: Int, animated: Bool, shiny: Bool = false, back: Bool = false, female: Bool) -> String {
        let url = SpriteStore.spriteURL(speciesID: speciesID, animated: animated, shiny: shiny, back: back, female: female)
        return url.pathComponents.suffix(2).joined(separator: "/")
    }

    func testAFemaleIsDrawnWithTheSameGenderArtStillAndAnimated() {
        var mismatched: [String] = []
        for speciesID in PokemonAssets.supportedSpeciesIDs {
            for variant in Self.variants {
                let still = file(speciesID, animated: false, shiny: variant.shiny, back: variant.back, female: true)
                let animated = file(speciesID, animated: true, shiny: variant.shiny, back: variant.back, female: true)
                if still.hasPrefix("female/") != animated.hasPrefix("female/")
                    || still.split(separator: "/").last?.split(separator: ".").first
                        != animated.split(separator: "/").last?.split(separator: ".").first {
                    mismatched.append("#\(speciesID) \(variant): \(still) vs \(animated)")
                }
            }
        }
        XCTAssertEqual(mismatched, [])
    }

    func testAFemaleIsDrawnFromTheFemaleFolderOnlyWhereEveryFemaleFileExists() throws {
        let fixture = try GenderFixture.load()
        let complete = try fixture.speciesWithEveryFemaleSprite()
        let varieties = Set(fixture.femaleVarieties.map(\.speciesID))
        let drawnFemale = Set(PokemonAssets.supportedSpeciesIDs.filter { file($0, animated: false, female: true).hasPrefix("female/") })
        XCTAssertEqual(drawnFemale, complete.subtracting(varieties))
        XCTAssertTrue(drawnFemale.contains(668), "Pyroar")
        XCTAssertFalse(drawnFemale.contains(133), "Eevee has no female GIF")
    }

    func testAFemaleOfAGenderVarietyIsDrawnAsThatVarietyStillAndAnimated() throws {
        for variety in try GenderFixture.load().femaleVarieties {
            for variant in Self.variants {
                let label = "\(variety.name) \(variant)"
                XCTAssertEqual(file(variety.speciesID, animated: false, shiny: variant.shiny, back: variant.back, female: true),
                               "\(variant.shiny ? "shiny" : variant.back ? "back" : "pokemon")/\(variety.pokemonID).png", label)
                XCTAssertTrue(file(variety.speciesID, animated: true, shiny: variant.shiny, back: variant.back, female: true)
                    .hasSuffix("/\(variety.pokemonID).gif"), label)
                XCTAssertEqual(file(variety.speciesID, animated: false, shiny: variant.shiny, back: variant.back, female: false)
                    .split(separator: "/").last, "\(variety.speciesID).png", label)
            }
            XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: variety.pokemonID), variety.name)
        }
    }
}
