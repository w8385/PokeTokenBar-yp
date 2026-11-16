import SwiftUI

/// One owned Pokémon's page. The held item slot is the only place an item is equipped and the move section the
/// only place its battle moves are chosen; everything else the Pokémon can do on its own (battle, trade,
/// Linking Cord, friend) sits under them.
@MainActor
struct BoxDetailView: View {
    let store: CompanionStore
    let individual: BoxIndividual
    let navigation: PopoverNavigation
    let onBack: () -> Void
    @Environment(BattleEntryStore.self) private var battleEntry: BattleEntryStore?
    @Environment(PartyUploader.self) private var uploader: PartyUploader?
    @State private var cordMessage: String?
    @State private var tradePanelOpen = false
    /// Capture hooks: open the trade panel on appear, optionally with a friend already picked.
    var opensTradePanel = false
    var initialTradeTarget: String?

    private var l: L { store.l }
    private var entry: DexEntry { individual.entry }
    private var name: String { store.dexEntryName(entry) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onBack) { Label(l.back, systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text("#\(individual.speciesID)").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    identityHeader
                    HeldItemSlot(store: store, individualID: individual.id, speciesID: individual.speciesID,
                                 speciesName: name, lineupSlots: battleEntry?.slots ?? []) {
                        Task { await uploader?.tick() }
                    }
                    moveTraining
                    actions
                    ForEach(store.evolutionCards(for: individual.speciesID, individual: entry)) {
                        EvolutionCardView(store: store, card: $0)
                    }
                    if let details = store.pokemonDetailsByID[individual.speciesID], let profile = entry.profile {
                        individualSection(profile: profile, details: details)
                    } else if entry.profile != nil {
                        PokemonDetailsPlaceholder(store: store, speciesID: individual.speciesID)
                    }
                }
                .padding(.bottom, 8)
                .reservesScrollerLane()
            }
        }
        .task {
            await store.loadPokemonDetails(speciesID: individual.speciesID)
            await store.loadEvolutionCardNames(for: individual.speciesID, individual: entry)
        }
    }

    // MARK: Identity

    private var identityHeader: some View {
        let mega = store.boxMegaSpriteID(individual)
        let stone = store.megaStone(of: individual.id, speciesID: individual.speciesID)
        return HStack(spacing: 14) {
            MegaEvolveStage(megaSpriteID: mega, size: 104, event: store.megaEvolveEvent) { shown in
                SpriteView(speciesID: shown ?? individual.speciesID, size: 104, animated: true, shiny: entry.isShiny,
                           form: shown == nil ? entry.form : nil,
                           female: shown == nil && entry.profile?.gender == .female)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    (Text(stone.map { l.megaFormName(name, variant: $0.variantSuffix) } ?? name)
                        + GenderGlyph.text(entry.profile?.gender, leadingSpace: true))
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 8)
                    Text(l.rarityLabel(entry.rarity)).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let stone {
                    TypeBadges(types: stone.types, language: store.language, size: 11,
                               horizontalPadding: 7, verticalPadding: 2)
                } else if let details = store.pokemonDetailsByID[individual.speciesID] {
                    TypeBadges(types: details.types, language: store.language, size: 11,
                               horizontalPadding: 7, verticalPadding: 2)
                }
                HStack(spacing: 6) {
                    Text("Lv\(individual.level)").font(.callout.weight(.semibold)).monospacedDigit()
                    if entry.isShiny { Text("✨ \(l.dexShinyLabel)").font(.callout) }
                }
                switch individual.role {
                case .raising: Text(l.dexRaising).font(.callout).foregroundStyle(Color.accentColor)
                case .parked: Text(l.parkedBadge).font(.callout).foregroundStyle(.orange)
                case .friend: Text(l.friendLabel).font(.callout).foregroundStyle(.pink)
                case .graduated: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Training

    /// Needs the bot: the move list is the bot's, and its answer is the only source for what this Pokémon may use.
    @ViewBuilder
    private var moveTraining: some View {
        if let battleEntry, let uploader, uploader.hasToken, uploader.hasServer,
           let candidate = store.battleCandidate(for: entry) {
            MoveTrainingSection(store: store, battleEntry: battleEntry, uploader: uploader, candidate: candidate) {
                Task { await uploader.tick() }
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            WrappingHStack(spacing: 6, lineSpacing: 6) {
                if let battleEntry, store.battleCandidate(for: entry) != nil {
                    BattleSlotControl(store: store, entry: entry, battleEntry: battleEntry) {
                        Task { await uploader?.tick() }
                    }
                }
                raiseButton
                representativeButton
                friendButton
                tradeButtons
                if let target = store.dexLinkTargets[individual.speciesID] {
                    Button {
                        navigation.openDexEntry(collectionID: target)
                    } label: {
                        Label(l.boxViewInDex, systemImage: "book")
                    }
                    .buttonStyle(.bordered).controlSize(.mini).fixedSize()
                }
            }
            tradeNotes
            if tradePanelOpen, let uploader {
                BoxTradePanel(store: store, uploader: uploader, individualID: individual.id, pokemonName: name,
                              initialTarget: initialTradeTarget)
            }
        }
        .onAppear { if opensTradePanel { tradePanelOpen = true } }
    }

    @ViewBuilder
    private var raiseButton: some View {
        switch individual.role {
        case .graduated, .friend:
            Button { store.raise(entryID: individual.id) } label: {
                Label(l.raiseThis, systemImage: "figure.walk")
            }
            .buttonStyle(.bordered).controlSize(.mini).fixedSize()
            .disabled(!store.canRaise(entryID: individual.id))
        case .parked:
            Button { store.resumeLine() } label: {
                Label(l.resumeLine, systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered).controlSize(.mini).fixedSize()
        case .raising:
            EmptyView()
        }
    }

    private var representativeButton: some View {
        let isRepresentative = store.isRepresentative(entry)
        return Button { store.toggleRepresentative(of: entry) } label: {
            Label(isRepresentative ? l.representativeClear : l.representativeSetHere,
                  systemImage: isRepresentative ? "star.slash" : "star")
        }
        .buttonStyle(.bordered).controlSize(.mini).fixedSize()
    }

    @ViewBuilder
    private var friendButton: some View {
        switch individual.role {
        case .friend:
            Button { store.removeFriend(entryID: individual.id) } label: {
                Label(l.friendRemove, systemImage: "heart.slash")
            }
            .buttonStyle(.bordered).controlSize(.mini).fixedSize()
        case .graduated:
            Button { store.addFriend(entryID: individual.id) } label: {
                Label(l.friendAdd, systemImage: "heart")
            }
            .buttonStyle(.bordered).controlSize(.mini).fixedSize()
            .disabled(store.state.friendEntryIDs.count >= CompanionState.maxFriends)
        case .raising, .parked:
            EmptyView()
        }
    }

    private var tradeRefusal: TradeRefusal? {
        let fightingIDs = battleEntry.map { TradePool.fightingIDs(state: store.state, slots: $0.slots) } ?? []
        return store.tradeRefusal(for: entry, fightingIDs: fightingIDs)
    }

    /// Graduated Pokémon only: the raised and the parked ones are not tradeable and a Linking Cord needs a settled
    /// individual.
    private var isGraduated: Bool { individual.role != .raising && individual.role != .parked && entry.profile != nil }

    @ViewBuilder
    private var tradeButtons: some View {
        if let uploader, uploader.hasToken, uploader.hasServer, tradeRefusal != .unavailable {
            Button {
                tradePanelOpen.toggle()
            } label: {
                Label(l.tradeOfferButton, systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.bordered).controlSize(.mini).fixedSize()
            .disabled(tradeRefusal != nil)
        }
        if isGraduated, store.itemCount(.linkingCord) > 0 {
            Button {
                Task { await useLinkingCord() }
            } label: {
                Label(l.linkingCordUse, systemImage: "link")
            }
            .buttonStyle(.bordered).controlSize(.mini).fixedSize()
        }
    }

    @ViewBuilder
    private var tradeNotes: some View {
        if let refusal = tradeRefusal, refusal == .raising || refusal == .parked || refusal == .fighting,
           uploader?.hasToken == true {
            Text(l.tradeRefusalText(refusal)).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let cordMessage {
            Text(cordMessage).font(.caption2).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func useLinkingCord() async {
        cordMessage = nil
        switch await store.useLinkingCord(on: individual.id) {
        case .evolved: break   // The page follows the same individual; the popover banner shows the result.
        case .wrongTarget: cordMessage = l.linkingCordWrongTarget(name)
        case .notReady: cordMessage = l.linkingCordNotReady(name)
        case .unavailable: cordMessage = l.linkingCordUnavailable
        case .listed: cordMessage = l.tradeLockedItemText
        }
    }

    // MARK: Individual data

    private func individualSection(profile: PokemonProfile, details: PokemonDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailTitle(l.pokemonIndividual)
            HStack(spacing: 12) {
                DetailValuePair(l.level, "\(profile.level)")
                DetailValuePair(l.gender, l.genderLabel(profile.gender))
                DetailValuePair(l.nature, entry.nature?.name(store.language) ?? "—")
            }
            if let trainer = entry.originalTrainer {
                Text(l.originalTrainerLine(trainer)).font(.caption).foregroundStyle(.secondary)
            }
            if let partner = entry.tradedTo {
                Text(l.tradedAwayLine(partner)).font(.caption).foregroundStyle(.secondary)
            }
            if let prayers = entry.prayers, prayers.count > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.prayerBornWith(prayers.count)).font(.callout)
                    Text(l.prayerReachedHeaven)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(l.ability).font(.ptb(.body)).foregroundStyle(.secondary)
                if let abilityName = profile.abilityName {
                    PokemonNameLabel(.ability, abilityName, language: store.language,
                                     suffix: profile.abilityIsHidden ? " · " + l.hiddenAbility : "")
                        .font(.callout.weight(.semibold))
                } else {
                    Text("—").font(.callout.weight(.semibold))
                }
            }
            statsSection(PokemonStatCalculator.stats(details: details, profile: profile, nature: entry.nature))
            DetailTitle(l.activeMoves)
            if profile.moves.isEmpty {
                Text(l.noLevelMoves).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(profile.moves) { move in
                    HStack {
                        PokemonNameLabel(.move, move.name, language: store.language)
                        Spacer()
                        Text("Lv. \(move.learnedAtLevel)").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .detailCard()
    }

    private func statsSection(_ stats: [PokemonComputedStat]) -> some View {
        let scaleMaximum = PokemonStatCalculator.displayScaleMaximum(for: stats.map(\.value))
        return VStack(alignment: .leading, spacing: 5) {
            DetailTitle(l.actualStats)
            ForEach(stats) { stat in
                PokemonStatRow(l: l, name: stat.name, value: stat.value, iv: stat.iv, scaleMaximum: scaleMaximum)
            }
        }
    }
}

/// The big held item slot at the top of a Box page: what it holds, what it does, and equip / swap / remove.
/// Every other screen only shows the item and links here.
@MainActor
struct HeldItemSlot: View {
    let store: CompanionStore
    let individualID: String
    let speciesID: Int
    let speciesName: String
    /// The battle lineup picks; an item another lineup member holds cannot be given to a lineup member.
    var lineupSlots: [BattleEntrySlot] = []
    /// Called after the item changed, so the bot's copy of the party follows.
    let onChange: () -> Void

    private var l: L { store.l }

    var body: some View {
        let held = store.heldItemRef(of: individualID)
        let locked = store.isTradeLocked(individualID)
        let spare = store.equippableBagItems
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                icon(held)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.heldItemLabel).font(.caption).foregroundStyle(.secondary)
                    Text(held?.name(l) ?? l.heldItemNone).font(.headline).lineLimit(2)
                }
                Spacer(minLength: 4)
                if locked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).help(l.tradeLockedItemText)
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        if !spare.isEmpty {
                            Menu(held == nil ? l.heldItemEquip : l.heldItemSwap) {
                                ForEach(spare, id: \.self) { ref in
                                    Button("\(ref.name(l)) ×\(store.bagCount(of: ref))") {
                                        if store.equip(ref, to: individualID) { onChange() }
                                    }
                                    .disabled(clash(ref))
                                }
                            }
                            .controlSize(.small).fixedSize()
                        }
                        if held != nil {
                            Button(l.heldItemRemove) {
                                if store.unequip(from: individualID) { onChange() }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            note(held, locked: locked, hasSpare: !spare.isEmpty)
            if !locked, spare.contains(where: clash) {
                caption(l.battleItemClause, color: .orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func clash(_ ref: HeldItemRef) -> Bool {
        BattleEntry.equipClash(ref.inventoryKey, onto: individualID, state: store.state, slots: lineupSlots)
    }

    @ViewBuilder
    private func icon(_ held: HeldItemRef?) -> some View {
        Group {
            switch held {
            case .item(let kind): ItemIconView(kind: kind, size: 38)
            case .stone(let stone): ItemIconView(stone: stone, size: 38)
            case nil: Image(systemName: "bag").font(.ptb(.title)).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 52, height: 52)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private func note(_ held: HeldItemRef?, locked: Bool, hasSpare: Bool) -> some View {
        if locked {
            caption(l.tradeLockedItemText, color: .orange)
        } else if case .item(let kind) = held {
            caption(kind.isHeldItem ? l.heldItemEffect(kind) : l.itemAppNote(kind), color: .secondary)
        } else if case .stone(let stone) = held {
            let matches = stone.speciesID == speciesID
            caption(matches ? l.megaStoneEffect : l.megaStoneWrongHolder(l.megaStoneName(stone), speciesName),
                    color: matches ? .secondary : .orange)
        } else if !hasSpare {
            caption(l.heldItemNoneOwned, color: Color(nsColor: .tertiaryLabelColor))
        }
    }

    private func caption(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}
