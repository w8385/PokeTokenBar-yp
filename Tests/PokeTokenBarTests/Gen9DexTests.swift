import XCTest
@testable import PokeTokenBar

final class Gen9DexTests: XCTestCase {
    private let spriteRoot = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"

    func testGen5KeepsBlackWhiteGIFsAndGen6PlusUsesShowdown() {
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 649, animated: true, shiny: false).absoluteString,
                       "\(spriteRoot)/versions/generation-v/black-white/animated/649.gif")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 650, animated: true, shiny: false).absoluteString,
                       "\(spriteRoot)/other/showdown/650.gif")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 906, animated: true, shiny: true, back: true).absoluteString,
                       "\(spriteRoot)/other/showdown/back/shiny/906.gif")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 1025, animated: false, shiny: false).absoluteString,
                       "\(spriteRoot)/1025.png")
    }

    func testSpeciesWithoutShowdownGIFStaySupportedButStatic() {
        XCTAssertTrue(PokemonAssets.isSupported(speciesID: 1025))
        XCTAssertFalse(PokemonAssets.hasAnimatedSprite(speciesID: 1025))
        XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: 1007))
        XCTAssertFalse(PokemonAssets.isSupported(speciesID: 1026))
    }

    func testEvolutionLinesKeepGen9StagesWithoutAnimatedSprites() {
        // Charcadet → Armarouge / Ceruledge; Iron Treads (990) has no Showdown GIF.
        let line = EvoLine(baseID: 935,
                           tree: EvoNode(speciesID: 935, children: [EvoNode(speciesID: 936, children: []),
                                                                    EvoNode(speciesID: 937, children: [])]),
                           rarity: .uncommon, names: [:])
        XCTAssertEqual(line.tree.finalIDs, [936, 937])
        let static990 = EvoLine(baseID: 990, tree: EvoNode(speciesID: 990, children: []), rarity: .rare, names: [:])
        XCTAssertEqual(static990.tree.speciesID, 990)
    }

    func testBaseIndexSnapshotFromTheGen5EraIsNotFresh() throws {
        let old = #"{"fetchedAt":0,"entries":[{"id":1,"captureRate":45}]}"#
        let snapshot = try JSONDecoder().decode(PokeAPIClient.BaseIndexSnapshot.self, from: Data(old.utf8))
        XCTAssertFalse(snapshot.coversSupportedRange)

        let current = PokeAPIClient.BaseIndexSnapshot(fetchedAt: Date(), entries: [],
                                                      maxSpeciesID: PokemonAssets.supportedSpeciesIDs.upperBound)
        let roundTrip = try JSONDecoder().decode(PokeAPIClient.BaseIndexSnapshot.self,
                                                 from: JSONEncoder().encode(current))
        XCTAssertTrue(roundTrip.coversSupportedRange)
    }
}
