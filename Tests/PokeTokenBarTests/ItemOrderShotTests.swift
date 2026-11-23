import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct OrderShotProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [])]),
                rarity: .common, names: [4: ["ko": "파이리"], 5: ["ko": "리자드"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Bag and the item lists in the order they are shown, for the PR. Writes only when `PTB_ITEM_ORDER_SHOT_DIR` is set.
@MainActor
final class ItemOrderShotTests: XCTestCase {
    /// A sample bag with the same kinds as a real player's save.
    private static let sampleBag: [ItemKind: Int] = [
        .rareCandy: 5, .mint: 4, .shinyCharm: 1, .expShare: 2, .dawnStone: 1, .iceStone: 1, .linkingCord: 2,
        .whippedDream: 1, .prismScale: 1, .abilityCapsule: 5, .abilityPatch: 4, .goldBottleCap: 4, .choiceScarf: 1,
    ]

    func testCaptureItemOrder() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_ITEM_ORDER_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_ITEM_ORDER_SHOT_DIR")
        }
        let dir = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try makeStore()
        let l = store.l

        try await capture(BagView(store: store, nav: PopoverNavigation()).environment(store),
                          width: PopoverMetrics.contentWidth, height: 520, to: dir.appendingPathComponent("bag-all.png"))

        let bagFlat = store.bagListItems(in: nil).map(\.kind)
        try await capture(OrderMap(l: l, blocks: [(l.categoryAll, bagFlat)]
                + store.ownedBattleSections.map { (l.battleItemGroupName($0.group), $0.kinds) }, columns: 1),
                          width: 300, height: 420, to: dir.appendingPathComponent("bag-order.png"))
        try await capture(OrderMap(l: l, blocks: [(l.categoryName(.evolution), store.shopEvolutionItems)], columns: 3),
                          width: 720, height: 420, to: dir.appendingPathComponent("shop-evolution-order.png"))
        let sections = store.shopBattleSections
        let split = sections.firstIndex { $0.group == .bulk } ?? sections.count
        for (name, slice) in [("shop-held-order-1.png", sections[..<split]), ("shop-held-order-2.png", sections[split...])] {
            try await capture(OrderMap(l: l, blocks: slice.map { (l.battleItemGroupName($0.group), $0.kinds) }, columns: 4),
                              width: 960, height: 1100, to: dir.appendingPathComponent(name))
        }
    }

    private func makeStore() throws -> CompanionStore {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("item-order-shot-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.usedSinceInstall = 90_000_000_000
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 2,
                                profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        state.inventory = Dictionary(uniqueKeysWithValues: Self.sampleBag.map { ($0.key.rawValue, $0.value) })
        let file = scratch.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: OrderShotProvider(), fileURL: file)
    }

    private func capture<V: View>(_ view: V, width: CGFloat, height: CGFloat, to file: URL) async throws {
        let size = NSSize(width: width, height: height)
        try await OffscreenRender.capture(view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light),
            size: size, appearance: .aqua, scale: 2, to: file)
    }
}

/// Item names under their headers, row by row, in list order. Icons come from the disk cache only.
private struct OrderMap: View {
    let l: L
    let blocks: [(String, [ItemKind])]
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ItemSectionHeader(title: block.0)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns),
                          alignment: .leading, spacing: 2) {
                    ForEach(Array(block.1.enumerated()), id: \.offset) { index, kind in
                        HStack(spacing: 4) {
                            Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            icon(kind).frame(width: 16, height: 16)
                            Text(l.itemName(kind)).font(.caption).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(8)
    }

    @ViewBuilder private func icon(_ kind: ItemKind) -> some View {
        if let name = kind.spriteName, let image = SpriteLoader.cachedItemImage(name: name) {
            Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
        } else {
            Text(kind.fallbackEmoji).font(.caption2)
        }
    }
}
