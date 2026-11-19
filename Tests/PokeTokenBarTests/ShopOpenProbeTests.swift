import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private final class ReadCountingImage: NSImage, @unchecked Sendable {
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

/// Print-only probe: PTB_SHOP_PROBE=1 swift test --filter ShopOpenProbeTests
@MainActor
final class ShopOpenProbeTests: XCTestCase {
    func testProbeShopOpenCost() throws {
        guard ProcessInfo.processInfo.environment["PTB_SHOP_PROBE"] != nil else { throw XCTSkip("probe") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shop-probe-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        let species = Int(ProcessInfo.processInfo.environment["PTB_SHOP_PROBE_SPECIES"] ?? "") ?? 1000
        state.dex = (1...species).map { i in
            DexEntry(baseID: i, finalID: i, chainOrder: [i], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)), names: [i: ["ko": "F\(i)"]])
        }
        for kind in ItemKind.allCases { state.inventory[kind.rawValue] = 2 }
        for (i, move) in MachineCatalog.moves.enumerated() where i % 2 == 0 {
            state.inventory[MachineMove.inventoryKey(move.id)] = 1
        }
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(fileURL: file)

        func time(_ label: String, reps: Int = 20, _ work: () -> Void) {
            let start = Date()
            for _ in 0..<reps { work() }
            print(String(format: "[probe] %@: %.2f ms", label, Date().timeIntervalSince(start) * 1000 / Double(reps)))
        }
        time("shopScreen(all)") { _ = store.shopScreen(category: nil, query: "", heldGroup: nil) }
        time("shopEntries(all)") { _ = store.shopEntries(in: nil) }
        time("shopCategories") { _ = store.shopCategories }
        time("megaStoneShopEntries") { _ = store.megaStoneShopEntries }
        time("machineShopMoves(learnable)") { _ = store.machineShopMoves(learnableOnly: true) }
        time("machineShopMoves(all)") { _ = store.machineShopMoves() }
        let kinds = ItemKind.allCases
        let l = store.l
        time("accessors price/max/canBuy/sold/count x\(kinds.count)", reps: 5) {
            for kind in kinds {
                _ = store.price(of: kind); _ = store.maxBuyCount(kind); _ = store.canBuy(kind)
                _ = store.isSoldOut(kind); _ = store.itemCount(kind); _ = store.itemOwnedTotal(kind)
            }
        }
        time("strings name/desc/note x\(kinds.count)", reps: 5) {
            for kind in kinds { _ = l.itemName(kind); _ = l.itemDescription(kind); _ = l.itemAppNote(kind) }
        }
        time("ownedSpeciesIDs") { _ = store.state.ownedSpeciesIDs }
        time("mega accessors x93", reps: 5) {
            for stone in MegaStone.all {
                _ = store.price(of: .megaStone(stone)); _ = store.canBuy(stone); _ = store.megaStoneCount(stone)
                _ = store.megaStoneOwnedTotal(stone); _ = l.megaStoneDescription(stone); _ = l.megaStoneAppNote(stone)
            }
        }
        print("[probe] counts: all entries \(store.shopEntries(in: nil).count), held sections kinds \(store.shopBattleSections.map(\.kinds.count).reduce(0, +)), evolution \(store.shopAllViewEvolutionItems.count), mega \(store.megaStoneShopEntries.count), TMs \(MachineCatalog.moves.count), owned species \(store.state.ownedSpeciesIDs.count)")

        let categories: [ItemCategory?] = [nil] + ItemCategory.allCases.map(Optional.some)
        for pass in ["cold", "warm"] {
            for category in categories {
                if pass == "cold" { SpriteLoader.imageCache.removeAllObjects() }
                let start = Date()
                autoreleasepool {
                    let host = OffscreenRender.host(ShopView(store: store, nav: PopoverNavigation(), initialCategory: category)
                        .frame(width: PopoverMetrics.contentWidth, height: 520).environment(store),
                        size: CGSize(width: PopoverMetrics.contentWidth, height: 520))
                    host.layoutSubtreeIfNeeded()
                }
                print(String(format: "[probe] %@ render %@: %.1f ms", pass, category?.rawValue ?? "all",
                             Date().timeIntervalSince(start) * 1000))
            }
        }

        for pass in ["bag cold", "bag warm"] {
            let start = Date()
            autoreleasepool {
                let host = OffscreenRender.host(BagView(store: store, nav: PopoverNavigation())
                    .frame(width: PopoverMetrics.contentWidth, height: 520).environment(store),
                    size: CGSize(width: PopoverMetrics.contentWidth, height: 520))
                host.layoutSubtreeIfNeeded()
            }
            print(String(format: "[probe] %@ render all: %.1f ms (%d items)", pass, Date().timeIntervalSince(start) * 1000,
                         store.bagListItems(in: nil).count))
        }

        var counters: [ReadCountingImage] = []
        let names = ItemKind.allCases.compactMap(\.spriteName) + MegaStone.all.map(\.slug)
        for name in Set(names) {
            let image = ReadCountingImage(size: NSSize(width: 30, height: 30))
            counters.append(image)
            pinSprite(image, at: SpriteLoader.cacheDir.appendingPathComponent("item-\(name).png").path as NSString)
        }
        for category in categories {
            let before = counters.map(\.sizeReadCount).reduce(0, +)
            let touched = counters.map(\.sizeReadCount)
            autoreleasepool {
                let host = OffscreenRender.host(ShopView(store: store, nav: PopoverNavigation(), initialCategory: category)
                    .frame(width: PopoverMetrics.contentWidth, height: 520).environment(store),
                    size: CGSize(width: PopoverMetrics.contentWidth, height: 520))
                host.layoutSubtreeIfNeeded()
            }
            let icons = zip(counters.map(\.sizeReadCount), touched).filter { $0 != $1 }.count
            print("[probe] icons laid out \(category?.rawValue ?? "all"): \(icons) distinct, \(counters.map(\.sizeReadCount).reduce(0, +) - before) reads")
        }
    }

    /// PTB_SHOP_SHOT_DIR=/tmp/shots swift test --filter ShopOpenProbeTests/testCaptureShopTabs
    func testCaptureShopTabs() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_SHOP_SHOT_DIR"] else { throw XCTSkip("shots") }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shop-shot-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = 9_000_000_000
        state.dex = [25, 143, 6, 150, 448].map { id in
            DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000), names: [id: ["ko": "F\(id)", "en": "F\(id)"]])
        }
        state.inventory = ["rareCandy": 2, "mint": 1, MachineMove.inventoryKey(85): 1]
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: ProbeOfflineProvider(), fileURL: file,
                                   defaults: UserDefaults(suiteName: "shop-shot-\(UUID())")!)
        let size = CGSize(width: PopoverMetrics.contentWidth, height: 520)
        for language in [AppLanguage.ko, .en] {
            store.setLanguage(language)
            for (name, category) in [("all", nil), ("tm", .machine), ("held", .heldItem), ("mega", .megaStone)] as [(String, ItemCategory?)] {
                try await OffscreenRender.capture(
                    ShopView(store: store, nav: PopoverNavigation(), initialCategory: category)
                        .environment(store).frame(width: size.width, height: size.height)
                        .background(Color.white).environment(\.colorScheme, .light)
                        .environment(\.locale, language.displayLocale),
                    size: size, appearance: .aqua, scale: 2,
                    to: directory.appendingPathComponent("shop-\(name)-\(language.rawValue).png"))
            }
        }
    }
}

private struct ProbeOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}
