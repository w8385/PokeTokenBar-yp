import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct BubbleShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: []), rarity: .common, names: [4: ["en": "Charmander"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Opt-in offscreen captures of every bubble in one family, light and dark.
///
///     PTB_BUBBLE_SHOT_DIR=/tmp/shots PTB_BUBBLE_SHOT_PREFIX=after swift test --filter BubbleScreenshotTests
@MainActor
final class BubbleScreenshotTests: XCTestCase {
    private func entry(_ species: Int, id: String, en: String) -> DexEntry {
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(species)),
                             isShiny: false, names: [species: ["en": en]])
        entry.id = id
        return entry
    }

    func testCaptureBubbleFamily() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BUBBLE_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_BUBBLE_SHOT_DIR to write the PR screenshots")
        }
        let prefix = ProcessInfo.processInfo.environment["PTB_BUBBLE_SHOT_PREFIX"] ?? "after"
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("bubble-family-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let suite = "bubble-family-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        var raised = PokemonProfile.generate(seed: 5, instanceID: "raised")
        raised.level = 24
        state.active = MonState(baseID: 4, pathIDs: [4], plannedPathIDs: [4], stageIndex: 0,
                                usedAtStage: 0, rarity: .common, totalForms: 1, profile: raised)
        state.dex = [entry(25, id: "pikachu", en: "Pikachu"), entry(6, id: "charizard", en: "Charizard")]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: BubbleShotProvider(), fileURL: file, rng: SeededRNG(seed: 3), defaults: defaults)
        let usage = UsageStore(providers: [], statusProvider: NoProviderStatus(), autoRefresh: false, defaults: defaults)
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))
        XCTAssertTrue(store.addFriend(entryID: "pikachu"))
        XCTAssertTrue(store.addFriend(entryID: "charizard"))

        let schemes: [(ColorScheme, NSAppearance.Name, String, NSColor)] = [
            (.light, .aqua, "light", NSColor(calibratedWhite: 0.78, alpha: 1)),
            (.dark, .darkAqua, "dark", NSColor(calibratedWhite: 0.16, alpha: 1)),
        ]
        for (scheme, appearance, name, desktop) in schemes {
            // The family side by side: pet speech (warning, critical), then every emote.
            let sizes: [CGFloat] = [28, 76, 96, 96]
            let emotes: [PetCrowd.Bubble] = [.heart, .note, .cheer, .prayer]
            let sheet = HStack(alignment: .bottom, spacing: 18) {
                SpeechBubbleView(content: .init(title: "Warning", body: "Claude 5h limit is at 80%", isCritical: false))
                SpeechBubbleView(content: .init(title: "Critical", body: "Codex weekly limit is at 95%", isCritical: true))
                ForEach(Array(sizes.enumerated()), id: \.offset) { index, size in
                    SpriteView(speciesID: 25, size: size, animated: false, spriteStore: sprites)
                        .frame(width: size, height: size)
                        .overlay(alignment: .top) { CrowdBubble(bubble: emotes[index], size: size) }
                }
            }
            .padding(EdgeInsets(top: 40, leading: 16, bottom: 16, trailing: 16))
            try await capture(sheet, width: 780, height: 190, appearance: appearance, scheme: scheme, background: desktop,
                              to: directory.appendingPathComponent("bubble-\(prefix)-family-\(name).png"))

            // Home: the raised Pokémon's tile and the friend slots under it, with reactions up.
            let homeCrowd = PetCrowd(settle: .seconds(120))
            homeCrowd.configure(order: [1, 0, 2], motionAllowed: true, active: false)
            homeCrowd.clicked(slot: 1)
            homeCrowd.cheer()
            homeCrowd.play(.note, between: 1, and: 0, bubbleOn: 0)
            let home = HomePetRow(store: store, crowd: homeCrowd, spriteStore: sprites) {
                SpriteView(speciesID: 4, size: HomePetRow<EmptyView>.mainSize, animated: false, spriteStore: sprites)
                    .crowdMember(homeCrowd, slot: 0, size: HomePetRow<EmptyView>.mainSize)
                    .frame(width: HomePetRow<EmptyView>.mainSize, height: HomePetRow<EmptyView>.mainSize)
            }
            .padding(EdgeInsets(top: 30, leading: 14, bottom: 14, trailing: 14))
            try await capture(home.environment(store).environment(usage), width: 160,
                              height: 130, appearance: appearance, scheme: scheme,
                              background: .windowBackgroundColor,
                              to: directory.appendingPathComponent("bubble-\(prefix)-home-\(name).png"))

            // Floating pet with two friends and reactions on all three.
            let crowd = PetCrowd(settle: .seconds(120))
            crowd.friendsOnLeft = true
            crowd.friendsFlank = true
            let layout = PetRowLayout(friendCount: 2, friendsOnLeft: true, friendsFlank: true)
            crowd.configure(order: layout.slotOrder, motionAllowed: true, active: false)
            crowd.clicked(slot: 1)
            crowd.cheer()
            crowd.play(.note, between: 1, and: 0, bubbleOn: 0)
            let panel = FloatingPetController.panelSize(petSize: CGFloat(usage.floatingPetSize), showingBubble: false,
                                                        layout: layout)
            try await capture(FloatingPetView(animated: false, spriteStore: sprites, crowd: crowd)
                .environment(usage).environment(store), width: panel.width, height: panel.height,
                              appearance: appearance, scheme: scheme, background: desktop,
                              to: directory.appendingPathComponent("bubble-\(prefix)-floating-\(name).png"))
        }
    }

    private func capture<V: View>(_ view: V, width: CGFloat, height: CGFloat, appearance: NSAppearance.Name,
                                  scheme: ColorScheme, background: NSColor, to file: URL) async throws {
        let size = NSSize(width: width, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: background))
            .environment(\.colorScheme, scheme),
            size: size, appearance: appearance, scale: 2, to: file)
    }
}
