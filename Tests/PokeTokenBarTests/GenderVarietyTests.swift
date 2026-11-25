import XCTest
@testable import PokeTokenBar

final class GenderVarietyTests: XCTestCase {
    private func profile(_ gender: PokemonGender, seed: UInt64 = 7) -> PokemonProfile {
        var profile = PokemonProfile.generate(seed: seed, instanceID: "gender-\(gender.rawValue)")
        profile.gender = gender
        return profile
    }

    func testAFemaleOfAGenderVarietyUploadsTheVarietyAndAMaleTheSpecies() throws {
        for variety in try GenderFixture.load().femaleVarieties {
            let female = PartyBuilder.member(speciesID: variety.speciesID, form: nil, shiny: false, profile: profile(.female))
            let male = PartyBuilder.member(speciesID: variety.speciesID, form: nil, shiny: false, profile: profile(.male))
            XCTAssertEqual(female.pokemonID, variety.pokemonID, variety.name)
            XCTAssertEqual(male.pokemonID, variety.speciesID, variety.name)
        }
    }

    func testTheGenderVarietiesAreThePokeAPIFemaleVarieties() throws {
        let fixture = try GenderFixture.load()
        XCTAssertEqual(GenderVariety.femalePokemonIDs,
                       Dictionary(uniqueKeysWithValues: fixture.femaleVarieties.map { ($0.speciesID, $0.pokemonID) }))
        for variety in fixture.femaleVarieties {
            XCTAssertNotNil(FormBattleData.byPokemonID[variety.pokemonID], variety.name)
        }
    }

    func testABattleSpriteOfAFemaleVarietyIdIsItsSpeciesDrawnFemale() throws {
        for variety in try GenderFixture.load().femaleVarieties {
            let target = try XCTUnwrap(BattleInfo.spriteTarget(pokemonID: variety.pokemonID), variety.name)
            XCTAssertEqual(target.speciesID, variety.speciesID, variety.name)
            XCTAssertNil(target.form, variety.name)
            XCTAssertTrue(target.female, variety.name)
        }
        XCTAssertEqual(BattleInfo.spriteTarget(pokemonID: 10191)?.female, false)
        XCTAssertEqual(BattleInfo.spriteTarget(pokemonID: 668)?.female, false)
    }

    func testAFemaleKeepsHerAbilitySlotInTheVariety() {
        var female = profile(.female)
        female.abilitySlot = 1
        female.abilityIsHidden = false
        female.abilityName = "inner-focus"
        XCTAssertEqual(FormBattleData.abilityName(speciesID: 876, form: nil, profile: female), "own-tempo")
        female.abilitySlot = 3
        female.abilityIsHidden = true
        female.abilityName = "prankster"
        XCTAssertEqual(FormBattleData.abilityName(speciesID: 678, form: nil, profile: female), "competitive")
        var male = profile(.male)
        male.abilityName = "inner-focus"
        XCTAssertEqual(FormBattleData.abilityName(speciesID: 876, form: nil, profile: male), "inner-focus")
    }

    func testTheRepresentativeUploadsAFemaleVarietyWhenTheNewestIsFemale() {
        let female = CompanionStore.RepresentativeSubject(speciesID: 916, isShiny: false, isFemale: true)
        let male = CompanionStore.RepresentativeSubject(speciesID: 916, isShiny: false, isFemale: false)
        let summary = { (subject: CompanionStore.RepresentativeSubject) in
            DexSummary(national: (owned: 1, shinyOwned: 0, total: 1025), completions: [], representative: subject)
        }
        XCTAssertEqual(summary(female).representative?.pokemonID, 10254)
        XCTAssertEqual(summary(male).representative?.pokemonID, 916)
    }

    func testAFemaleBasculegionFromARedStripedBasculinUploadsTheFemaleVariety() {
        let member = PartyBuilder.member(speciesID: 902, form: PokemonForm("red-striped"), shiny: false,
                                         profile: profile(.female))
        XCTAssertEqual(member.pokemonID, 10248)
        XCTAssertEqual(member.ability.map { ["swift-swim", "adaptability", "mold-breaker"].contains($0) }, true)
    }
}
