import Foundation

/// The dex summary in the YPoke bot's `POST /v1/party` body (`bot/API.md`).
struct DexSummary: Encodable, Equatable, Sendable {
    struct Representative: Encodable, Equatable, Sendable {
        let pokemonID: Int
        let shiny: Bool
    }

    let owned: Int
    let shiny: Int
    /// Owned species per region, keyed by `PokedexRegion.rawValue`.
    let regions: [String: Int]
    /// Nil while the user has only an egg.
    let representative: Representative?

    init(national: (owned: Int, shinyOwned: Int, total: Int), completions: [DexCompletion],
         representative: CompanionStore.RepresentativeSubject) {
        owned = national.owned
        shiny = national.shinyOwned
        regions = Dictionary(uniqueKeysWithValues: completions.map { ($0.region.rawValue, $0.owned) })
        self.representative = representative.speciesID.map {
            let member = PartyBuilder.member(speciesID: $0, form: representative.form,
                                             shiny: representative.isShiny, profile: nil)
            return Representative(pokemonID: member.pokemonID, shiny: representative.isShiny)
        }
    }

    @MainActor
    init(_ companion: CompanionStore) {
        self.init(national: companion.nationalDexProgress, completions: companion.dexCompletions,
                  representative: companion.representativeSubject)
    }
}
