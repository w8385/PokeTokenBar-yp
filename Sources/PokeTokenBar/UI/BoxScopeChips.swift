import SwiftUI

/// The Pokédex header's region and grade rows, counted over Box individuals instead of species.
@MainActor
struct BoxScopeChips: View {
    struct Chip<Value: Hashable>: Hashable {
        let value: Value
        let count: Int
        let isSelected: Bool
        var isEnabled: Bool { count > 0 || isSelected }
    }

    let l: L
    let all: [BoxIndividual]
    let filters: BoxFilterStore

    static func regionChips(_ all: [BoxIndividual], filter: BoxFilter) -> [Chip<PokedexRegion>] {
        let counts = Dictionary(grouping: all.compactMap { PokedexRegion.region(forDexNumber: $0.speciesID) },
                                by: { $0 }).mapValues(\.count)
        return PokedexRegion.allCases.map { Chip(value: $0, count: counts[$0] ?? 0, isSelected: filter.region == $0) }
    }

    static func rarityChips(_ all: [BoxIndividual], filter: BoxFilter) -> [Chip<Rarity>] {
        let counts = Dictionary(grouping: all.map(\.entry.rarity), by: { $0 }).mapValues(\.count)
        return rarityDisplayOrder.map { Chip(value: $0, count: counts[$0] ?? 0, isSelected: filter.rarity == $0) }
    }

    var body: some View {
        let filter = filters.filter
        VStack(alignment: .leading, spacing: 5) {
            row {
                ForEach(Self.regionChips(all, filter: filter), id: \.value) { chip in
                    button(chip, label: l.regionName(chip.value), color: .secondary, help: l.boxRegionChipHint) {
                        filters.filter.toggleRegion(chip.value)
                    }
                }
            }
            row {
                ForEach(Self.rarityChips(all, filter: filter), id: \.value) { chip in
                    button(chip, label: l.rarityLabel(chip.value), color: rarityColor(chip.value), help: l.dexFilterHint) {
                        filters.filter.toggleRarity(chip.value)
                    }
                }
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) { content() }
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func button<Value>(_ chip: Chip<Value>, label: String, color: Color, help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RarityTally(label: label, count: chip.count, color: color, isSelected: chip.isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!chip.isEnabled)
        .help(help)
        .accessibilityAddTraits(chip.isSelected ? .isSelected : [])
    }
}
