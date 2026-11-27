import SwiftUI

/// The tower's BP exchange: growth and battle items, the Mega Stones of species in the Box, the legendary scout ticket.
@MainActor
struct TowerExchangeView: View {
    let store: CompanionStore
    let onClose: () -> Void

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(l.towerExchange).font(.callout.weight(.semibold))
                Spacer()
                Text(l.towerBP(store.state.tower.bp)).font(.callout.weight(.semibold)).monospacedDigit()
            }
            Text(l.towerExchangeNote).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Spacing.xs) {
                ForEach(store.towerGoods, id: \.self) { row($0) }
            }
            HStack {
                Spacer()
                Button(l.close, action: onClose).controlSize(.small)
            }
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
    }

    private func row(_ good: TowerGood) -> some View {
        HStack(spacing: Spacing.md) {
            icon(good).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.sm) {
                    Text(name(good)).font(.caption.weight(.semibold)).lineLimit(1)
                    let owned = owned(good)
                    if owned > 0 {
                        Text(l.ownedCount(owned)).font(.caption2.weight(.bold)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if let price = store.bpPrice(of: good) {
                    Text(l.towerBP(price)).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            Spacer(minLength: Spacing.xs)
            Button(l.towerExchangeAction) { store.exchange(good) }
                .buttonStyle(.bordered).controlSize(.small).disabled(!store.canExchange(good))
        }
        .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
        .ptbPanel()
    }

    @ViewBuilder
    private func icon(_ good: TowerGood) -> some View {
        switch good {
        case .item(let kind): ItemIconView(kind: kind, size: 22)
        case .stone(let stone): ItemIconView(stone: stone, size: 22)
        case .legendaryScout: ScoutTicketIcon(size: 22)
        }
    }

    private func name(_ good: TowerGood) -> String {
        switch good {
        case .item(let kind): l.itemName(kind)
        case .stone(let stone): l.megaStoneName(stone)
        case .legendaryScout: l.scoutTicketName(.legendary)
        }
    }

    private func owned(_ good: TowerGood) -> Int {
        switch good {
        case .item(let kind): store.itemCount(kind)
        case .stone(let stone): store.megaStoneOwnedTotal(stone)
        case .legendaryScout: store.scoutTicketCount(.legendary)
        }
    }
}
