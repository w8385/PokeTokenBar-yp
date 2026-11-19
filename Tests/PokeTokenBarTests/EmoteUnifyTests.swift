import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct NoStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}

/// One emote per Pokémon: a new one replaces the old, a lower one never draws over a higher one, speech wins on the pet.
@MainActor
final class EmoteUnifyTests: XCTestCase {
    private func crowd(order: [Int] = [0, 1, 2], motion: Bool = true) -> PetCrowd {
        let crowd = PetCrowd(settle: .seconds(120))
        crowd.configure(order: order, motionAllowed: motion, active: false)
        return crowd
    }

    private func emotes(_ crowd: PetCrowd) -> [PetCrowd.Bubble?] { (0..<3).map(crowd.bubble) }

    func testATouchReplacesAnIdleHeartOnTheSamePokemon() {
        let crowd = crowd()
        crowd.play(.heart, between: 0, and: 1, bubbleOn: 0)
        XCTAssertEqual(emotes(crowd), [.heart, nil, nil])
        XCTAssertTrue(crowd.touched(slot: 0))
        XCTAssertEqual(emotes(crowd), [.heart, nil, nil])
        crowd.play(.note, between: 0, and: 1, bubbleOn: 0)
        XCTAssertEqual(emotes(crowd), [.heart, nil, nil], "an idle note never replaces a touch heart")
    }

    func testAStrokeOnAClickedFriendKeepsOneEmote() {
        let crowd = crowd()
        crowd.clicked(slot: 1)
        XCTAssertEqual(emotes(crowd), [nil, .heart, nil])
        XCTAssertTrue(crowd.touched(slot: 1))
        XCTAssertEqual(emotes(crowd), [nil, .heart, nil])
    }

    func testALowerEmoteNeverDrawsOverAHigherOne() {
        let crowd = crowd()
        crowd.touched(slot: 1)
        crowd.cheer()
        XCTAssertEqual(emotes(crowd), [nil, .heart, .cheer], "the cheer skips the touched friend")
        crowd.play(.note, between: 1, and: 2, bubbleOn: 2)
        XCTAssertEqual(crowd.bubble(2), .cheer, "idle under cheer")
        crowd.touched(slot: 2, with: .heart)
        XCTAssertEqual(crowd.bubble(2), .heart, "a touch replaces a cheer")
    }

    func testSpeechClearsAndBlocksEveryEmoteOnThePet() {
        let crowd = crowd()
        crowd.touched(slot: 0)
        crowd.speechOnMain = true
        XCTAssertNil(crowd.bubble(0))
        XCTAssertFalse(crowd.touched(slot: 0))
        XCTAssertFalse(crowd.touched(slot: 0, with: .prayer))
        crowd.play(.heart, between: 0, and: 1, bubbleOn: 0)
        XCTAssertNil(crowd.bubble(0))
        XCTAssertTrue(crowd.touched(slot: 1), "speech sits over the pet only")
        crowd.speechOnMain = false
        XCTAssertTrue(crowd.touched(slot: 0))
    }

    func testAClickWithMotionOffStillShowsOneEmote() {
        let crowd = crowd(motion: false)
        crowd.clicked(slot: 2)
        XCTAssertEqual(emotes(crowd), [nil, nil, .heart])
        crowd.configure(order: [0, 1, 2], motionAllowed: false, active: true)
        XCTAssertEqual(emotes(crowd), [nil, nil, .heart], "re-showing the panel keeps the emote")
    }

    // MARK: the floating pet's controller

    private struct Fixture {
        let controller: FloatingPetController
        let store: UsageStore
        let companion: CompanionStore
        let cleanUp: () -> Void
    }

    private func makeFixture(hatched: Bool = true) throws -> Fixture {
        let suite = "EmoteUnifyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        let store = UsageStore(providers: [], statusProvider: NoStatus(), autoRefresh: false, defaults: defaults)
        if hatched {
            var state = CompanionState()
            state.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
            var friend = DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: false,
                                  names: [25: ["en": "Pikachu"]])
            friend.id = "friend-25"
            state.dex = [friend]
            try JSONEncoder().encode(state).write(to: file)
        }
        store.floatingPetEnabled = true
        let companion = CompanionStore(fileURL: file, defaults: defaults)
        if hatched { XCTAssertTrue(companion.addFriend(entryID: "friend-25")) }
        let controller = FloatingPetController(store: store, companion: companion, defaults: defaults,
                                               motionOverride: true, crowd: PetCrowd(settle: .seconds(120)))
        controller.setDisplayAwake(false)
        // The row the shown panel would configure, without showing a panel.
        controller.crowd.configure(order: hatched ? [1, 0] : [0], motionAllowed: true, active: false)
        return Fixture(controller: controller, store: store, companion: companion, cleanUp: {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: file)
        })
    }

    func testClickingThePetOverAnIdleHeartLeavesOneEmoteOnIt() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let crowd = fixture.controller.crowd
        crowd.play(.heart, between: 0, and: 1, bubbleOn: 0)
        fixture.controller.petClicked()
        XCTAssertEqual(emotes(crowd), [.heart, nil, nil])
    }

    func testClickingAFriendThenStrokingItLeavesOneEmote() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let hosting = fixture.controller.makeHostingView(animated: false)
        fixture.controller.friendClicked(0)
        XCTAssertEqual(emotes(fixture.controller.crowd), [nil, .heart, nil])
        hosting.onStroke?(.friend(0))
        XCTAssertEqual(emotes(fixture.controller.crowd), [nil, .heart, nil])
    }

    func testAnEggClickShowsOnePrayer() throws {
        let fixture = try makeFixture(hatched: false)
        defer { fixture.cleanUp() }
        fixture.controller.petClicked()
        fixture.controller.petClicked()
        XCTAssertEqual(emotes(fixture.controller.crowd), [.prayer, nil, nil])
    }

    func testAgentSpeechKeepsHeartsOffThePet() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let crowd = fixture.controller.crowd
        crowd.touched(slot: 0)
        let url = try XCTUnwrap(URL(string: "poketokenbar://agent?state=waiting&label=web"))
        fixture.controller.handleAgentEvent(try XCTUnwrap(AgentActivityEvent(url: url)))
        crowd.configure(order: [1, 0], motionAllowed: true, active: false)
        XCTAssertNil(crowd.bubble(0))
        fixture.controller.makeHostingView(animated: false).onStroke?(.main)
        XCTAssertNil(crowd.bubble(0), "a stroke under speech shows nothing")
        crowd.play(.heart, between: 0, and: 1, bubbleOn: 0)
        XCTAssertNil(crowd.bubble(0), "an idle heart under speech shows nothing")
    }

    // MARK: pixels

    private static let green = NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)

    private func greenPNG() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 4..<28 { for y in 8..<32 { rep.setColor(Self.green, atX: x, y: y) } }
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func isHeartRed(_ c: NSColor) -> Bool {
        c.redComponent > 0.6 && c.greenComponent < 0.4 && c.blueComponent < 0.45 && c.alphaComponent > 0.5
    }

    private func isSpriteGreen(_ c: NSColor) -> Bool {
        c.greenComponent > 0.9 && c.redComponent < 0.2 && c.blueComponent < 0.2
    }

    /// Friend on the left, the pet on the right: both sprites have loaded once both columns hold green.
    private func columnHasSprite(_ rep: NSBitmapImageRep, x: Int) -> Bool {
        (0..<rep.pixelsHigh).contains { y in
            rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB).map(isSpriteGreen) ?? false
        }
    }

    /// 4-connected blobs of `match` pixels at least `minPixels` big.
    private func blobs(in rep: NSBitmapImageRep, minPixels: Int = 6, _ match: (NSColor) -> Bool) -> Int {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var hit = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w {
            if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), match(c) { hit[y * w + x] = true }
        } }
        var seen = [Bool](repeating: false, count: w * h)
        var count = 0
        for start in 0..<(w * h) where hit[start] && !seen[start] {
            var stack = [start], size = 0
            seen[start] = true
            while let i = stack.popLast() {
                size += 1
                let x = i % w, y = i / w
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < w && ny < h && hit[ny * w + nx] && !seen[ny * w + nx] {
                    seen[ny * w + nx] = true
                    stack.append(ny * w + nx)
                }
            }
            if size >= minPixels { count += 1 }
        }
        return count
    }

    private func renderRow(_ fixture: Fixture, sprites: URL) async throws -> NSBitmapImageRep {
        let crowd = fixture.controller.crowd
        let size = CGFloat(fixture.store.floatingPetSize)
        let layout = PetRowLayout(friendCount: 1, friendsOnLeft: crowd.friendsOnLeft, friendsFlank: false)
        let panel = FloatingPetController.panelSize(petSize: size, showingBubble: false, layout: layout)
        let view = FloatingPetView(animated: false, spriteStore: SpriteStore(directory: sprites), crowd: crowd)
            .environment(fixture.store).environment(fixture.companion)
            .frame(width: panel.width, height: panel.height)
            .background(Color.white)
        let host = OffscreenRender.host(view, size: panel, appearance: .aqua)
        var rep = try OffscreenRender.bitmap(of: host)
        try await OffscreenRender.settle(host) {
            rep = try OffscreenRender.bitmap(of: host)
            return [0.15, 0.85].allSatisfy { self.columnHasSprite(rep, x: Int(Double(rep.pixelsWide) * $0)) }
        }
        return rep
    }

    private func spriteDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("emote-sprites-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for key in ["1-s", "1-f-s", "25-s", "25-f-s"] {
            try greenPNG().write(to: dir.appendingPathComponent("\(key).png"))
        }
        return dir
    }

    func testAFriendClickDrawsOneHeartInTheRow() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let sprites = try spriteDirectory()
        defer { try? FileManager.default.removeItem(at: sprites) }
        fixture.controller.crowd.play(.note, between: 0, and: 1, bubbleOn: 1)
        fixture.controller.friendClicked(0)
        let rep = try await renderRow(fixture, sprites: sprites)
        XCTAssertEqual(blobs(in: rep, isHeartRed), 1)
    }

    func testAPetClickOverAnIdleHeartDrawsOneHeartInTheRow() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let sprites = try spriteDirectory()
        defer { try? FileManager.default.removeItem(at: sprites) }
        fixture.controller.crowd.play(.heart, between: 0, and: 1, bubbleOn: 0)
        fixture.controller.petClicked()
        let rep = try await renderRow(fixture, sprites: sprites)
        XCTAssertEqual(blobs(in: rep, isHeartRed), 1)
    }
}
