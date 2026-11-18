import AppKit
import Foundation
@testable import PokeTokenBar

/// PokéAPI move names by id for the moves the test fixtures use. Unknown ids fail like an unreachable PokéAPI.
struct StubMoveNames: PokemonNameProviding {
    static let table: [Int: [String: String]] = [
        14: ["ko": "칼춤", "en": "Swords Dance", "ja": "つるぎのまい"],
        22: ["ko": "덩굴채찍", "en": "Vine Whip", "ja": "つるのムチ"],
        52: ["ko": "불꽃세례", "en": "Ember", "ja": "ひのこ"],
        53: ["ko": "화염방사", "en": "Flamethrower", "ja": "かえんほうしゃ"],
        57: ["ko": "파도타기", "en": "Surf", "ja": "なみのり"],
        84: ["ko": "전기쇼크", "en": "Thunder Shock", "ja": "でんきショック"],
        85: ["ko": "10만볼트", "en": "Thunderbolt", "ja": "10まんボルト"],
        86: ["ko": "전기자석파", "en": "Thunder Wave", "ja": "でんじは"],
        89: ["ko": "지진", "en": "Earthquake", "ja": "じしん"],
        209: ["ko": "스파크", "en": "Spark", "ja": "スパーク"],
        225: ["ko": "용의숨결", "en": "Dragon Breath", "ja": "りゅうのいぶき"],
        231: ["ko": "아이언테일", "en": "Iron Tail", "ja": "アイアンテール"],
        246: ["ko": "원시의힘", "en": "Ancient Power", "ja": "げんしのちから"],
        281: ["ko": "하품", "en": "Yawn", "ja": "あくび"],
        337: ["ko": "드래곤크루", "en": "Dragon Claw", "ja": "ドラゴンクロー"],
        344: ["ko": "볼트태클", "en": "Volt Tackle", "ja": "ボルテッカー"],
        407: ["ko": "드래곤다이브", "en": "Dragon Rush", "ja": "ドラゴンダイブ"],
        433: ["ko": "트릭룸", "en": "Trick Room", "ja": "トリックルーム"],
        446: ["ko": "스텔스록", "en": "Stealth Rock", "ja": "ステルスロック"],
    ]

    func names(for resource: PokemonNameResource) async throws -> [String: String] {
        guard resource.kind == .move, let id = Int(resource.name), let names = Self.table[id] else {
            throw URLError(.cannotFindHost)
        }
        return names
    }
}

/// Holds every request until `release()`, then answers from `StubMoveNames`.
actor GatedMoveNames: PokemonNameProviding {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var open = false
    private(set) var requested: Set<String> = []

    func names(for resource: PokemonNameResource) async throws -> [String: String] {
        requested.insert(resource.name)
        if !open { await withCheckedContinuation { waiting.append($0) } }
        return try await StubMoveNames().names(for: resource)
    }

    func release() {
        open = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

enum MoveNameFixtures {
    /// GymFixtures' replay with the bot's `move_id` on every move.
    static var replayEvents: [[String: Any]] {
        let ids = ["10만볼트": 85, "덩굴채찍": 22, "화염방사": 53, "아이언테일": 231, "파도타기": 57]
        return GymFixtures.replayEvents.map { event in
            var event = event
            if let name = event["move"] as? String { event["move_id"] = ids[name] }
            return event
        }
    }

    /// `statusMovesJSON` from a bot that already sent English names.
    static var englishStatusMovesJSON: String {
        StubMoveNames.table.values.reduce(statusMovesJSON) { json, names in
            json.replacingOccurrences(of: #""name":"\#(names["ko"]!)""#, with: #""name":"\#(names["en"]!)""#)
        }
    }
}

/// Answers every move with its `code` name as the English one, so a reference drawing goes through the translated
/// branch and never through the fallback it is compared against.
struct FixedMoveNames: PokemonNameProviding {
    let code: String

    func names(for resource: PokemonNameResource) async throws -> [String: String] {
        let names = try await StubMoveNames().names(for: resource)
        return ["en": names[code]!]
    }
}

/// PokéAPI unreachable.
struct FailingMoveNames: PokemonNameProviding {
    func names(for resource: PokemonNameResource) async throws -> [String: String] { throw URLError(.cannotFindHost) }
}
