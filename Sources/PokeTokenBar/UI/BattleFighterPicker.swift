import SwiftUI

/// Sprite grid of the owned Pokémon that can battle. It does not know which slot it fills: the
/// caller passes that slot's `current` pick and handles `onPick`, so one view serves any slot.
@MainActor
struct BattleFighterPicker: View {
    let store: CompanionStore
    /// `BattleCandidate.id` of the Pokémon now in this slot.
    let current: String?
    /// Candidates already in other slots; they are not offered again.
    let excluding: Set<String>
    /// Whether "follow the Pokémon being raised" is offered; only a lone pick can do that.
    let allowsAuto: Bool
    /// A candidate id, or nil for "follow the Pokémon being raised".
    let onPick: (String?) -> Void
    let onBack: () -> Void

    @State private var query: String
    @State private var rarity: Rarity?
    @State private var shinyOnly = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    init(store: CompanionStore, current: String?, excluding: Set<String> = [], allowsAuto: Bool = true,
         initialQuery: String = "", onPick: @escaping (String?) -> Void, onBack: @escaping () -> Void) {
        self.store = store
        self.current = current
        self.excluding = excluding
        self.allowsAuto = allowsAuto
        self.onPick = onPick
        self.onBack = onBack
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let l = store.l
        let all = BattleEntry.candidates(in: store.state).filter { !excluding.contains($0.id) }
        let visible = store.filteredBattleCandidates(query: query, rarity: rarity, shinyOnly: shinyOnly)
            .filter { !excluding.contains($0.id) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onBack) { Label(l.back, systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(l.battleEntryLabel).font(.callout.weight(.semibold))
            }
            HStack(spacing: 6) {
                DexSearchField(l: l, text: $query)
                DexShinyToggle(l: l, isOn: $shinyOnly)
            }
            rarityChips(all)
            if allowsAuto {
                Button { onPick(nil) } label: {
                    Label(l.battleEntryAutoPick, systemImage: "arrow.triangle.2.circlepath").font(.caption)
                }
                .buttonStyle(.borderless)
            }
            if visible.isEmpty {
                emptyResults
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 4) {
                        ForEach(visible) { candidate in
                            if let species = store.battleSpecies(for: candidate) {
                                DexSpeciesCell(store: store, species: species,
                                               isSelected: candidate.id == current, isRepresentative: false,
                                               formCount: nil, level: candidate.member.level) {
                                    onPick(candidate.id)
                                }
                            }
                        }
                    }
                    .reservesScrollerLane()
                }
            }
        }
    }

    private func rarityChips(_ all: [BattleCandidate]) -> some View {
        let counts = Dictionary(grouping: all.compactMap { store.dexEntry(for: $0)?.rarity }, by: { $0 })
            .mapValues(\.count)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(rarityDisplayOrder, id: \.self) { r in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { rarity = (rarity == r) ? nil : r }
                    } label: {
                        RarityTally(label: store.l.rarityLabel(r), count: counts[r] ?? 0,
                                    color: rarityColor(r), isSelected: rarity == r)
                    }
                    .buttonStyle(.plain)
                    .disabled((counts[r] ?? 0) == 0)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyResults: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 24)).foregroundStyle(.tertiary)
            Text(store.l.noSearchResults).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Button(store.l.clearFilters) {
                query = ""; rarity = nil; shinyOnly = false
            }
            .buttonStyle(.bordered).controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
