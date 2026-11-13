import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct ShotProvider: PokeProviding {
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
///     PTB_FRIENDS_SCREENSHOT_DIR=/tmp/shots swift test --filter FriendsScreenshotTests
@MainActor
final class FriendsScreenshotTests: XCTestCase {
    private func entry(_ species: Int, id: String, en: String, shiny: Bool = false) -> DexEntry {
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(species)),
                             isShiny: shiny, names: [species: ["en": en]])
        entry.id = id
        return entry
    }

    func testCaptureFriends() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_FRIENDS_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_FRIENDS_SCREENSHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("friends-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let suite = "friends-shot-\(UUID())"
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
            entry(149, id: "dragonite", en: "Dragonite"), entry(130, id: "gyarados", en: "Gyarados"),
        ]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: ShotProvider(), fileURL: file, rng: SeededRNG(seed: 3), defaults: defaults)
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let sprites = SpriteStore(directory: scratch.appendingPathComponent("sprites"))

        try await capture(CompanionHeader(store: store, spriteStore: sprites).padding(12)
            .environment(store).environment(usage), width: PopoverMetrics.contentWidth, height: 150,
                          to: directory.appendingPathComponent("home-single.png"))

        try await capture(FriendPicker(store: store, spriteStore: sprites) {}
            .environment(store), width: 300, height: 150,
                          to: directory.appendingPathComponent("friend-picker.png"))

        XCTAssertTrue(store.addFriend(entryID: "pikachu"))
        XCTAssertTrue(store.addFriend(entryID: "charizard"))
        try await capture(CompanionHeader(store: store, spriteStore: sprites).padding(12)
            .environment(store).environment(usage), width: PopoverMetrics.contentWidth, height: 150,
                          to: directory.appendingPathComponent("home-with-friends.png"))

        let crowd = PetCrowd(settle: .seconds(120))
        crowd.configure(order: [1, 0, 2], motionAllowed: true, active: false)
        let layout = PetRowLayout(friendCount: 2, friendsOnLeft: true)
        crowd.friendsOnLeft = true
        let size = CGFloat(usage.floatingPetSize)
        let panel = FloatingPetController.panelSize(petSize: size, showingBubble: false, layout: layout)
        func floating() -> some View {
            FloatingPetView(animated: false, spriteStore: sprites, crowd: crowd)
                .environment(usage).environment(store)
        }
        try await capture(floating(), width: panel.width, height: panel.height,
                          to: directory.appendingPathComponent("floating-pet-friends.png"))
        crowd.play(.heart, between: 1, and: 0, bubbleOn: 1)
        try await capture(floating(), width: panel.width, height: panel.height,
                          to: directory.appendingPathComponent("floating-pet-interaction.png"))
    }

    private func capture<V: View>(_ view: V, width: CGFloat, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: width, height: height)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .seconds(5))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: file)
    }
}
