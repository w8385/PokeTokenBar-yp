import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct CenterShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [
            EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])]),
                rarity: .common,
                names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"], 6: ["en": "Charizard"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in captures for the PR: a synthetic save, the real views.
///
///     PTB_CENTER_SCREENSHOT_DIR=/tmp/shots swift test --filter HomeCenterScreenshotTests
@MainActor
final class HomeCenterScreenshotTests: XCTestCase {
    private func entry(_ species: Int, id: String, en: String, shiny: Bool = false) -> DexEntry {
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(species)),
                             isShiny: shiny, names: [species: ["en": en]])
        entry.id = id
        return entry
    }

    func testCaptureCenteredTrio() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_CENTER_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_CENTER_SCREENSHOT_DIR to write the PR screenshots")
        }
        let prefix = ProcessInfo.processInfo.environment["PTB_CENTER_SCREENSHOT_PREFIX"] ?? "home-center-after"
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("center-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let suite = "center-shot-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4, 5, 6], plannedPathIDs: [4, 5, 6], stageIndex: 1,
                                usedAtStage: 0, rarity: .common, totalForms: 3, profile: raised)
        state.dex = [
            entry(25, id: "pikachu", en: "Pikachu", shiny: true), entry(6, id: "charizard", en: "Charizard"),
            entry(94, id: "gengar", en: "Gengar"), entry(143, id: "snorlax", en: "Snorlax"),
        ]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: CenterShotProvider(), fileURL: file, rng: SeededRNG(seed: 3), defaults: defaults)
        let usage = UsageStore(providers: [], statusProvider: NoProviderStatus(), autoRefresh: false, defaults: defaults)
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))

        for friends in 1...2 {
            XCTAssertTrue(store.addFriend(entryID: friends == 1 ? "pikachu" : "charizard"))
            try await capture(CompanionHeader(store: store, spriteStore: sprites).padding(12)
                .environment(store).environment(usage), width: PopoverMetrics.contentWidth, height: 150,
                              to: directory.appendingPathComponent("\(prefix)-home-\(friends)friend.png"))

            let crowd = PetCrowd(settle: .seconds(120))
            let layout = Self.floatingLayout(friends: friends, crowd: crowd)
            crowd.configure(order: layout.slotOrder, motionAllowed: true, active: false)
            let size = CGFloat(usage.floatingPetSize)
            let panel = FloatingPetController.panelSize(petSize: size, showingBubble: false, layout: layout)
            try await capture(FloatingPetView(animated: false, spriteStore: sprites, crowd: crowd)
                .environment(usage).environment(store), width: panel.width, height: panel.height,
                              to: directory.appendingPathComponent("\(prefix)-floating-\(friends)friend.png"))
        }
    }

    /// Reaction bubbles at Home's slot and tile sizes and the floating pet's smallest, default and a large size.
    func testCaptureBubbles() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_CENTER_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_CENTER_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("bubble-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let sprites = SpriteStore(directory: scratch)
        let sizes: [CGFloat] = [28, 76, 48, 96, 192]
        func oldBubble(_ bubble: PetCrowd.Bubble, size: CGFloat) -> some View {
            Text(bubble.rawValue)
                .font(.system(size: max(10, size * 0.26)))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5))
        }
        func row(old: Bool) -> some View {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(sizes.enumerated()), id: \.offset) { index, size in
                    let bubble: PetCrowd.Bubble = [.heart, .note, .cheer][index % 3]
                    SpriteView(speciesID: 25, size: size, animated: false, spriteStore: sprites)
                        .frame(width: size, height: size)
                        .overlay(alignment: .top) {
                            if old { oldBubble(bubble, size: size) } else { CrowdBubble(bubble: bubble, size: size) }
                        }
                }
            }
            .padding(12)
        }
        let width = sizes.reduce(0, +) + CGFloat(sizes.count - 1) * 12 + 24
        for (name, old) in [("before", true), ("after", false)] {
            try await capture(row(old: old), width: width, height: 216,
                              to: directory.appendingPathComponent("home-center-\(name)-bubbles.png"))
        }
    }

    private static func floatingLayout(friends: Int, crowd: PetCrowd) -> PetRowLayout {
        crowd.friendsOnLeft = true
        crowd.friendsFlank = friends == 2
        return PetRowLayout(friendCount: friends, friendsOnLeft: true, friendsFlank: friends == 2)
    }

    private func capture<V: View>(_ view: V, width: CGFloat, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: width, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light),
            size: size, appearance: .aqua, scale: 2, to: file)
    }
}
