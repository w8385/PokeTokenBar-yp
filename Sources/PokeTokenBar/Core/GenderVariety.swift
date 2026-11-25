import Foundation

/// Species whose female is its own PokéAPI variety with its own stats and abilities (Indeedee ♀, Basculegion ♀).
/// The individual's stored gender picks it; it is not a `PokemonForm`, so a Basculegion keeps its Basculin stripe.
enum GenderVariety {
    static let femalePokemonIDs: [Int: Int] = [678: 10025, 876: 10186, 902: 10248, 916: 10254]

    static func pokemonID(speciesID: Int, gender: PokemonGender?) -> Int? {
        gender == .female ? femalePokemonIDs[speciesID] : nil
    }

    /// The species and gender a female variety id stands for.
    static func species(ofPokemonID pokemonID: Int) -> Int? {
        femalePokemonIDs.first { $0.value == pokemonID }?.key
    }
}

extension PokemonForm {
    /// The PokéAPI variety an individual is: its gender variety, else its form's variety, else nil for the species itself.
    static func varietyID(speciesID: Int, form: PokemonForm?, gender: PokemonGender?) -> Int? {
        if let id = GenderVariety.pokemonID(speciesID: speciesID, gender: gender) { return id }
        let resolved = resolved(speciesID: speciesID, form: form)
        return entries(speciesID: speciesID).first { $0.form == resolved }?.pokemonID
    }
}
