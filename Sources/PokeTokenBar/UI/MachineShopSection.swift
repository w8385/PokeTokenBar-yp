import SwiftUI

/// The shop's TM category: search, a type filter, a "my Pokémon can learn it" toggle and one card per move.
@MainActor
struct MachineShopSection: View {
    let store: CompanionStore
    @State private var query: String
    @State private var type: PokemonType?
    @State private var learnableOnly: Bool

    init(store: CompanionStore, initialQuery: String = "", initialLearnableOnly: Bool = true) {
        self.store = store
        _query = State(initialValue: initialQuery)
        _type = State(initialValue: nil)
        _learnableOnly = State(initialValue: initialLearnableOnly)
    }

    var body: some View {
        let l = store.l
        let moves = store.machineShopMoves(query: query, type: type?.rawValue, learnableOnly: learnableOnly)
        VStack(alignment: .leading, spacing: 10) {
            Text(l.shopMachineHint).font(.caption2).foregroundStyle(.tertiary)
            DexSearchField(l: l, text: $query, placeholder: l.shopMachineSearchPrompt)
            learnableToggle(l)
            typeChips
            if moves.isEmpty {
                Text(l.shopMachineEmpty).font(.caption).foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 10) {
                ForEach(moves) { MachineShopCard(store: store, move: $0) }
            }
        }
    }

    private func learnableToggle(_ l: L) -> some View {
        Button {
            learnableOnly.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: learnableOnly ? "checkmark.circle.fill" : "circle")
                Text(l.shopMachineLearnableOnly)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(learnableOnly ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .ptbChip(active: learnableOnly ? .accent : nil)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(learnableOnly ? .isSelected : [])
    }

    private var typeChips: some View {
        let present = Set(MachineCatalog.moves.map(\.type))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(PokemonType.allCases.filter { present.contains($0.rawValue) }, id: \.self) { candidate in
                    Button {
                        type = type == candidate ? nil : candidate
                    } label: {
                        Badge(tint: .type(candidate), style: type == candidate ? .solid : .tinted, size: 9,
                              horizontalPadding: 7, verticalPadding: 3) {
                            PokemonNameLabel(.type, candidate.rawValue, language: store.language).textCase(.uppercase)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(type == candidate ? .isSelected : [])
                }
            }
        }
    }
}

@MainActor
struct MachineShopCard: View {
    let store: CompanionStore
    let move: MachineEntry

    var body: some View {
        let l = store.l
        let mine = MachineCatalog.learners(of: move.id, among: store.state.ownedSpeciesIDs).count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "opticaldisc.fill")
                    .font(.ptb(.lead)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background((PokemonType(apiName: move.type)?.color ?? .gray), in: RoundedRectangle(cornerRadius: Radius.chip))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(move.name(store.language)).font(.callout.weight(.semibold))
                        TypeBadges(types: [move.type], language: store.language)
                        Spacer(minLength: 4)
                    }
                    Text(move.isWeather ? l.moveWeatherMove : l.movePowerLine(move.power))
                        .font(.caption).foregroundStyle(.secondary)
                    if mine > 0 { Badge(l.shopMachineMine(mine), tint: .accent) }
                }
            }
            controls(l)
            PurchaseUndoLine(store: store, inventoryKey: MachineMove.inventoryKey(move.id))
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
    }

    @ViewBuilder
    private func controls(_ l: L) -> some View {
        let price = store.tmPrice(power: move.power, isWeather: move.isWeather)
        if store.ownsTM(move.id) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
                Text(l.ownedAlready).font(.caption2.weight(.semibold)).foregroundStyle(.green)
                Spacer()
            }
        } else {
            HStack {
                Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price))")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.canBuyTM(power: move.power, isWeather: move.isWeather) {
                    Button(l.buy) { store.buyTM(moveID: move.id, power: move.power, isWeather: move.isWeather) }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
