import Foundation
@testable import PokeTokenBar

/// JSON in the shape `bot/API.md` "Gyms (PvE)" documents, built from plain dictionaries so tests decode what the bot sends.
enum GymFixtures {
    static let gymTypes = ["rock", "water", "electric", "grass", "poison", "psychic", "fire", "ground"]
    static let eliteTypes = ["ice", "fighting", "ghost", "dragon"]

    static func text(_ ko: String, _ en: String) -> [String: Any] { ["ko": ko, "en": en] }

    static func trainer(_ ko: String, _ en: String) -> [String: Any] {
        ["name": text(ko, en), "line": text("\(ko)의 한마디", "\(en) says hi")]
    }

    static func opponent(_ id: String, kind: String, index: Int, types: [String], trainer name: (String, String),
                         run: (String, Int, Int)? = nil) -> [String: Any] {
        var json: [String: Any] = [
            "id": id, "kind": kind, "index": index, "types": types, "level": 50,
            "trainer": trainer(name.0, name.1), "team": [25, 6, 9, 3, 94, 149],
        ]
        json["run"] = run.map { ["id": $0.0, "step": $0.1, "steps": $0.2] as [String: Any] } ?? NSNull()
        return json
    }

    static func region(_ id: String, name: String = "Kanto") -> [String: Any] {
        let gyms = (1...8).map {
            opponent("\(id)-\($0)", kind: "gym", index: $0, types: [gymTypes[$0 - 1]], trainer: ("관장\($0)", "Leader \($0)"))
        }
        var elite = (1...4).map {
            opponent("\(id)-elite-\($0)", kind: "elite", index: $0, types: [eliteTypes[$0 - 1]],
                     trainer: ("사천왕\($0)", "Elite \($0)"), run: ("\(id)-elite", $0, 5))
        }
        elite.append(opponent("\(id)-champion", kind: "champion", index: 5, types: [], trainer: ("챔피언", "Champion"),
                              run: ("\(id)-elite", 5, 5)))
        let hideout = [
            opponent("\(id)-hideout-1", kind: "grunt", index: 1, types: ["poison", "dark"], trainer: ("단원1", "Grunt 1"),
                     run: ("\(id)-hideout", 1, 4)),
            opponent("\(id)-hideout-2", kind: "grunt", index: 2, types: ["poison", "dark"], trainer: ("단원2", "Grunt 2"),
                     run: ("\(id)-hideout", 2, 4)),
            opponent("\(id)-hideout-3", kind: "admin", index: 3, types: ["poison", "dark"], trainer: ("간부", "Admin"),
                     run: ("\(id)-hideout", 3, 4)),
            opponent("\(id)-hideout-4", kind: "boss", index: 4, types: ["poison", "dark"], trainer: ("두목", "Boss"),
                     run: ("\(id)-hideout", 4, 4)),
        ]
        return [
            "id": id, "name": name, "first": 1, "last": 151, "gyms": gyms,
            "elite": ["run": "\(id)-elite", "badges_needed": 8, "battles": elite] as [String: Any],
            "hideout": ["run": "\(id)-hideout", "org": ["name": text("로켓단", "Rocket"), "types": ["poison", "dark"]],
                        "battles": hideout] as [String: Any],
        ]
    }

    static func catalogData(regions: [(String, String)] = [("kanto", "Kanto"), ("johto", "Johto")]) -> Data {
        let json: [String: Any] = ["ok": true, "regions": regions.map { region($0.0, name: $0.1) }]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    static func catalog() -> GymCatalog { try! GymCatalog.decode(catalogData()) }

    static func fighter(_ id: Int, name: String, level: Int = 50, hp: Int?, shiny: Bool = false) -> [String: Any] {
        ["pokemon_id": id, "name": name, "level": level, "types": ["normal"], "shiny": shiny, "hp": hp as Any? ?? NSNull()]
    }

    /// A battle reply; `run` is `(id, step, steps, first, next)`.
    static func outcomeData(gymID: String, kind: String, won: Bool, run: (String, Int, Int, String, String?)? = nil,
                            carry: [[String: Any]?]? = nil, hps: [Int?] = [80, 0, 35, nil, 100, 60],
                            foeHps: [Int?] = [0, 0, 0, 0, 0, 0]) -> Data {
        let mine = hps.enumerated().map { fighter(25 + $0.offset, name: "Mine\($0.offset)", hp: $0.element) }
        let theirs = foeHps.enumerated().map { fighter(1 + $0.offset, name: "Foe\($0.offset)", hp: $0.element) }
        var json: [String: Any] = [
            "ok": true, "gym_id": gymID, "kind": kind, "won": won, "turns": 12, "seed": 42,
            "trainer": trainer("트레이너", "Trainer"), "player_team": mine, "foe_team": theirs,
            "log": [
                ["turn": 1, "lines": [["side": 0, "text": "Mine0 used Thunderbolt!"], ["side": 1, "text": "Foe0 fainted!"]]],
                ["turn": 2, "lines": [["side": NSNull(), "text": "A gust blows."]]],
            ],
        ]
        json["run"] = run.map { ["id": $0.0, "step": $0.1, "steps": $0.2, "first": $0.3, "next": $0.4 as Any? ?? NSNull()] as [String: Any] } ?? NSNull()
        json["carry"] = carry.map { entries in entries.map { entry -> Any in entry ?? NSNull() } } ?? NSNull()
        return try! JSONSerialization.data(withJSONObject: json)
    }

    static func carryJSON(hp: Int, status: String? = nil) -> [String: Any] { ["hp": hp, "status": status as Any? ?? NSNull()] }
}
