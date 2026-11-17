import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct FriendRowShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: []), rarity: .common, names: [4: ["en": "Charmander"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures of the floating pet's friend row, one image per layout.
///
///     PTB_FRIEND_ROW_SHOT_DIR=/tmp/shots swift test --filter FloatingFriendsLayoutShotTests
@MainActor
final class FloatingFriendsLayoutShotTests: XCTestCase {
    private struct Row {
        let name: String
        let count: Int
        let left: Bool
        let flank: Bool
        var order: [Int] { flank ? [1, 0, 2] : (left ? Array((0...count).reversed()) : Array(0...count)) }
    }

    private enum Mode { case calm, bubble, friendHearts
        var suffix: String { self == .calm ? "" : (self == .bubble ? "-bubble" : "-friend-hearts") }
    }
    private static let modes: [Mode] = [.calm, .bubble, .friendHearts]

    private static let rows = [
        Row(name: "one-left", count: 1, left: true, flank: false),
        Row(name: "one-right", count: 1, left: false, flank: false),
        Row(name: "two-left", count: 2, left: true, flank: false),
        Row(name: "two-right", count: 2, left: false, flank: false),
        Row(name: "two-flank", count: 2, left: true, flank: true),
    ]

    /// Friend pairs picked for their silhouettes: tall, wide, tiny, long.
    private static let pairs: [(name: String, ids: [Int])] = [
        ("mixed", [25, 6]), ("wide", [143, 94]), ("small", [13, 16]), ("long", [130, 149]),
    ]

    private func entry(_ species: Int) -> DexEntry {
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(species)),
                             isShiny: false, names: [species: ["en": "Mon \(species)"]])
        entry.id = "mon-\(species)"
        return entry
    }

    func testCaptureFriendRows() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_FRIEND_ROW_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_FRIEND_ROW_SHOT_DIR to write the friend row captures")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("friend-row-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let suite = "friend-row-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4], plannedPathIDs: [4], stageIndex: 0,
                                usedAtStage: 0, rarity: .common, totalForms: 1, profile: raised)
        state.dex = Self.pairs.flatMap(\.ids).map(entry)
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: FriendRowShotProvider(), fileURL: file, rng: SeededRNG(seed: 3), defaults: defaults)
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))
        let size = CGFloat(usage.floatingPetSize)

        for pair in Self.pairs {
            for row in Self.rows {
                for mode in Self.modes where mode == .calm || pair.name == "mixed" {
                    let bubble = mode == .bubble || mode == .friendHearts
                    store.friendSubjects.forEach { store.removeFriend(entryID: $0.entryID) }
                    for id in pair.ids.prefix(row.count) { XCTAssertTrue(store.addFriend(entryID: "mon-\(id)")) }
                    let crowd = PetCrowd(settle: .seconds(120))
                    crowd.configure(order: row.order, motionAllowed: true, active: false)
                    crowd.friendsOnLeft = row.left
                    crowd.friendsFlank = row.flank
                    let hearts = PetHeartState()
                    hearts.isShowing = mode == .bubble
                    if mode == .friendHearts { hearts.friendIndex = row.count - 1 }
                    let layout = PetRowLayout(friendCount: row.count, friendsOnLeft: row.left, friendsFlank: row.flank)
                    let panel = FloatingPetController.panelSize(petSize: size, showingBubble: bubble, layout: layout)
                    let view = FloatingPetView(animated: false, spriteStore: sprites, hearts: hearts, crowd: crowd)
                        .environment(usage).environment(store)
                        .frame(width: panel.width, height: panel.height)
                        .background(Color.white)
                        .environment(\.colorScheme, .light)
                    try await OffscreenRender.capture(
                        view, size: panel, appearance: .aqua, scale: 3, settle: .seconds(5),
                        to: directory.appendingPathComponent("\(pair.name)-\(row.name)\(mode.suffix).png"))
                }
            }
        }
    }
}
