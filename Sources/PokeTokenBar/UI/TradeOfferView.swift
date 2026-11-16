import SwiftUI

/// Friends tab screen: pick one of your graduated Pokémon and a linked coworker, then send the offer.
/// The coworker answers in a Slack DM; the trade lands on the next sync after both accept.
@MainActor
struct TradeOfferView: View {
    let store: CompanionStore
    let fightingIDs: Set<String>
    let onBack: () -> Void

    @State private var model: TradeOfferModel
    @State private var changing = false
    private let startsPreselected: Bool

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
    private var l: L { store.l }

    init(store: CompanionStore, uploader: PartyUploader, fightingIDs: Set<String>, initialGive: String? = nil,
         initialCoworkers: [TradeCoworker]? = nil, onBack: @escaping () -> Void) {
        self.store = store
        self.fightingIDs = fightingIDs
        self.onBack = onBack
        startsPreselected = initialGive != nil
        _model = State(initialValue: TradeOfferModel(uploader: uploader, give: initialGive, coworkers: initialCoworkers))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onBack) { Label(l.back, systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(l.tradeOfferTitle).font(.callout.weight(.semibold))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pokemonSection
                    coworkerSection
                    sendSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .reservesScrollerLane()
            }
        }
        .task { await model.load() }
    }

    private var entries: [DexEntry] { store.tradableEntries(fightingIDs: fightingIDs) }

    private var givenEntry: DexEntry? { entries.first { $0.id == model.give } }

    private var collapsed: Bool { Self.collapsesGrid(startsPreselected: startsPreselected, changing: changing,
                                                      hasGive: givenEntry != nil) }

    static func collapsesGrid(startsPreselected: Bool, changing: Bool, hasGive: Bool) -> Bool {
        startsPreselected && !changing && hasGive
    }

    @ViewBuilder
    private var pokemonSection: some View {
        if let givenEntry, collapsed {
            HStack(spacing: 6) {
                Text(l.tradeGivingSummary(store.dexEntryName(givenEntry))).font(.callout)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Button(l.tradeChange) { changing = true }
                    .buttonStyle(.borderless).controlSize(.small)
            }
            .padding(.horizontal, 4)
        } else {
            pokemonGrid
        }
    }

    private var pokemonGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(l.tradePickPokemon)
            if entries.isEmpty {
                Text(l.tradeNoPokemon).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: Self.columns, spacing: 4) {
                    ForEach(entries) { entry in
                        DexSpeciesCell(store: store, species: species(of: entry), isSelected: entry.id == model.give,
                                       isRepresentative: false, formCount: nil, level: entry.profile?.level) {
                            model.pickGive(entry.id)
                            changing = false
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(l.tradeRefusalText(.raising))
                Text(l.tradeRefusalText(.fighting))
            }
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var coworkerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(l.tradePickCoworker)
            TradeCoworkerPicker(model: model, l: l)
        }
    }

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await model.send() }
            } label: {
                Text(model.phase == .sending ? l.tradeSending : l.tradeSendOffer)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSend)
            TradePhaseLine(phase: model.phase, l: l)
            if model.phase == .idle || model.phase == .sending {
                Text(l.tradeSectionHint).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func species(of entry: DexEntry) -> CompanionStore.DexSpecies {
        CompanionStore.DexSpecies(id: entry.finalID, name: store.dexEntryName(entry), rarity: entry.rarity,
                                  isShiny: entry.isShiny, isRaising: false,
                                  form: PokemonForm.resolved(speciesID: entry.finalID, form: entry.form),
                                  names: entry.names?[entry.finalID], hasNormal: !entry.isShiny)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            .textCase(.uppercase).padding(.leading, 4)
    }
}

/// Box detail panel: the coworker list for one Pokémon, a confirm row for the picked friend, the result line.
@MainActor
struct BoxTradePanel: View {
    let store: CompanionStore
    let pokemonName: String
    @State private var model: TradeOfferModel
    private var l: L { store.l }

    init(store: CompanionStore, uploader: PartyUploader, individualID: String, pokemonName: String,
         initialTarget: String? = nil, initialCoworkers: [TradeCoworker]? = nil) {
        self.store = store
        self.pokemonName = pokemonName
        _model = State(initialValue: TradeOfferModel(uploader: uploader, give: individualID, target: initialTarget,
                                                     coworkers: initialCoworkers))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.tradePickCoworker)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            TradeCoworkerPicker(model: model, l: l)
            if let friend = model.targetName, model.give != nil {
                HStack(spacing: 8) {
                    Text(l.tradeConfirmLine(friend: friend, pokemon: pokemonName)).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(model.phase == .sending ? l.tradeSending : l.tradeSend) {
                        Task { await model.send() }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!model.canSend)
                }
            }
            TradePhaseLine(phase: model.phase, l: l)
        }
        .task { await model.load() }
    }
}

/// Top-of-popover notice for the newest arrival or Linking Cord evolution.
@MainActor
struct TradeArrivalBanner: View {
    let store: CompanionStore

    var body: some View {
        if let arrival = store.tradeArrival {
            let l = store.l
            HStack(spacing: 10) {
                SpriteView(speciesID: arrival.evolvedID ?? arrival.receivedID, size: 44, animated: true,
                           shiny: arrival.isShiny)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    if let sender = arrival.fromName {
                        Text(l.tradeArrivalReceived(arrival.receivedName, from: sender))
                            .font(.caption.weight(.semibold))
                    }
                    if let evolved = arrival.evolvedName {
                        Text(l.tradeArrivalEvolved(arrival.receivedName, evolved))
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { store.dismissTradeArrival() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).controlSize(.small)
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .id(arrival.id)
            .transition(.opacity)
        }
    }
}
