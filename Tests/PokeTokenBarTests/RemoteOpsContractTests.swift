import Foundation
import XCTest
@testable import PokeTokenBar

/// Checks the app side of `bot/contract/remote_ops.json`; `bot/tests/test_remote_contract.py` checks the bot side.
@MainActor
final class RemoteOpsContractTests: XCTestCase {
    private struct Contract: Decodable {
        struct Op: Decodable {
            let botReasons: [String]
            let appReasons: [String]
            let actions: [String]
        }
        let unsupportedReason: String
        let ops: [String: Op]
        let trainStats: [String]
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func contract() throws -> Contract {
        let url = Self.repoRoot.appendingPathComponent("bot/contract/remote_ops.json")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Contract.self, from: Data(contentsOf: url))
    }

    func testTheAppAppliesTheContractKinds() throws {
        let suite = "RemoteOpsContractTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let battleEntry = BattleEntryStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        let expected = Set(try contract().ops.keys)
        XCTAssertEqual(Set(RemoteOpAppliers.all(battleEntry: battleEntry).keys), expected)
        XCTAssertEqual(Set([RemoteBuy.kind, RemoteLineup.kind, RemoteTrain.kind]), expected)
    }

    func testTheUnsupportedReasonMatches() throws {
        XCTAssertEqual(RemoteOpReason.unsupported, try contract().unsupportedReason)
    }

    func testTheAppReasonsMatchTheContract() throws {
        let contract = try contract()
        let buy = [RemoteBuy.Reason.notSold, RemoteBuy.Reason.priceChanged, RemoteBuy.Reason.noTokens,
                   RemoteBuy.Reason.invalid]
        let lineup = [RemoteLineup.Reason.gone, RemoteLineup.Reason.evolved, RemoteLineup.Reason.tradeLocked,
                      RemoteLineup.Reason.noItem, RemoteLineup.Reason.noMachine, RemoteLineup.Reason.speciesClause,
                      RemoteLineup.Reason.itemClause, RemoteLineup.Reason.invalid]
        let train = [RemoteTrain.Reason.gone, RemoteTrain.Reason.evolved, RemoteTrain.Reason.tradeLocked,
                     RemoteTrain.Reason.noItem, RemoteTrain.Reason.noTokens, RemoteTrain.Reason.priceChanged,
                     RemoteTrain.Reason.unchanged, RemoteTrain.Reason.notApplicable, RemoteTrain.Reason.noMachine,
                     RemoteTrain.Reason.noHerb, RemoteTrain.Reason.noData, RemoteTrain.Reason.invalid,
                     RemoteTrain.Reason.wrongTarget, RemoteTrain.Reason.notReady, RemoteTrain.Reason.everstone]
        for (kind, reasons) in [("buy", buy), ("lineup", lineup), ("train", train)] {
            let entry = try XCTUnwrap(contract.ops[kind])
            XCTAssertEqual(reasons.sorted(), entry.appReasons, kind)
            XCTAssertTrue(Set(entry.appReasons).isSubset(of: Set(entry.botReasons)), kind)
        }
    }

    func testTheTrainActionsAreTheContractActions() throws {
        let source = Self.repoRoot.appendingPathComponent("Sources/PokeTokenBar/Core/RemoteTrain.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: "switch payload.action {"))
        var actions: Set = [RemoteTrain.evolveAction]
        for line in text[start.upperBound...].split(separator: "\n").prefix(12) where line.contains("case \"") {
            let head = line.split(separator: ":", maxSplits: 1)[0]
            for (offset, part) in head.split(separator: "\"").enumerated() where offset % 2 == 1 {
                actions.insert(String(part))
            }
        }
        XCTAssertEqual(actions.sorted(), try XCTUnwrap(contract().ops["train"]).actions)
    }

    func testTheTrainStatsAreTheContractStats() throws {
        XCTAssertEqual(PokemonStatCalculator.order.sorted(), try contract().trainStats)
    }
}
