import Foundation

/// The battle info the YPoke bot adds to its `POST /v1/party` reply (`bot/API.md`).
struct BattleInfo: Codable, Equatable, Sendable {
    var recentBattles: [RecentBattle] = []
    var coworkers: [Coworker] = []

    struct RecentBattle: Codable, Equatable, Sendable {
        /// Nil when the bot could not look the name up.
        var opponentName: String?
        /// Nil for battles the bot stored before it kept the species.
        var myPokemonId: Int?
        var opponentPokemonId: Int?
        /// `"win"` or `"loss"`, from the uploader's side.
        var result: String
        var turns: Int?
        /// ISO 8601 UTC.
        var at: String?

        var isWin: Bool { result == "win" }

        var date: Date? { at.flatMap { ISO8601DateFormatter().date(from: $0) } }
    }

    struct Coworker: Codable, Equatable, Sendable {
        /// Nil when the bot could not look the name up.
        var name: String?
        var pokemonId: Int
        var level: Int
        var shiny: Bool = false
    }

    /// The sprite for a bot-side Pokémon id: the species itself, or the species and form that own an
    /// alternate-form id. Nil for ids the app has no sprite for.
    static func spriteTarget(pokemonID: Int) -> (speciesID: Int, form: PokemonForm?)? {
        if (1...1025).contains(pokemonID) { return (pokemonID, nil) }
        for (speciesID, entries) in PokemonForm.catalog {
            if let entry = entries.first(where: { $0.pokemonID == pokemonID }) { return (speciesID, entry.form) }
        }
        return nil
    }

    private struct Reply: Decodable {
        var recentBattles: [RecentBattle]?
        var coworkers: [Coworker]?
    }

    /// Nil for a reply from a bot without these fields, so the caller keeps what it has.
    static func decode(_ data: Data) -> BattleInfo? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let reply = try? decoder.decode(Reply.self, from: data),
              reply.recentBattles != nil || reply.coworkers != nil
        else { return nil }
        return BattleInfo(recentBattles: reply.recentBattles ?? [], coworkers: reply.coworkers ?? [])
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(self)
    }
}
