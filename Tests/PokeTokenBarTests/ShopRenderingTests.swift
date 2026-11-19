import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private final class SizeReadCountingImage: NSImage, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var reads = 0
    var sizeReadCount: Int { lock.withLock { reads } }

    override var size: NSSize {
        get {
            lock.withLock { reads += 1 }
            return super.size
        }
        set { super.size = newValue }
    }
}

private struct OfflineShopProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class ShopRenderingTests: XCTestCase {
    private let size = CGSize(width: PopoverMetrics.contentWidth, height: 520)

    private func makeStore(owning species: ClosedRange<Int> = 1...200) throws -> CompanionStore {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("shop-render-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        state.dex = species.map { id in
            DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)), names: [id: ["en": "Fixture \(id)"]])
        }
        for kind in ItemKind.allCases { state.inventory[kind.rawValue] = 2 }
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: OfflineShopProvider(), fileURL: file,
                              defaults: UserDefaults(suiteName: "shop-render-\(UUID())")!)
    }

    private func host<V: View>(_ view: V, store: CompanionStore) -> NSHostingView<AnyView> {
        OffscreenRender.host(view.environment(store).frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light), size: size, appearance: .aqua)
    }

    /// Every item icon in the shop, pinned to a counting image, so a test sees which cards were laid out.
    private func pinCountingItemIcons() -> [SizeReadCountingImage] {
        let names = Set(ItemKind.allCases.compactMap(\.spriteName) + MegaStone.all.map(\.slug))
        return names.map { name in
            let image = SizeReadCountingImage(size: NSSize(width: 30, height: 30))
            pinSprite(image, at: SpriteLoader.cacheDir.appendingPathComponent("item-\(name).png").path as NSString)
            return image
        }
    }

    func testOpeningTheShopLaysOutOnlyTheCardsOnScreen() throws {
        let store = try makeStore()
        let icons = pinCountingItemIcons()
        let listed = store.shopEntries(in: nil).count + store.shopBattleSections.map(\.kinds.count).reduce(0, +)
            + store.shopAllViewEvolutionItems.count
        for category in [nil, .heldItem, .evolution, .megaStone] as [ItemCategory?] {
            let before = icons.map(\.sizeReadCount)
            let shop = host(ShopView(store: store, nav: PopoverNavigation(), initialCategory: category), store: store)
            shop.layoutSubtreeIfNeeded()
            let laidOut = zip(icons.map(\.sizeReadCount), before).filter { $0 != $1 }.count
            XCTAssertGreaterThan(laidOut, 0, "\(category?.rawValue ?? "all"): the test must lay out item cards")
            XCTAssertLessThan(laidOut, 20, "\(category?.rawValue ?? "all"): \(laidOut) icons laid out of \(listed) listed")
        }
    }

    func testOpeningTheBagLaysOutOnlyTheCardsOnScreen() throws {
        let store = try makeStore()
        let icons = pinCountingItemIcons()
        let shop = host(BagView(store: store, nav: PopoverNavigation()), store: store)
        shop.layoutSubtreeIfNeeded()
        let laidOut = icons.filter { $0.sizeReadCount > 0 }.count
        XCTAssertGreaterThan(laidOut, 0, "the test must lay out item cards")
        XCTAssertLessThan(laidOut, 20, "\(laidOut) icons laid out of \(store.ownedItems.count) owned items")
    }
}
