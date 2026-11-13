import SwiftUI

/// Light detail page for a species the user does not own: identity, how to get it, its evolution line.
@MainActor
struct UnownedSpeciesDetailView: View {
    let store: CompanionStore
    let species: CompanionStore.DexSpecies
    let onOpen: (String) -> Void
    let onBack: () -> Void
    var spriteStore: SpriteStore = .shared
    var flavorProvider: SpeciesFlavorProviding = SpeciesFlavorClient.shared

    private var index: SpeciesIndex? { store.speciesIndex }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Label(store.l.back, systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("#\(species.id)").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    identityHeader
                    SpeciesFlavorCard(speciesID: species.id, language: store.language, provider: flavorProvider)
                    howToGetCard
                    evolutionLineCard
                }
                .padding(.bottom, 8)
                .reservesScrollerLane()
            }
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 14) {
            SpriteView(speciesID: species.id, size: 104, animated: true, spriteStore: spriteStore)
                .frame(width: 104, height: 104)
                .opacity(0.55)
                .saturation(0.35)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(species.name).font(.title3.weight(.bold))
                    Spacer(minLength: 8)
                    Text(store.l.rarityLabel(species.rarity))
                        .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let types = index?.entry(species.id)?.types, !types.isEmpty {
                    TypeBadges(types: types, language: store.language, size: 11,
                               horizontalPadding: 7, verticalPadding: 2)
                }
                Badge(store.l.dexUnownedBadge, tint: .secondary, style: .tinted, size: 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var howToGetCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.l.dexHowToGetTitle).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Text(howToGet).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private var howToGet: String {
        switch index?.acquisition(of: species.id) ?? .unavailable {
        case .hatch(let rarity): return store.l.dexHowHatch(store.l.rarityLabel(rarity))
        case .evolve(let parent): return store.l.dexHowEvolve(from: name(of: parent))
        case .ditto: return store.l.dexHowDitto
        case .unavailable: return store.l.dexHowUnavailable
        }
    }

    @ViewBuilder private var evolutionLineCard: some View {
        let items = index?.lineItems(of: species.id) ?? []
        if items.count > 1 {
            let owned = store.dexLinkTargets
            let ids = items.compactMap { item -> Int? in
                if case .species(let id) = item { id } else { nil }
            }
            let links = Dictionary(ids.filter { $0 != species.id }.map { ($0, owned[$0] ?? String($0)) },
                                   uniquingKeysWith: { first, _ in first })
            VStack(alignment: .leading, spacing: 6) {
                Text(store.l.dexEvolutionLineTitle).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                EvoLineView(nodes: items.map { item in
                                if case .species(let id) = item { EvoLineItem(item, state(of: id, owned: owned)) }
                                else { EvoLineItem(item, .future) }
                            },
                            mysteryLabel: store.l.unknownNextEvolution, language: store.language, thumb: 56,
                            names: Dictionary(ids.map { ($0, name(of: $0)) }, uniquingKeysWith: { first, _ in first }),
                            maxWidth: PopoverMetrics.scrollContentWidth - 18,
                            nameFontSize: 11, nameLineLimit: 2, nameMinimumScaleFactor: 1,
                            dexLinks: links, onOpenDexEntry: onOpen, spriteStore: spriteStore)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private func state(of id: Int, owned: [Int: String]) -> EvoLineItemState {
        if id == species.id { return .current }
        return owned[id] == nil ? .future : .done
    }

    private func name(of id: Int) -> String {
        index?.entry(id).flatMap { store.language.resolveName($0.names) } ?? "#\(id)"
    }
}
