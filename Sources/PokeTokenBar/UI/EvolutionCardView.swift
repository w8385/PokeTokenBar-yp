import SwiftUI

/// "In the games … / In this app …" for one special evolution step, with progress when the raised Pokémon is on it.
@MainActor
struct EvolutionCardView: View {
    let store: CompanionStore
    let card: CompanionStore.EvolutionCard

    private var l: L { store.l }

    private func speciesLabel(_ id: Int) -> String {
        store.speciesIndex?.entry(id)?.names[store.language.rawValue] ?? "#\(id)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.isNextStep ? l.evolutionNextStep(speciesLabel(card.rule.species)) : l.evolutionBecomesThisForm)
                .font(.callout.weight(.semibold))
            section(l.evolutionInGames) {
                ForEach(Array(card.rule.original.enumerated()), id: \.offset) { _, original in
                    Text(l.evolutionOriginalText(original, speciesName: speciesLabel))
                }
            }
            section(l.evolutionInApp) {
                if let selector = card.rule.selector { Text(l.evolutionSelectorText(selector)) }
                ForEach(Array(card.rule.paths.enumerated()), id: \.offset) { index, path in
                    if index > 0 { Text(l.evolutionOr).foregroundStyle(.secondary) }
                    ForEach(Array(path.enumerated()), id: \.offset) { _, requirement in
                        requirementRow(requirement)
                    }
                }
                if let trade = card.rule.trade {
                    if !card.rule.paths.isEmpty { Text(l.evolutionOr).foregroundStyle(.secondary) }
                    tradeRows(trade)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content().font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func tradeRows(_ trade: EvolutionTrade) -> some View {
        Text(l.evolutionTradeText(trade, speciesName: speciesLabel))
        if case .holding(let kind) = trade, let id = card.individualID {
            let held = store.heldItem(of: id) == kind
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: held ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(held ? Color.green : Color.secondary)
                Text(l.evolutionItemName(kind))
                Spacer(minLength: 4)
                if store.isTradeLocked(id) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                } else if held {
                    Button(l.heldItemRemove) { _ = store.unequip(from: id) }
                        .buttonStyle(.borderless).controlSize(.small)
                } else if store.itemCount(kind) > 0 {
                    Button(l.heldItemEquip) { _ = store.equip(kind, to: id) }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
            if store.isTradeLocked(id) {
                Text(l.tradeLockedItemText).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func requirementRow(_ requirement: EvolutionRequirement) -> some View {
        let progress = card.context.map { requirement.progress(in: $0) }
        let met = progress.map { $0.have >= $0.need } ?? false
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if progress != nil {
                Image(systemName: met ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(met ? Color.green : Color.secondary)
            } else {
                Text("•").foregroundStyle(.secondary)
            }
            Text(l.evolutionRequirementText(requirement, speciesName: speciesLabel))
            if let progress, progress.need > 1 {
                Text("\(min(progress.have, progress.need))/\(progress.need)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if progress != nil, !met { action(for: requirement) }
        }
    }

    @ViewBuilder
    private func action(for requirement: EvolutionRequirement) -> some View {
        switch requirement {
        case .holds(let kind):
            if let id = store.state.active?.profile?.instanceID, store.itemCount(kind) > 0 {
                Button(l.heldItemEquip) { _ = store.equip(kind, to: id) }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        case .towerChosen:
            Button(l.evolutionTowerDarkness) { store.chooseTower("darkness") }
                .buttonStyle(.borderless).controlSize(.small)
            Button(l.evolutionTowerWaters) { store.chooseTower("waters") }
                .buttonStyle(.borderless).controlSize(.small)
        default:
            EmptyView()
        }
    }
}
