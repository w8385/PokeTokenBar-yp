import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The add-friend slot on Home must read as a button at rest, in light and dark.
///
///     PTB_FRIEND_ADD_SHOT_DIR=/tmp/shots PTB_FRIEND_ADD_SHOT_PREFIX=after swift test --filter FriendAddButtonTests
@MainActor
final class FriendAddButtonTests: XCTestCase {
    private typealias Row = HomePetRow<EmptyView>

    private struct RGB {
        let r: Double, g: Double, b: Double

        var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }

        func contrast(_ other: RGB) -> Double {
            let (hi, lo) = (max(luminance, other.luminance), min(luminance, other.luminance))
            return (hi + 0.05) / (lo + 0.05)
        }

        func distance(_ other: RGB) -> Double {
            ((r - other.r) * (r - other.r) + (g - other.g) * (g - other.g) + (b - other.b) * (b - other.b)).squareRoot()
        }
    }

    private static let schemes: [(ColorScheme, NSAppearance.Name, String)] = [
        (.light, .aqua, "light"), (.dark, .darkAqua, "dark"),
    ]

    private func entry(_ species: Int, id: String, en: String) -> DexEntry {
        var entry = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(species)),
                             isShiny: false, names: [species: ["en": en]])
        entry.id = id
        return entry
    }

    private func makeStore(friends: [String]) throws -> CompanionStore {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("friend-add-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.pendingHatchID = 4
        state.dex = [entry(25, id: "pikachu", en: "Pikachu"), entry(6, id: "charizard", en: "Charizard"),
                     entry(7, id: "squirtle", en: "Squirtle")]
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: StubProvider(value: EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: []),
                                                                         rarity: .common, names: [4: ["en": "Charmander"]])),
                                   fileURL: file, rng: SeededRNG(seed: 3))
        for id in friends { XCTAssertTrue(store.addFriend(entryID: id)) }
        return store
    }

    private func row(store: CompanionStore, scheme: ColorScheme, main: some View = Color.clear) -> some View {
        HomePetRow(store: store, crowd: PetCrowd()) {
            main.frame(width: Row.mainSize, height: Row.mainSize)
        }
        .frame(width: Row.tileWidth, height: Row.tileHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme)
    }

    private func pixel(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) throws -> RGB {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let color = try XCTUnwrap(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
        return RGB(r: color.redComponent, g: color.greenComponent, b: color.blueComponent)
    }

    /// With no friend yet the add slot stands left of the raised Pokémon, bottom-aligned on the floor.
    private func measure(scheme: ColorScheme, appearance: NSAppearance.Name)
        throws -> (floor: RGB, fill: RGB, plus: RGB) {
        let store = try makeStore(friends: [])
        XCTAssertEqual(Row.arrangement(friendCount: 0, canAdd: !store.friendCandidates.isEmpty), .init(leading: .add))
        let host = OffscreenRender.host(row(store: store, scheme: scheme),
                                        size: CGSize(width: Row.tileWidth, height: Row.tileHeight), appearance: appearance)
        let bitmap = try OffscreenRender.bitmap(of: host)
        let radius = (Row.friendSize - 6) / 2
        let center = CGPoint(x: Row.tileInset + Row.friendSize / 2, y: Row.tileHeight - Row.floorInset - radius)
        let floor = try pixel(bitmap, x: Row.tileWidth / 2, y: Spacing.md)
        var ring: [RGB] = []
        for step in 0..<8 {
            let angle = Double(step) * .pi / 4 + .pi / 8
            ring.append(try pixel(bitmap, x: center.x + radius * 0.65 * cos(angle), y: center.y + radius * 0.65 * sin(angle)))
        }
        let fill = ring.sorted { $0.luminance < $1.luminance }[ring.count / 2]
        var plus = fill
        for dy in stride(from: -3.0, through: 3.0, by: 0.5) {
            for dx in stride(from: -3.0, through: 3.0, by: 0.5) {
                let candidate = try pixel(bitmap, x: center.x + dx, y: center.y + dy)
                if candidate.contrast(fill) > plus.contrast(fill) { plus = candidate }
            }
        }
        return (floor, fill, plus)
    }

    func testTheAddSlotFillStandsOutFromTheTileFloorInLightAndDark() throws {
        for (scheme, appearance, name) in Self.schemes {
            let m = try measure(scheme: scheme, appearance: appearance)
            XCTAssertGreaterThan(m.fill.distance(m.floor), 0.12, "\(name): fill \(m.fill) floor \(m.floor)")
        }
    }

    func testThePlusContrastsWithTheFillAtLeastThreeToOne() throws {
        for (scheme, appearance, name) in Self.schemes {
            let m = try measure(scheme: scheme, appearance: appearance)
            XCTAssertGreaterThanOrEqual(m.plus.contrast(m.fill), 3, "\(name): plus \(m.plus) fill \(m.fill)")
        }
    }

    func testHoverDrawsAStrongerFillThanRest() throws {
        for (scheme, appearance, name) in Self.schemes {
            func fill(hovering: Bool) throws -> RGB {
                let disc = FriendAddDisc(hovering: hovering).frame(width: 26, height: 26)
                    .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme)
                let host = OffscreenRender.host(disc, size: CGSize(width: 26, height: 26), appearance: appearance)
                return try pixel(OffscreenRender.bitmap(of: host), x: 6, y: 13)
            }
            let floor = try pixel(OffscreenRender.bitmap(of: OffscreenRender.host(
                Color(nsColor: .windowBackgroundColor), size: CGSize(width: 4, height: 4), appearance: appearance)), x: 2, y: 2)
            let (rest, hover) = (try fill(hovering: false), try fill(hovering: true))
            XCTAssertGreaterThan(hover.distance(floor), rest.distance(floor) + 0.03, "\(name): rest \(rest) hover \(hover)")
        }
    }

    func testCaptureFriendsRow() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_FRIEND_ADD_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_FRIEND_ADD_SHOT_DIR to write the PR screenshots")
        }
        let prefix = ProcessInfo.processInfo.environment["PTB_FRIEND_ADD_SHOT_PREFIX"] ?? "after"
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sprites = SpriteStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("friend-add-sprites"))
        for (friends, label) in [([String](), "none"), (["pikachu"], "one")] {
            let store = try makeStore(friends: friends)
            for (scheme, appearance, name) in Self.schemes {
                let main = SpriteView(speciesID: 4, size: Row.mainSize, animated: false, spriteStore: sprites)
                let view = HomePetRow(store: store, crowd: PetCrowd(), spriteStore: sprites) {
                    main.frame(width: Row.mainSize, height: Row.mainSize)
                }
                .padding(Spacing.lg)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
                try await OffscreenRender.capture(view, size: CGSize(width: Row.tileWidth + 2 * Spacing.lg,
                                                                     height: Row.tileHeight + 2 * Spacing.lg),
                                                  appearance: appearance, scale: 3,
                                                  to: directory.appendingPathComponent("friend-add-\(prefix)-\(label)-\(name).png"))
            }
        }
    }
}
