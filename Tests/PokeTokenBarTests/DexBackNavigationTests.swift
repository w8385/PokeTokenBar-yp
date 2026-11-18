import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct OfflineProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { throw URLError(.notConnectedToInternet) }
}

@MainActor @Observable
private final class RegionProbe {
    var region: PokedexRegion?
}

/// The real Pokédex grid with its region binding owned here, so the test reads the model instead of
/// inferring it from pixels. Animations are off: the offscreen CI window gets no display-link ticks,
/// so a fade could stay half-done for seconds with the previous grid still on screen.
@MainActor
private struct RegionHarness: View {
    let store: CompanionStore
    let probe: RegionProbe

    var body: some View {
        @Bindable var probe = probe
        return DexGridView(store: store, searchText: "", shinyOnly: false, includeUnowned: false,
                    sortOption: .numberAsc, selectedRarity: .constant(nil), selectedRegion: $probe.region,
                    returnAnchor: nil, onSelectSpecies: { _ in }, onResetFilters: {})
            .transaction { $0.disablesAnimations = true }
    }
}

/// The detail page replaces the grid, so Back rebuilds it. These drive the real `CollectionView` and
/// `BoxView` through that round trip. Which screen is up is read from sprite pixels: every species
/// under test gets its own solid-colored sprite, so a color is on screen exactly when its cell is.
/// Controls are found as native views by their localized title or tooltip, never by reading text.
@MainActor
final class DexBackNavigationTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    // MARK: Fixtures

    private enum Swatch: CaseIterable {
        case red, green, blue

        var color: NSColor {
            switch self {
            case .red: return .red
            case .green: return .green
            case .blue: return .blue
            }
        }

        func matches(_ color: NSColor) -> Bool {
            switch self {
            case .red: return color.redComponent > 0.8 && color.greenComponent < 0.4 && color.blueComponent < 0.3
            case .green: return color.greenComponent > 0.8 && color.redComponent < 0.3 && color.blueComponent < 0.3
            case .blue: return color.blueComponent > 0.8 && color.redComponent < 0.3 && color.greenComponent < 0.4
            }
        }
    }

    /// Solid 96pt sprites in the sprite cache for these species, restored when the test ends.
    private func paint(_ sprites: [Int: Swatch]) {
        for (id, swatch) in sprites {
            let key = SpriteLoader.cacheDir.appendingPathComponent(
                SpriteStore.cacheKey(speciesID: id, animated: false, shiny: false) + ".png").path as NSString
            let image = NSImage(size: NSSize(width: 96, height: 96))
            image.lockFocus()
            swatch.color.setFill()
            NSRect(x: 0, y: 0, width: 96, height: 96).fill()
            image.unlockFocus()
            pinSprite(image, at: key)
        }
    }

    /// 20 species = 2 grid pages: species 1…16, then 17…20.
    private func makeStore(count: Int = 20) throws -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-back-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.dex = (1...count).map { id in
            DexEntry(id: "entry-\(id)", baseID: id, finalID: id, chainOrder: [id], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
                     names: [id: ["en": "Mon\(id)"]])
        }
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: OfflineProvider(), fileURL: file)
    }

    private func host<V: View>(_ content: V) -> NSView {
        let host = OffscreenRender.host(content
            .frame(width: PopoverMetrics.contentWidth, height: 520)
            .background(Color.white)
            .environment(\.colorScheme, .light), size: CGSize(width: PopoverMetrics.contentWidth, height: 520))
        window = OffscreenRender.windowHosting(host, appearance: .aqua)
        return host
    }

    // MARK: Rendered pixels

    /// How many square points of `swatch` the screen draws now, so the thresholds hold at any bitmap scale.
    private func pixels(_ swatch: Swatch, in host: NSView) throws -> Int {
        let bitmap = try OffscreenRender.bitmap(of: host)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let normalized = try XCTUnwrap(NSBitmapImageRep(data: png))
        var count = 0
        for y in 0..<normalized.pixelsHigh {
            for x in 0..<normalized.pixelsWide {
                if let color = normalized.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), swatch.matches(color) {
                    count += 1
                }
            }
        }
        return Int((CGFloat(count) / (scale * scale)).rounded())
    }

    /// A cell is a 96pt sprite scaled into the grid, so its color covers far more than stray pixels.
    private let visible = 200

    /// SwiftUI renders a state change a run-loop turn or two later.
    private func waitFor(_ description: String, in host: NSView,
                         file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () throws -> Bool) async throws {
        try await OffscreenRender.waitUntil(description, in: host, file: file, line: line, condition)
    }

    private func showing(_ swatches: [Swatch], hiding: [Swatch] = [], in host: NSView) throws -> Bool {
        try swatches.allSatisfy { try pixels($0, in: host) > visible }
            && hiding.allSatisfy { try pixels($0, in: host) < visible / 4 }
    }

    // MARK: Native controls

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    /// Back sits in the detail page's top-left corner. SwiftUI exposes no native view for it, so it is
    /// clicked by position, retried while the detail page is still mounting.
    private func pressBack(until done: () throws -> Bool, in host: NSView,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let window = try XCTUnwrap(host.window)
        try await OffscreenRender.waitUntil("clicking the top-left Back to leave the detail page", in: host,
                                            file: file, line: line) {
            if try done() { return true }
            try OffscreenRender.click(at: NSPoint(x: 28, y: host.bounds.height - 12), in: window)
            return false
        }
    }

    // MARK: Pokédex grid

    func testRegionChipFiltersMountedCollectionAndTogglesBack() async throws {
        paint([1: .red, 152: .blue])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-region-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.dex = [
            DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                     caughtAt: Date(), names: [1: ["en": "Maple"]]),
            DexEntry(baseID: 152, finalID: 152, chainOrder: [152], rarity: .common,
                     caughtAt: Date(), names: [152: ["en": "Willow"]]),
        ]
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: OfflineProvider(), fileURL: file)
        let probe = RegionProbe()
        let root = host(RegionHarness(store: store, probe: probe))
        // Kanto's Maple is red and Johto's Willow is blue: the grid shows a color exactly when it shows the cell.
        try await waitFor("both cells", in: root) { try showing([.red, .blue], in: root) }

        // The chip's own tap is not driven: native views are not exposed for it, so the binding it
        // writes is set here and the grid's reaction to the region is what is read from pixels.
        probe.region = .johto
        try await waitFor("Johto only", in: root) {
            try showing([.blue], hiding: [.red], in: root)
        }

        probe.region = nil
        try await waitFor("both cells again", in: root) { try showing([.red, .blue], in: root) }
    }

    func testBackFromDetailReturnsToThePageOfThatSpecies() async throws {
        // #5 is on page 1, #18 and #20 on page 2.
        paint([5: .red, 18: .green, 20: .blue])
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.tab = .dex
        let root = host(CollectionView(store: store, navigation: navigation))
        try await waitFor("page 1", in: root) { try showing([.red], hiding: [.blue], in: root) }

        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 18 })
        navigation.dexDetailCollectionID = species.collectionID
        try await pressBack(until: { navigation.dexDetailCollectionID == nil }, in: root)

        // Back lands on the page that holds #18, not on page 1.
        try await waitFor("page 2", in: root) { try showing([.green, .blue], hiding: [.red], in: root) }
    }

    // MARK: Box

    /// Oldest is the first catch, so it is the Box's last cell — off screen until scrolled to.
    func testBackFromTheBoxPageReturnsTheGridToWhereItWas() async throws {
        paint([1: .blue])
        let store = try makeStore(count: 40)
        let navigation = PopoverNavigation()
        navigation.tab = .box
        let root = host(BoxView(store: store, navigation: navigation))
        try await waitFor("the first screenful", in: root) { try pixels(.blue, in: root) == 0 }
        let grid = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }
            .max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) })
        // LazyVGrid grows the document as cells are realized, so keep scrolling to the end.
        try await waitFor("scrolling to reach the oldest cell", in: root) {
            if try pixels(.blue, in: root) > visible { return true }
            let clip = grid.contentView
            let bottom = (grid.documentView?.frame.height ?? 0) - clip.bounds.height
            clip.scroll(to: NSPoint(x: 0, y: clip.isFlipped ? bottom : 0))
            grid.reflectScrolledClipView(clip)
            return false
        }

        navigation.boxDetailID = "entry-1"
        try await pressBack(until: { navigation.boxDetailID == nil }, in: root)

        // Back scrolls the new grid to the cell that was open: the oldest one is on screen without scrolling.
        try await waitFor("the grid back at the oldest cell", in: root) { try pixels(.blue, in: root) > visible }
        XCTAssertNil(navigation.boxDetailID)
    }
}
