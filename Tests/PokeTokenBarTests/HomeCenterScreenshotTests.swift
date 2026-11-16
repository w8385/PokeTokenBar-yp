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
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
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

    private static func floatingLayout(friends: Int, crowd: PetCrowd) -> PetRowLayout {
        crowd.friendsOnLeft = true
        crowd.friendsFlank = friends == 2
        return PetRowLayout(friendCount: friends, friendsOnLeft: true, friendsFlank: friends == 2)
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
