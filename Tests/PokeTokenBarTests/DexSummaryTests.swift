import Foundation
import XCTest
@testable import PokeTokenBar

final class DexSummaryTests: XCTestCase {
    private func json(_ payload: PartyPayload) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: payload.encoded()) as? [String: Any])
    }

    private let member = PartyMember(pokemonID: 25, level: 5, shiny: false, ivs: nil)

    private func summary(species: Int?, form: PokemonForm? = nil, shiny: Bool = false) -> DexSummary {
        let completions = DexProgress.regionCompletions(owned: [(id: 25, isShiny: true), (id: 152, isShiny: false)])
        return DexSummary(national: DexProgress.nationalProgress(owned: [(id: 25, isShiny: true), (id: 152, isShiny: false)]),
                          completions: completions,
                          representative: .init(speciesID: species, isShiny: shiny, form: form))
    }

    func testPayloadWithoutDexLeavesTheKeyOut() throws {
        XCTAssertNil(try json(PartyPayload(appVersion: "2.5.7", party: [member]))["dex"])
    }

    func testSummaryEncodesWithTheBotFieldNames() throws {
        let body = try json(PartyPayload(appVersion: "2.5.7", party: [member],
                                         dex: summary(species: 25, shiny: true)))

        let dex = try XCTUnwrap(body["dex"] as? [String: Any])
        XCTAssertEqual(dex["owned"] as? Int, 2)
        XCTAssertEqual(dex["shiny"] as? Int, 1)
        let regions = try XCTUnwrap(dex["regions"] as? [String: Int])
        XCTAssertEqual(regions["kanto"], 1)
        XCTAssertEqual(regions["johto"], 1)
        XCTAssertEqual(regions["paldea"], 0)
        XCTAssertEqual(regions.count, PokedexRegion.allCases.count)
        let representative = try XCTUnwrap(dex["representative"] as? [String: Any])
        XCTAssertEqual(representative["pokemon_id"] as? Int, 25)
        XCTAssertEqual(representative["shiny"] as? Bool, true)
    }

    func testEggHasNoRepresentative() throws {
        let dex = try XCTUnwrap(try json(PartyPayload(appVersion: nil, party: [member],
                                                      dex: summary(species: nil)))["dex"] as? [String: Any])
        XCTAssertNil(dex["representative"])
    }

    func testRepresentativeFormUsesTheVarietyID() {
        XCTAssertEqual(summary(species: 492, form: PokemonForm("sky")).representative?.pokemonID, 10006)
    }
}
