import XCTest
@testable import PokeTokenBar

@MainActor
final class PlayerToolTests: XCTestCase {
    private func store(_ dex: [DexEntry], inventory: [String: Int], species: [Int]) async throws -> CompanionStore {
        let fixture = try TrainingFixture(self)
        return try await fixture.store(TrainingFixture.state(dex: dex, inventory: inventory), loadDetailsFor: species)
    }

    private func onix(slot: Int, hidden: Bool = false) -> DexEntry {
        TrainingFixture.graduate("onix", speciesID: 95, profile: TrainingFixture.profile("p-onix", slot: slot, hidden: hidden))
    }

    private func ability(_ s: CompanionStore, _ id: String) -> (slot: Int?, hidden: Bool, name: String?)? {
        s.trainable(id: id).map { ($0.profile.abilitySlot, $0.profile.abilityIsHidden, $0.profile.abilityName) }
    }

    // MARK: Ability Capsule

    func testCapsuleSwapsTheRegularSlots() async throws {
        let s = try await store([onix(slot: 1)], inventory: ["abilityCapsule": 2], species: [95])
        XCTAssertEqual(s.useAbilityCapsule(on: "onix"), .changed)
        XCTAssertEqual(ability(s, "onix")?.slot, 2)
        XCTAssertEqual(ability(s, "onix")?.name, "sturdy")
        XCTAssertEqual(s.useAbilityCapsule(on: "onix"), .changed)
        XCTAssertEqual(ability(s, "onix")?.name, "rock-head")
        XCTAssertEqual(s.itemCount(.abilityCapsule), 0)
    }

    func testCapsuleIsRefusedOnASingleAbilitySpeciesAndNotConsumed() async throws {
        let kyurem = TrainingFixture.graduate("kyurem", speciesID: 646)
        let s = try await store([kyurem], inventory: ["abilityCapsule": 1, "abilityPatch": 1], species: [646])
        XCTAssertEqual(s.useAbilityCapsule(on: "kyurem"), .unavailable)
        XCTAssertEqual(s.useAbilityPatch(on: "kyurem"), .unavailable)
        XCTAssertEqual(s.itemCount(.abilityCapsule), 1)
        XCTAssertEqual(s.itemCount(.abilityPatch), 1)
    }

    func testCapsuleIsRefusedOnAHiddenAbility() async throws {
        let s = try await store([onix(slot: 3, hidden: true)], inventory: ["abilityCapsule": 1], species: [95])
        XCTAssertEqual(s.useAbilityCapsule(on: "onix"), .unavailable)
        XCTAssertEqual(s.itemCount(.abilityCapsule), 1)
    }

    func testCapsuleWaitsForTheSpeciesDetails() async throws {
        let s = try await store([onix(slot: 1)], inventory: ["abilityCapsule": 1], species: [])
        XCTAssertEqual(s.useAbilityCapsule(on: "onix"), .unavailable)
        XCTAssertEqual(s.itemCount(.abilityCapsule), 1)
    }

    // MARK: Ability Patch

    func testPatchGoesToAndFromTheHiddenAbility() async throws {
        let s = try await store([onix(slot: 2)], inventory: ["abilityPatch": 2], species: [95])
        XCTAssertEqual(s.useAbilityPatch(on: "onix"), .changed)
        XCTAssertEqual(ability(s, "onix")?.slot, 3)
        XCTAssertEqual(ability(s, "onix")?.hidden, true)
        XCTAssertEqual(ability(s, "onix")?.name, "weak-armor")
        XCTAssertEqual(s.useAbilityPatch(on: "onix"), .changed)
        XCTAssertEqual(ability(s, "onix")?.hidden, false)
        XCTAssertEqual(ability(s, "onix")?.name, "rock-head")
        XCTAssertEqual(s.itemCount(.abilityPatch), 0)
    }

    func testPatchWorksOnTheActivePokemon() async throws {
        let s = try await store([], inventory: ["abilityPatch": 1], species: [25])
        XCTAssertEqual(s.useAbilityPatch(on: TrainingFixture.activeID), .changed)
        XCTAssertEqual(s.state.active?.profile?.abilityName, "lightning-rod")
        XCTAssertEqual(s.state.active?.profile?.abilityIsHidden, true)
    }

    // MARK: Bottle Caps

    func testOneBottleCapSetsTheChosenIV() async throws {
        let s = try await store([onix(slot: 1)], inventory: ["bottleCap": 2], species: [])
        XCTAssertEqual(s.useBottleCap(on: "onix", stat: "speed"), .changed)
        let ivs = try XCTUnwrap(s.trainable(id: "onix")?.profile.ivs)
        XCTAssertEqual(ivs.speed, 31)
        XCTAssertEqual(ivs.attack, 20, "other IVs stay")
        XCTAssertEqual(s.itemCount(.bottleCap), 1)
    }

    func testBottleCapIsNotConsumedWhenTheIVIsAlready31() async throws {
        let s = try await store([onix(slot: 1)], inventory: ["bottleCap": 1], species: [])
        XCTAssertEqual(s.useBottleCap(on: "onix", stat: "defense"), .unchanged)
        XCTAssertEqual(s.useBottleCap(on: "onix", stat: "luck"), .unavailable)
        XCTAssertEqual(s.itemCount(.bottleCap), 1)
    }

    func testGoldBottleCapSetsAllSix() async throws {
        let s = try await store([onix(slot: 1)], inventory: ["goldBottleCap": 2], species: [])
        XCTAssertEqual(s.useGoldBottleCap(on: "onix"), .changed)
        let ivs = try XCTUnwrap(s.trainable(id: "onix")?.profile.ivs)
        for stat in PokemonStatCalculator.order { XCTAssertEqual(ivs[stat], 31, stat) }
        XCTAssertEqual(s.useGoldBottleCap(on: "onix"), .unchanged)
        XCTAssertEqual(s.itemCount(.goldBottleCap), 1)
    }

    // MARK: Form tools

    private static let formCases: [(tool: ItemKind, species: Int, forms: [String])] = [
        (.revealGlass, 641, ["therian", "incarnate"]),
        (.revealGlass, 642, ["therian", "incarnate"]),
        (.revealGlass, 645, ["therian", "incarnate"]),
        (.revealGlass, 905, ["therian", "incarnate"]),
        (.dnaSplicers, 646, ["black", "white", "normal"]),
        (.reinsOfUnity, 898, ["ice", "shadow", "normal"]),
    ]

    func testEachFormToolTogglesEveryFormAndTheUploadCarriesTheFormPokemonID() async throws {
        for (tool, species, forms) in Self.formCases {
            let id = "mon-\(species)"
            var state = TrainingFixture.state(dex: [TrainingFixture.graduate(id, speciesID: species)],
                                              inventory: [tool.rawValue: 1])
            state.raisedEntryID = id
            let fixture = try TrainingFixture(self)
            let s = try await fixture.store(state)
            for raw in forms {
                let form = PokemonForm(raw)
                XCTAssertEqual(s.changeForm(of: id, to: form), .changed, "\(species) → \(raw)")
                XCTAssertEqual(s.trainable(id: id)?.form, form)
                let expected = try XCTUnwrap(PokemonForm.entries(speciesID: species).first { $0.form == form })
                let member = try XCTUnwrap(PartyBuilder.party(from: s.state).first)
                XCTAssertEqual(member.pokemonID, expected.pokemonID ?? species, "\(species) \(raw)")
                XCTAssertTrue(PartyBuilder.isAcceptedPokemonID(member.pokemonID))
            }
            XCTAssertEqual(s.itemCount(tool), 1, "\(tool) is a key item and stays in the bag")
            XCTAssertEqual(s.changeForm(of: id, to: PokemonForm(forms.last!)), .unchanged)
        }
    }

    func testFormToolsNeedTheirOwnItem() async throws {
        let kyurem = TrainingFixture.graduate("kyurem", speciesID: 646)
        let s = try await store([kyurem], inventory: ["revealGlass": 1], species: [])
        XCTAssertEqual(s.changeForm(of: "kyurem", to: PokemonForm("black")), .unavailable)
        let owned = try await store([kyurem], inventory: ["dnaSplicers": 1], species: [])
        XCTAssertEqual(owned.changeForm(of: "kyurem", to: PokemonForm("therian")), .unavailable)
    }

    func testFormAbilityAndTypesFollowTheCurrentForm() async throws {
        let profile = TrainingFixture.profile("p-landorus", slot: 3, hidden: true, ability: "sheer-force")
        let landorus = TrainingFixture.graduate("landorus", speciesID: 645, profile: profile)
        let s = try await store([landorus], inventory: ["revealGlass": 1], species: [645])
        XCTAssertEqual(s.pokemonDetails(speciesID: 645, form: nil)?.types, ["ground", "flying"])
        XCTAssertEqual(s.changeForm(of: "landorus", to: PokemonForm("therian")), .changed)
        let form = s.trainable(id: "landorus")?.form
        XCTAssertEqual(FormBattleData.abilityName(speciesID: 645, form: form, profile: profile), "intimidate")
        XCTAssertEqual(s.pokemonDetails(speciesID: 645, form: form)?.baseStats["attack"], 145)
        let member = PartyBuilder.member(speciesID: 645, form: form, shiny: false, profile: profile)
        XCTAssertEqual(member.ability, "intimidate")
        XCTAssertEqual(member.pokemonID, 10021)
    }

    // MARK: Shop

    func testNewItemsArePricedAndSoldInTheShop() async throws {
        let prices: [ItemKind: Int] = [
            .abilityCapsule: 50_000_000, .abilityPatch: 200_000_000, .bottleCap: 50_000_000,
            .goldBottleCap: 300_000_000, .revealGlass: 150_000_000, .dnaSplicers: 150_000_000,
            .reinsOfUnity: 150_000_000, .mint: 20_000_000,
        ]
        let s = try await store([], inventory: [:], species: [])
        for (kind, price) in prices {
            XCTAssertEqual(kind.shopPrice, price, "\(kind)")
            XCTAssertTrue(s.purchasableItems.contains(kind), "\(kind)")
            XCTAssertNotEqual(s.l.itemName(kind), kind.rawValue, "\(kind) has a name")
            XCTAssertFalse(s.l.itemAppNote(kind).isEmpty, "\(kind) has an effect line")
        }
    }

    func testKeyItemsAreBoughtOnceAndConsumablesStack() async throws {
        let s = try await store([], inventory: [:], species: [])
        for tool in [ItemKind.revealGlass, .dnaSplicers, .reinsOfUnity] {
            XCTAssertTrue(tool.isKeyItem)
            XCTAssertEqual(s.maxBuyCount(tool), 1)
            XCTAssertTrue(s.buy(tool))
            XCTAssertTrue(s.isSoldOut(tool))
            XCTAssertFalse(s.canBuy(tool))
        }
        for consumable in [ItemKind.abilityCapsule, .abilityPatch, .bottleCap, .goldBottleCap] {
            XCTAssertFalse(consumable.isKeyItem)
            XCTAssertFalse(consumable.isBoughtOnce)
        }
        XCTAssertTrue(s.buy(.bottleCap))
        XCTAssertTrue(s.buy(.bottleCap))
        XCTAssertEqual(s.itemCount(.bottleCap), 2)
    }

    // MARK: Saves

    func testAnOldSaveDecodesUnchanged() throws {
        let json = #"{"economyVersion":2,"installBaselineSet":true,"usedSinceInstall":5,"lastDate":"d","#
            + #""active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":3,"nature":"adamant"},"#
            + #""inventory":{"mint":2},"dex":[{"id":"g","baseID":646,"finalID":646,"chainOrder":[646],"rarity":"legendary","form":"black"}],"#
            + #""collectedFinals":[]}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(state.active?.nature, .adamant)
        XCTAssertEqual(state.inventory, ["mint": 2])
        XCTAssertEqual(state.dex.first?.form, PokemonForm("black"))
    }

    static let newerSaveJSON = #"{"economyVersion":2,"installBaselineSet":true,"usedSinceInstall":5,"lastDate":"d","#
        + #""inventory":{"abilityCapsule":1,"abilityPatch":1,"bottleCap":3,"goldBottleCap":1,"revealGlass":1,"dnaSplicers":1,"reinsOfUnity":1,"mint":1},"#
        + #""dex":[{"id":"c","baseID":898,"finalID":898,"chainOrder":[898],"rarity":"legendary","form":"shadow"},"#
        + #"{"id":"e","baseID":905,"finalID":905,"chainOrder":[905],"rarity":"legendary","form":"therian"}],"collectedFinals":[]}"#

    func testANewerSaveDecodesOnTodaysDecoder() throws {
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(Self.newerSaveJSON.utf8))
        XCTAssertEqual(state.dex.count, 2)
        XCTAssertEqual(state.inventory["reinsOfUnity"], 1)
        XCTAssertEqual(state.dex.map(\.form), [PokemonForm("shadow"), PokemonForm("therian")])
    }

    func testAnUnknownFutureItemKeyIsKeptAndIgnored() throws {
        let json = #"{"economyVersion":2,"inventory":{"mint":1,"someFutureItem":4},"dex":[],"collectedFinals":[]}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(state.inventory["someFutureItem"], 4)
        XCTAssertEqual(state.inventory["mint"], 1)
    }
}
