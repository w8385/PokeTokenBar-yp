import XCTest
@testable import PokeTokenBar

@MainActor
final class MintTests: XCTestCase {
    private let boxID = "onix-graduate"

    private func store(mint: Int = 1, tokens: Int = 1_000_000_000) async throws -> CompanionStore {
        let fixture = try TrainingFixture(self)
        let state = TrainingFixture.state(dex: [TrainingFixture.graduate(boxID, speciesID: 95)],
                                          inventory: mint > 0 ? ["mint": mint] : [:], tokens: tokens)
        return try await fixture.store(state)
    }

    private func nature(_ s: CompanionStore, _ id: String) -> PokemonNature? { s.trainable(id: id)?.nature }

    func testMintSetsThePickedNatureOnABoxPokemon() async throws {
        let s = try await store(mint: 2)
        XCTAssertEqual(s.changeNature(of: boxID, to: .modest), .changed)
        XCTAssertEqual(nature(s, boxID), .modest)
        XCTAssertEqual(s.itemCount(.mint), 1)
        XCTAssertEqual(s.state.spentTokens, 0)
        XCTAssertEqual(s.state.active?.nature, .adamant, "the active Pokémon is untouched")
    }

    func testMintSetsThePickedNatureOnTheActivePokemonAndShowsFeedback() async throws {
        let s = try await store()
        let seq = s.mintFeedbackSeq
        XCTAssertEqual(s.changeNature(of: TrainingFixture.activeID, to: .jolly), .changed)
        XCTAssertEqual(s.state.active?.nature, .jolly)
        XCTAssertEqual(s.mintFeedbackNature, .jolly)
        XCTAssertEqual(s.mintFeedbackSeq, seq + 1)
    }

    func testMintOnABoxPokemonShowsNoHomeFeedback() async throws {
        let s = try await store()
        _ = s.changeNature(of: boxID, to: .modest)
        XCTAssertNil(s.mintFeedbackNature)
    }

    func testPickingTheCurrentNatureIsFreeAndChangesNothing() async throws {
        let s = try await store(mint: 1)
        XCTAssertEqual(s.changeNature(of: boxID, to: .lonely), .unchanged)
        XCTAssertEqual(s.itemCount(.mint), 1)
        let empty = try await store(mint: 0)
        XCTAssertEqual(empty.changeNature(of: boxID, to: .lonely), .unchanged)
        XCTAssertEqual(empty.state.spentTokens, 0)
    }

    func testBuyAndUseDeductsOnceAndSetsTheNature() async throws {
        let s = try await store(mint: 0, tokens: Mint.price + 5)
        XCTAssertEqual(s.mintPayment, .buy(price: Mint.price))
        XCTAssertEqual(s.changeNature(of: boxID, to: .timid), .changed)
        XCTAssertEqual(nature(s, boxID), .timid)
        XCTAssertEqual(s.state.spentTokens, Mint.price)
        XCTAssertEqual(s.availableTokens, 5)
        XCTAssertEqual(s.itemCount(.mint), 0, "the bought Mint is used, not stocked")
    }

    func testShortTokensRefuseWithoutChange() async throws {
        let s = try await store(mint: 0, tokens: Mint.price - 1)
        XCTAssertEqual(s.mintPayment, .short(price: Mint.price))
        XCTAssertEqual(s.changeNature(of: boxID, to: .timid), .short)
        XCTAssertEqual(nature(s, boxID), .lonely)
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    func testMintRefusesAnUnknownOrTradeLockedPokemon() async throws {
        let s = try await store(mint: 1)
        XCTAssertEqual(s.changeNature(of: "nobody", to: .timid), .unavailable)
        s.lockForTrade(boxID)
        XCTAssertEqual(s.changeNature(of: boxID, to: .timid), .unavailable)
        XCTAssertEqual(s.itemCount(.mint), 1)
    }

    func testMintChangePersistsAcrossRestart() async throws {
        let fixture = try TrainingFixture(self)
        let state = TrainingFixture.state(dex: [TrainingFixture.graduate(boxID, speciesID: 95)], inventory: ["mint": 2])
        let s = try await fixture.store(state)
        XCTAssertEqual(s.changeNature(of: boxID, to: .bold), .changed)
        let restored = fixture.reload()
        XCTAssertEqual(restored.trainable(id: boxID)?.nature, .bold)
        XCTAssertEqual(restored.itemCount(.mint), 1)
    }

    func testMintShopPriceAndPurchase() async throws {
        XCTAssertEqual(ItemKind.mint.shopPrice, Mint.price)
        let s = try await store(mint: 0, tokens: Mint.price)
        XCTAssertTrue(s.purchasableItems.contains(.mint))
        XCTAssertTrue(s.buy(.mint))
        XCTAssertEqual(s.itemCount(.mint), 1)
        XCTAssertFalse(s.canBuy(.mint))
    }
}
