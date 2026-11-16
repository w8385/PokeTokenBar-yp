import SwiftUI

/// The Box's filter menu: type chips (any of the picked types), rarity, lineup, tradable and level. An inline panel
/// under the toolbar — popovers and sheets inside the popover are avoided like everywhere else in the app.
@MainActor
struct BoxFilterPanel: View {
    let store: CompanionStore
    let filters: BoxFilterStore

    private static let typeColumns = [GridItem(.adaptive(minimum: 56), spacing: 4)]
    private static let rarities: [Rarity] = [.common, .uncommon, .rare, .legendary]

    var body: some View {
        let l = store.l
        let filter = filters.filter
        VStack(alignment: .leading, spacing: 8) {
            section(l.boxFilterType) {
                LazyVGrid(columns: Self.typeColumns, alignment: .leading, spacing: 4) {
                    ForEach(PokemonType.allCases, id: \.self) { type in
                        typeChip(type, isSelected: filter.types.contains(type))
                    }
                }
            }
            section(l.boxFilterRarity) {
                HStack(spacing: 4) {
                    ForEach(Self.rarities, id: \.self) { rarity in
                        chip(l.rarityLabel(rarity), isSelected: filter.rarity == rarity) {
                            filters.filter.rarity = filter.rarity == rarity ? nil : rarity
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                chip(l.boxFilterInLineup, isSelected: filter.inLineupOnly) { filters.filter.inLineupOnly.toggle() }
                chip(l.boxFilterTradable, isSelected: filter.tradableOnly) { filters.filter.tradableOnly.toggle() }
            }
            section(l.boxFilterLevel) {
                HStack(spacing: 4) {
                    ForEach(BoxLevelFilter.allCases, id: \.self) { level in
                        chip(l.label(for: level), isSelected: filter.level == level) { filters.filter.level = level }
                    }
                }
            }
            HStack {
                Spacer()
                Button(l.clearFilters) { filters.clear() }
                    .buttonStyle(.borderless).font(.caption)
                    .disabled(filter == BoxFilter() && filters.searchText.isEmpty)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func typeChip(_ type: PokemonType, isSelected: Bool) -> some View {
        Button { filters.filter.types.formSymmetricDifference([type]) } label: {
            Badge(tint: .type(type), style: isSelected ? .solid : .tinted, size: 9,
                  horizontalPadding: 6, verticalPadding: 2) {
                PokemonNameLabel(.type, type.rawValue, language: store.language).textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Bought · Undo" under a shop row for the few seconds a purchase can be taken back.
@MainActor
struct PurchaseUndoLine: View {
    let store: CompanionStore
    let inventoryKey: String

    var body: some View {
        if let receipt = store.purchaseReceipts[inventoryKey] {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                Text(store.l.purchaseDone).font(.caption2.weight(.semibold)).foregroundStyle(.green)
                Spacer()
                Button(store.l.purchaseUndo) { store.undoPurchase(receipt) }
                    .buttonStyle(.borderless).controlSize(.small)
                    .disabled(!store.canUndo(receipt))
            }
            .task(id: receipt.id) {
                try? await Task.sleep(for: .seconds(PurchaseReceipt.window))
                store.dismissReceipt(receipt)
            }
        }
    }
}
