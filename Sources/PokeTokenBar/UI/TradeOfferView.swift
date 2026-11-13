import SwiftUI

/// Battle tab screen: pick one of your graduated Pokémon and a linked coworker, then send the offer.
/// The coworker answers in a Slack DM; the trade lands on the next sync after both accept.
@MainActor
struct TradeOfferView: View {
    let store: CompanionStore
    let uploader: PartyUploader
    let fighterID: String?
    let onBack: () -> Void

    @State private var give: String?
    @State private var coworkers: [TradeCoworker]?
    @State private var target: String?
    @State private var phase = Phase.idle
    @State private var loadFailed = false

    enum Phase: Equatable { case idle, sending, sent(String), refused(String), failed }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
    private var l: L { store.l }

    init(store: CompanionStore, uploader: PartyUploader, fighterID: String?, initialGive: String? = nil,
         initialCoworkers: [TradeCoworker]? = nil, onBack: @escaping () -> Void) {
        self.store = store
        self.uploader = uploader
        self.fighterID = fighterID
        self.onBack = onBack
        _give = State(initialValue: initialGive)
        _coworkers = State(initialValue: initialCoworkers)
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
        .task { await loadCoworkers() }
    }

    private var entries: [DexEntry] { store.tradableEntries(fighterID: fighterID) }

    private var pokemonSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(l.tradePickPokemon)
            if entries.isEmpty {
                Text(l.tradeNoPokemon).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: Self.columns, spacing: 4) {
                    ForEach(entries) { entry in
                        DexSpeciesCell(store: store, species: species(of: entry), isSelected: entry.id == give,
                                       isRepresentative: false, formCount: nil, level: entry.profile?.level) {
                            give = entry.id
                            phase = .idle
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
            if let coworkers {
                if coworkers.isEmpty {
                    Text(l.tradeNoCoworkers).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(coworkers) { coworker in
                            coworkerRow(coworker)
                            if coworker != coworkers.last { Divider() }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
                }
            } else if loadFailed {
                Text(l.tradeCoworkersUnavailable).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(l.tradeLoadingCoworkers).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func coworkerRow(_ coworker: TradeCoworker) -> some View {
        Button {
            target = coworker.id
            phase = .idle
        } label: {
            HStack {
                Image(systemName: target == coworker.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(target == coworker.id ? Color.accentColor : .secondary)
                Text(coworker.name).font(.callout)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                send()
            } label: {
                Text(phase == .sending ? l.tradeSending : l.tradeSendOffer)
            }
            .buttonStyle(.borderedProminent)
            .disabled(give == nil || target == nil || phase == .sending)
            switch phase {
            case .sent(let name):
                Text(l.tradeOfferSent(name)).font(.caption).foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            case .refused(let message):
                Text(message).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed:
                Text(l.tradeSendFailed).font(.caption).foregroundStyle(.orange)
            case .idle, .sending:
                Text(l.tradeSectionHint).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func send() {
        guard let give, let target, let name = coworkers?.first(where: { $0.id == target })?.name else { return }
        phase = .sending
        Task {
            switch await uploader.proposeTrade(to: target, give: give) {
            case .sent:
                phase = .sent(name)
                self.give = nil
                self.target = nil
            case .refused(let message): phase = .refused(message)
            case .failed: phase = .failed
            }
        }
    }

    private func loadCoworkers() async {
        guard coworkers == nil else { return }
        coworkers = await uploader.coworkers()
        loadFailed = coworkers == nil
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
