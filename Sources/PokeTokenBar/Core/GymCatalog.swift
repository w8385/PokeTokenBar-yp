import Foundation

/// `GET /v1/gyms`: nine regions of gyms, an Elite Four run and a villain hideout run (`bot/API.md` "Gyms (PvE)").
struct GymCatalog: Decodable, Equatable, Sendable {
    let regions: [GymRegion]

    static func decode(_ data: Data) throws -> GymCatalog {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GymCatalog.self, from: data)
    }

    func region(_ id: String) -> GymRegion? { regions.first { $0.id == id } }
}

struct GymRegion: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let first: Int
    let last: Int
    let gyms: [GymOpponent]
    let elite: GymEliteRun
    let hideout: GymHideoutRun

    /// The opponent a battle id names, in any of the region's three groups.
    func opponent(_ battleID: String) -> GymOpponent? {
        (gyms + elite.battles + hideout.battles).first { $0.id == battleID }
    }
}

struct GymEliteRun: Decodable, Equatable, Sendable {
    let run: String
    /// How many gym badges the app asks for before the run opens; the bot does not check.
    let badgesNeeded: Int
    let battles: [GymOpponent]
}

struct GymHideoutRun: Decodable, Equatable, Sendable {
    let run: String
    let org: GymOrg
    let battles: [GymOpponent]
}

struct GymOrg: Decodable, Equatable, Sendable {
    let name: [String: String]
    let types: [String]

    func displayName(_ language: AppLanguage) -> String { GymTrainer.pick(name, language) }
}

struct GymTrainer: Decodable, Equatable, Sendable {
    let name: [String: String]
    let line: [String: String]

    func displayName(_ language: AppLanguage) -> String { Self.pick(name, language) }
    func displayLine(_ language: AppLanguage) -> String { Self.pick(line, language) }

    /// Korean and Japanese have their own text; every other language shows the English one.
    static func pick(_ texts: [String: String], _ language: AppLanguage) -> String {
        switch language {
        case .ko: texts["ko"] ?? texts["en"] ?? ""
        case .ja: texts["ja"] ?? texts["en"] ?? ""
        default: texts["en"] ?? texts["ko"] ?? ""
        }
    }
}

/// Where a battle stands in its run; the bot sends it for every battle that has one.
struct GymRunPosition: Decodable, Equatable, Sendable {
    let id: String
    let step: Int
    let steps: Int
}

struct GymOpponent: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    /// `gym`, `elite`, `champion`, `grunt`, `admin` or `boss`.
    let kind: String
    let index: Int
    let types: [String]
    let level: Int
    let trainer: GymTrainer
    let team: [Int]
    let run: GymRunPosition?
    /// Members the champion keeps hidden after `team`; nil from a bot older than the finale.
    var finale: Int? = nil

    var isRunFinale: Bool { kind == "champion" || kind == "boss" }
}
