import Foundation
import XCTest
@testable import PokeTokenBar

@MainActor
final class RemoteTrainTests: XCTestCase {
    // MARK: Each action applies

    func testAMintFromTheBagSetsTheNatureAndUsesTheMint() async throws {
        let rig = try await rig(inventory: ["mint": 1])
        XCTAssertNil(apply(rig, ["action": "nature", "id": "pika", "pokemon_id": 25, "nature": "timid"]))
        XCTAssertEqual(rig.store.trainable(id: "pika")?.nature, .timid)
        XCTAssertEqual(rig.store.itemCount(.mint), 0)
        XCTAssertEqual(rig.store.state.spentTokens, 0)
    }

    func testAMintWithNoneInTheBagIsBoughtAtTheShopLinesPrice() async throws {
        let rig = try await rig()
        let line = try XCTUnwrap(rig.store.remoteShop.first { $0.key == ItemKind.mint.rawValue })
        XCTAssertNil(apply(rig, ["action": "nature", "id": "pika", "pokemon_id": 25, "nature": "timid", "price": line.price]))
        XCTAssertEqual(rig.store.trainable(id: "pika")?.nature, .timid)
        XCTAssertEqual(rig.store.state.spentTokens, line.price)
    }

    func testAMirrorHerbIsBoughtAtTheShopLinesPriceAndUnlocksEggMoves() async throws {
        let rig = try await rig()
        let line = try XCTUnwrap(rig.store.remoteShop.first { $0.key == ItemKind.mirrorHerb.rawValue })
        XCTAssertNil(apply(rig, ["action": "herb", "id": "pika", "pokemon_id": 25, "price": line.price]))
        XCTAssertEqual(rig.store.trainable(id: "pika")?.profile.mirrorHerb, true)
        XCTAssertEqual(rig.store.state.spentTokens, line.price)
    }

    func testTheCapsuleAndThePatchGiveTheAbilityTheBotShowed() async throws {
        let rig = try await rig(inventory: ["abilityCapsule": 1, "abilityPatch": 1], details: [95, 25])
        XCTAssertNil(apply(rig, ability("capsule", "onix", 95, "sturdy", slot: 2, hidden: false)))
        XCTAssertEqual(rig.store.trainable(id: "onix")?.profile.abilityName, "sturdy")
        XCTAssertNil(apply(rig, ability("patch", "pika", 25, "lightning-rod", slot: 3, hidden: true)))
        XCTAssertEqual(rig.store.trainable(id: "pika")?.profile.abilityIsHidden, true)
        XCTAssertEqual(rig.store.itemCount(.abilityCapsule) + rig.store.itemCount(.abilityPatch), 0)
    }

    func testTheSyncLoadsTheAbilityOptionsACapsuleOpChecks() async throws {
        let rig = try await rig(inventory: ["abilityCapsule": 1])
        let op = trainOp(1, ability("capsule", "onix", 95, "sturdy", slot: 2, hidden: false))
        XCTAssertEqual(RemoteTrain.apply(op.payload, store: rig.store, battleEntry: rig.battle), RemoteTrain.Reason.noData)
        await rig.store.prepareRemoteOps([op])
        rig.store.applyRemoteOps([op], appliers: RemoteOpAppliers.all(battleEntry: rig.battle))
        XCTAssertEqual(rig.store.state.remoteOpResults, [RemoteOpResult(id: 1)])
    }

    func testBottleCapsMaxOneIVOrAllSix() async throws {
        let rig = try await rig(inventory: ["bottleCap": 1, "goldBottleCap": 1])
        XCTAssertNil(apply(rig, ["action": "cap", "id": "pika", "pokemon_id": 25, "stat": "special-attack"]))
        XCTAssertEqual(rig.store.trainable(id: "pika")?.profile.ivs["special-attack"], BottleCap.maxIV)
        XCTAssertNil(apply(rig, ["action": "gold_cap", "id": "onix", "pokemon_id": 95]))
        let ivs = try XCTUnwrap(rig.store.trainable(id: "onix")?.profile.ivs)
        XCTAssertTrue(PokemonStatCalculator.order.allSatisfy { ivs[$0] == BottleCap.maxIV })
    }

    func testAFormChangeSwitchesTheFormAndKeepsTheKeyItem() async throws {
        let rig = try await rig(inventory: ["revealGlass": 1])
        XCTAssertNil(apply(rig, ["action": "form", "id": "thund", "pokemon_id": 642, "form": "therian", "to_pokemon_id": 10020]))
        XCTAssertEqual(rig.store.trainable(id: "thund")?.form, PokemonForm("therian"))
        XCTAssertEqual(rig.store.itemCount(.revealGlass), 1)
    }

    func testMovesAreSetAndAnEmptyListGoesBackToTheDefaults() async throws {
        let rig = try await rig(inventory: [MachineMove.inventoryKey(87): 1])
        XCTAssertNil(apply(rig, moves("pika", 25, [87, 85], machine: [87])))
        XCTAssertEqual(rig.battle.moveChoices["pika"], MoveChoice(pokemonID: 25, moves: [87, 85], machine: [87]))
        XCTAssertNil(apply(rig, moves("pika", 25, [])))
        XCTAssertNil(rig.battle.moveChoices["pika"])
    }

    func testEggMovesFollowAMirrorHerbUsedEarlierInTheSameSync() async throws {
        let rig = try await rig(inventory: ["mirrorHerb": 1])
        rig.store.applyRemoteOps([trainOp(1, ["action": "herb", "id": "pika", "pokemon_id": 25]),
                                  trainOp(2, moves("pika", 25, [57], egg: [57]))],
                                 appliers: RemoteOpAppliers.all(battleEntry: rig.battle))
        XCTAssertEqual(rig.store.state.remoteOpResults, [RemoteOpResult(id: 1), RemoteOpResult(id: 2)])
        XCTAssertEqual(rig.battle.moveChoices["pika"]?.moves, [57])
    }

    // MARK: Cancelling with nothing changed

    func testWhatNoLongerAppliesCancelsWithNothingChanged() async throws {
        let mint = try XCTUnwrap(ItemKind.mint.shopPrice)
        let cases: [(String, [String: Any], [String: Int], Int)] = [
            (RemoteTrain.Reason.gone, ["action": "nature", "id": "nobody", "pokemon_id": 25, "nature": "timid"], ["mint": 1], 0),
            (RemoteTrain.Reason.evolved, ["action": "nature", "id": "pika", "pokemon_id": 26, "nature": "timid"], ["mint": 1], 0),
            (RemoteTrain.Reason.unchanged, ["action": "nature", "id": "pika", "pokemon_id": 25, "nature": "lonely"], ["mint": 1], 0),
            (RemoteTrain.Reason.noItem, ["action": "nature", "id": "pika", "pokemon_id": 25, "nature": "timid"], [:], 0),
            (RemoteTrain.Reason.priceChanged, ["action": "nature", "id": "pika", "pokemon_id": 25, "nature": "timid",
                                               "price": mint - 1], [:], 0),
            (RemoteTrain.Reason.noTokens, ["action": "nature", "id": "pika", "pokemon_id": 25, "nature": "timid",
                                           "price": mint], [:], mint - 1),
            (RemoteTrain.Reason.notApplicable, ["action": "herb", "id": "pie", "pokemon_id": 10, "price": 1], [:], 0),
            (RemoteTrain.Reason.noItem, ability("capsule", "onix", 95, "sturdy", slot: 2, hidden: false), [:], 0),
            (RemoteTrain.Reason.notApplicable, ability("capsule", "onix", 95, "weak-armor", slot: 3, hidden: true),
             ["abilityCapsule": 1], 0),
            (RemoteTrain.Reason.noItem, ["action": "cap", "id": "pika", "pokemon_id": 25, "stat": "speed"], [:], 0),
            (RemoteTrain.Reason.unchanged, ["action": "cap", "id": "pika", "pokemon_id": 25, "stat": "defense"],
             ["bottleCap": 1], 0),
            (RemoteTrain.Reason.noItem, ["action": "form", "id": "thund", "pokemon_id": 642, "form": "therian",
                                         "to_pokemon_id": 10020], [:], 0),
            (RemoteTrain.Reason.notApplicable, ["action": "form", "id": "thund", "pokemon_id": 642, "form": "therian",
                                                "to_pokemon_id": 10019], ["revealGlass": 1], 0),
            (RemoteTrain.Reason.noMachine, moves("pika", 25, [87], machine: [87]), [:], 0),
            (RemoteTrain.Reason.noHerb, moves("pika", 25, [57], egg: [57]), [:], 0),
            (RemoteTrain.Reason.invalid, ["action": "dance", "id": "pika", "pokemon_id": 25], [:], 0),
        ]
        for (reason, payload, inventory, wallet) in cases {
            let rig = try await rig(inventory: inventory, tokens: wallet > 0 ? wallet : 1_000_000_000, details: [95])
            let before = rig.store.state
            XCTAssertEqual(apply(rig, payload), reason, "\(payload)")
            XCTAssertEqual(rig.store.state.inventory, before.inventory, "\(payload)")
            XCTAssertEqual(rig.store.state.spentTokens, before.spentTokens, "\(payload)")
            XCTAssertEqual(individuals(rig.store.state), individuals(before), "\(payload)")
            XCTAssertTrue(rig.battle.moveChoices.isEmpty, "\(payload)")
        }
    }

    // MARK: Order with buy ops, and idempotency

    func testAMintBoughtInSlackIsUsedByTheTrainingAfterIt() async throws {
        let rig = try await rig()
        let price = try XCTUnwrap(rig.store.remoteShop.first { $0.key == ItemKind.mint.rawValue }).price
        let buy = try JSONSerialization.data(withJSONObject: ["key": "mint", "name": "민트", "count": 1, "price": price])
        rig.store.applyRemoteOps([RemoteOp(id: 1, kind: RemoteBuy.kind, payload: buy),
                                  trainOp(2, ["action": "nature", "id": "pika", "pokemon_id": 25, "nature": "timid"])],
                                 appliers: RemoteOpAppliers.all(battleEntry: rig.battle))
        XCTAssertEqual(rig.store.state.remoteOpResults, [RemoteOpResult(id: 1), RemoteOpResult(id: 2)])
        XCTAssertEqual(rig.store.trainable(id: "pika")?.nature, .timid)
        XCTAssertEqual(rig.store.itemCount(.mint), 0)
        XCTAssertEqual(rig.store.state.spentTokens, price)
    }

    func testATrainingAppliedBeforeARestartIsNotAppliedAgain() async throws {
        let rig = try await rig()
        let price = try XCTUnwrap(rig.store.remoteShop.first { $0.key == ItemKind.mint.rawValue }).price
        let op = trainOp(1, ["action": "nature", "id": "pika", "pokemon_id": 25, "nature": "timid", "price": price])
        rig.store.applyRemoteOps([op], appliers: RemoteOpAppliers.all(battleEntry: rig.battle))

        let store = rig.fixture.reload()
        store.applyRemoteOps([op], appliers: RemoteOpAppliers.all(battleEntry: rig.battle))

        XCTAssertEqual(store.state.remoteOpResults, [RemoteOpResult(id: 1)])
        XCTAssertEqual(store.trainable(id: "pika")?.nature, .timid)
        XCTAssertEqual(store.state.spentTokens, price)
    }

    // MARK: What the upload tells Slack

    func testTheAppAdvertisesTrainOps() async throws {
        let rig = try await rig()
        XCTAssertTrue(RemoteOpsSync(store: rig.store, battleEntry: rig.battle).kinds.contains(RemoteTrain.kind))
    }

    func testTheUploadCarriesTheAbilitySlotEggMovesAndTheFormsOfAFormToolSpecies() async throws {
        let rig = try await rig()
        let slots = ["thund", "pika", "onix"].map { BattleEntrySlot(instanceID: $0) }
        let party = BattleEntry.party(state: rig.store.state, slots: slots, moveChoices: [:], rentalSpeciesID: 25)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(party)) as? [[String: Any]])
        let members = Dictionary(uniqueKeysWithValues: json.map { ($0["id"] as? String ?? "", $0) })
        let thundurus = try XCTUnwrap(members["thund"])
        XCTAssertEqual(thundurus["ability_slot"] as? Int, 1)
        XCTAssertEqual(thundurus["form"] as? String, "incarnate")
        XCTAssertEqual(thundurus["form_tool"] as? String, "revealGlass")
        let forms = try XCTUnwrap(thundurus["forms"] as? [[String: Any]])
        XCTAssertEqual(forms.map { $0["pokemon_id"] as? Int }, [642, 10020])
        XCTAssertEqual(forms.map { $0["ability"] as? String }, [nil, "volt-absorb"])
        XCTAssertEqual(members["pika"]?["egg_moves"] as? Bool, true)
        XCTAssertNil(members["onix"]?["form_tool"])
    }

    // MARK: Helpers

    private struct Rig {
        let fixture: TrainingFixture
        let store: CompanionStore
        let battle: BattleEntryStore
    }

    /// Pikachu `pika`, Onix `onix` (Rock Head), Incarnate Thundurus `thund` and Caterpie `pie` in the Box.
    private func rig(inventory: [String: Int] = [:], tokens: Int = 1_000_000_000, details: [Int] = []) async throws -> Rig {
        let fixture = try TrainingFixture(self)
        let dex = [
            TrainingFixture.graduate("pika", speciesID: 25),
            TrainingFixture.graduate("onix", speciesID: 95, profile: TrainingFixture.profile("p-onix", ability: "rock-head")),
            TrainingFixture.graduate("thund", speciesID: 642, form: PokemonForm("incarnate")),
            TrainingFixture.graduate("pie", speciesID: 10),
        ]
        let state = TrainingFixture.state(dex: dex, inventory: inventory, tokens: tokens)
        let store = try await fixture.store(state, loadDetailsFor: details)
        let battle = BattleEntryStore(defaults: fixture.defaults)
        return Rig(fixture: fixture, store: store, battle: battle)
    }

    private func individuals(_ state: CompanionState) -> [TrainableIndividual?] {
        state.dex.map { TrainableIndividual.find(id: $0.id, in: state) }
    }

    private func apply(_ rig: Rig, _ payload: [String: Any]) -> String? {
        RemoteTrain.apply(data(payload), store: rig.store, battleEntry: rig.battle)
    }

    private func trainOp(_ id: Int, _ payload: [String: Any]) -> RemoteOp {
        RemoteOp(id: id, kind: RemoteTrain.kind, payload: data(payload))
    }

    private func data(_ payload: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private func ability(_ action: String, _ id: String, _ pokemonID: Int, _ name: String, slot: Int,
                         hidden: Bool) -> [String: Any] {
        ["action": action, "id": id, "pokemon_id": pokemonID,
         "ability": ["name": name, "slot": slot, "hidden": hidden, "label": name]]
    }

    private func moves(_ id: String, _ pokemonID: Int, _ moves: [Int], machine: [Int] = [],
                       egg: [Int] = []) -> [String: Any] {
        ["action": "moves", "id": id, "pokemon_id": pokemonID, "moves": moves, "machine": machine, "egg": egg]
    }
}
