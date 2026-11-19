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

    static func region(_ id: String, name: String = "Kanto", hidden: Bool = false) -> [String: Any] {
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
        var json: [String: Any] = [
            "id": id, "name": name, "first": 1, "last": 151, "gyms": gyms,
            "elite": ["run": "\(id)-elite", "badges_needed": 8, "battles": elite] as [String: Any],
            "hideout": ["run": "\(id)-hideout", "org": ["name": text("로켓단", "Rocket"), "types": ["poison", "dark"]],
                        "battles": hideout] as [String: Any],
        ]
        if hidden {
            var boss = opponent("\(id)-hidden", kind: "hidden", index: 1, types: [], trainer: ("숨은강자", "Hidden"))
            boss["finale"] = 1
            json["hidden"] = boss
        }
        return json
    }

    static func catalogData(regions: [(String, String)] = [("kanto", "Kanto"), ("johto", "Johto")], hidden: Bool = false) -> Data {
        let json: [String: Any] = ["ok": true, "regions": regions.map { region($0.0, name: $0.1, hidden: hidden) }]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    static func catalog(hidden: Bool = false) -> GymCatalog { try! GymCatalog.decode(catalogData(hidden: hidden)) }

    static func fighter(_ id: Int, name: String, level: Int = 50, hp: Int?, shiny: Bool = false) -> [String: Any] {
        ["pokemon_id": id, "name": name, "level": level, "types": ["normal"], "shiny": shiny, "hp": hp as Any? ?? NSNull()]
    }

    /// A battle reply; `run` is `(id, step, steps, first, next)`.
    static func outcomeData(gymID: String, kind: String, won: Bool, run: (String, Int, Int, String, String?)? = nil,
                            carry: [[String: Any]?]? = nil, hps: [Int?] = [80, 0, 35, nil, 100, 60],
                            foeHps: [Int?] = [0, 0, 0, 0, 0, 0], turns: Int = 12,
                            events: [[String: Any]]? = nil, teams: ([[String: Any]], [[String: Any]])? = nil) -> Data {
        let mine = teams?.0 ?? hps.enumerated().map { fighter(25 + $0.offset, name: "Mine\($0.offset)", hp: $0.element) }
        let theirs = teams?.1 ?? foeHps.enumerated().map { fighter(1 + $0.offset, name: "Foe\($0.offset)", hp: $0.element) }
        var json: [String: Any] = [
            "ok": true, "gym_id": gymID, "kind": kind, "won": won, "turns": turns, "seed": 42,
            "trainer": trainer("트레이너", "Trainer"), "player_team": mine, "foe_team": theirs,
            "log": [
                ["turn": 1, "lines": [["side": 0, "text": "Mine0 used Thunderbolt!"], ["side": 1, "text": "Foe0 fainted!"]]],
                ["turn": 2, "lines": [["side": NSNull(), "text": "A gust blows."]]],
            ],
        ]
        json["run"] = run.map { ["id": $0.0, "step": $0.1, "steps": $0.2, "first": $0.3, "next": $0.4 as Any? ?? NSNull()] as [String: Any] } ?? NSNull()
        json["carry"] = carry.map { entries in entries.map { entry -> Any in entry ?? NSNull() } } ?? NSNull()
        if let events { json["events"] = events }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    static func event(_ turn: Int, _ type: String, side: Int, member: Int, hp: Int? = nil, status: String? = nil,
                      move: String? = nil) -> [String: Any] {
        var event: [String: Any] = ["turn": turn, "type": type, "side": side, "member": member]
        if let hp { event["hp"] = hp }
        if type == "switch" || type == "status" { event["status"] = status as Any? ?? NSNull() }
        if let move { event["move"] = move }
        return event
    }

    /// Mine0 beats Foe0, takes a burn from Foe1 and faints; Mine1 comes in and finishes Foe1.
    static var replayEvents: [[String: Any]] { [
        event(0, "switch", side: 0, member: 0, hp: 100), event(0, "switch", side: 1, member: 0, hp: 100),
        event(1, "move", side: 0, member: 0, move: "10만볼트"), event(1, "damage", side: 1, member: 0, hp: 45),
        event(1, "move", side: 1, member: 0, move: "덩굴채찍"), event(1, "damage", side: 0, member: 0, hp: 70),
        event(2, "move", side: 0, member: 0, move: "10만볼트"), event(2, "damage", side: 1, member: 0, hp: 0),
        event(2, "faint", side: 1, member: 0), event(2, "switch", side: 1, member: 1, hp: 100),
        event(3, "move", side: 1, member: 1, move: "화염방사"), event(3, "damage", side: 0, member: 0, hp: 30),
        event(3, "status", side: 0, member: 0, status: "burn"),
        event(3, "move", side: 0, member: 0, move: "아이언테일"), event(3, "damage", side: 1, member: 1, hp: 55),
        event(3, "damage", side: 0, member: 0, hp: 24),
        event(4, "move", side: 1, member: 1, move: "화염방사"), event(4, "damage", side: 0, member: 0, hp: 0),
        event(4, "faint", side: 0, member: 0), event(4, "switch", side: 0, member: 1, hp: 100),
        event(5, "move", side: 0, member: 1, move: "파도타기"), event(5, "damage", side: 1, member: 1, hp: 0),
        event(5, "faint", side: 1, member: 1),
    ] }

    static func form(_ turn: Int, side: Int, member: Int, id: Int, kind: String = "mega") -> [String: Any] {
        ["turn": turn, "type": "form", "side": side, "member": member, "pokemon_id": id, "kind": kind]
    }

    /// `replayEvents` with Foe1 (Charizard) Mega Evolving into Mega Charizard X right after it comes out.
    static var megaReplayEvents: [[String: Any]] {
        var events = replayEvents
        events.insert(form(2, side: 1, member: 1, id: 10034), at: 10)
        return events
    }

    /// `replayEvents` with Foe1 (Ditto) transforming into the player's Pikachu right after it comes out.
    static var imposterReplayEvents: [[String: Any]] {
        var events = replayEvents
        events.insert(form(2, side: 1, member: 1, id: 25, kind: "transform"), at: 10)
        return events
    }

    /// `replayEvents` with Foe1 (Aegislash) taking its Blade Forme through Stance Change as it first attacks.
    static var stanceChangeReplayEvents: [[String: Any]] {
        var events = replayEvents.map { event -> [String: Any] in
            guard event["type"] as? String == "move", event["side"] as? Int == 1, event["member"] as? Int == 1 else {
                return event
            }
            return event.merging(["move": "섀도크루"]) { $1 }
        }
        events.insert(form(3, side: 1, member: 1, id: 10026, kind: "blade"), at: 10)
        return events
    }

    static func carryJSON(hp: Int, status: String? = nil) -> [String: Any] { ["hp": hp, "status": status as Any? ?? NSNull()] }
}
