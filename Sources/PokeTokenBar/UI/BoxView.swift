import SwiftUI

/// The Box tab: every Pokémon I own, one cell each. The Pokédex tab is about species; this one is about individuals.
@MainActor
struct BoxView: View {
    let store: CompanionStore
    let navigation: PopoverNavigation
    @State private var searchText = ""
    @State private var shinyOnly = false
    @State private var hasItemOnly = false
    @State private var sort: BoxSortOption = .recent
    /// The individual whose page was just closed; the grid scrolls back to it once, because the page replaces the grid.
    @State private var returnAnchor: String?

    static let contentHeight: CGFloat = 520
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    private var isCustomSortActive: Bool { sort != .recent }

    var body: some View {
        let all = store.boxIndividuals
        if all.isEmpty {
            emptyState
        } else if let id = navigation.boxDetailID, let individual = all.first(where: { $0.id == id }) {
            BoxDetailView(store: store, individual: individual, navigation: navigation) {
                returnAnchor = id
                navigation.boxDetailID = nil
            }
            .id(id)
            .frame(height: Self.contentHeight)
        } else {
            grid(all)
                .frame(height: Self.contentHeight)
        }
    }

    private func grid(_ all: [BoxIndividual]) -> some View {
        let visible = store.filteredBoxIndividuals(query: searchText, speciesID: navigation.boxSpeciesFilter,
                                                   shinyOnly: shinyOnly, hasItemOnly: hasItemOnly, sort: sort)
        return VStack(alignment: .leading, spacing: 6) {
            toolbar
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.l.boxTab).font(.callout.weight(.semibold))
                Text(store.l.dexTotal(visible.count)).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if let speciesID = navigation.boxSpeciesFilter {
                speciesFilterChip(speciesID, all: all)
            }
            if store.isLineParked, store.state.active == nil, navigation.boxSpeciesFilter == nil,
               searchText.isEmpty, !shinyOnly, !hasItemOnly {
                parkedEggRow
            }
            if visible.isEmpty {
                emptyResults
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("boxTop")
                            LazyVGrid(columns: Self.columns, spacing: 4) {
                                ForEach(visible) { individual in
                                    BoxCell(store: store, individual: individual) {
                                        navigation.boxDetailID = individual.id
                                    }
                                    .id(individual.id)
                                }
                            }
                        }
                        .reservesScrollerLane()
                    }
                    .task {
                        guard let anchor = returnAnchor else { return }
                        returnAnchor = nil
                        // Lazy cells are placed with estimated heights first; scroll again once they are measured.
                        proxy.scrollTo(anchor, anchor: .center)
                        try? await Task.sleep(for: .milliseconds(50))
                        proxy.scrollTo(anchor, anchor: .center)
                    }
                    .onChange(of: searchText) { scrollToTop(proxy) }
                    .onChange(of: shinyOnly) { scrollToTop(proxy) }
                    .onChange(of: hasItemOnly) { scrollToTop(proxy) }
                    .onChange(of: sort) { scrollToTop(proxy) }
                }
            }
        }
    }

    /// An egg has no Pokémon to put in the grid, so the parked one gets its own row with the resume button.
    private var parkedEggRow: some View {
        let l = store.l
        return HStack(spacing: 8) {
            SpriteView(speciesID: nil, size: 32, animated: false)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(l.parkedEggName).font(.caption.weight(.semibold))
                    Text(l.parkedBadge).font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                }
                Text("\(Int(store.eggProgress * 100))%").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            Button(l.resumeLine) { store.resumeLine() }
                .buttonStyle(.bordered).controlSize(.mini).fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("boxTop", anchor: .top) }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            DexSearchField(l: store.l, text: $searchText)
            DexShinyToggle(l: store.l, isOn: $shinyOnly)
            toolbarButton(systemImage: hasItemOnly ? "bag.fill" : "bag", isActive: hasItemOnly,
                          title: store.l.boxFilterHasItem) { hasItemOnly.toggle() }
            Menu {
                ForEach(BoxSortOption.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        HStack {
                            Text(store.l.label(for: option))
                            if sort == option { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                toolbarIcon("arrow.up.arrow.down", isActive: isCustomSortActive)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(store.l.sortTitle)
            .accessibilityLabel(store.l.sortTitle)
        }
    }

    private func toolbarButton(systemImage: String, isActive: Bool, title: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) { toolbarIcon(systemImage, isActive: isActive) }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func toolbarIcon(_ systemImage: String, isActive: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: isActive ? .bold : .regular))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .frame(width: 16, height: 16)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
    }

    private func speciesFilterChip(_ speciesID: Int, all: [BoxIndividual]) -> some View {
        let name = all.first { $0.speciesID == speciesID }.map { store.dexEntryName($0.entry) } ?? "#\(speciesID)"
        return HStack(spacing: 6) {
            Text(store.l.boxOnlySpecies(name)).font(.caption).lineLimit(1)
            Spacer(minLength: 4)
            Button(store.l.boxShowAll) { navigation.boxSpeciesFilter = nil }
                .buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private var emptyResults: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 24)).foregroundStyle(.tertiary)
            Text(store.l.noSearchResults).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Button(store.l.clearFilters) {
                searchText = ""; shinyOnly = false; hasItemOnly = false; sort = .recent
                navigation.boxSpeciesFilter = nil
            }
            .buttonStyle(.bordered).controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            SpriteView(speciesID: 25, size: 96, animated: true)
            Text(store.l.boxEmptyTitle).font(.callout.weight(.semibold))
            Text(store.l.boxEmptyHint)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// One owned Pokémon in the grid: sprite (its Mega form while it holds the matching stone), level, shiny and
/// gender marks, and the held item in the sprite's bottom corner.
@MainActor
struct BoxCell: View {
    let store: CompanionStore
    let individual: BoxIndividual
    let onTap: () -> Void
    @State private var isHovered = false

    private static let thumb: CGFloat = 56

    private var entry: DexEntry { individual.entry }
    private var held: HeldItemRef? { store.heldItemRef(of: individual.id) }
    private var megaStone: MegaStone? { store.megaStone(of: individual.id, speciesID: individual.speciesID) }

    private var displayName: String {
        let name = store.dexEntryName(entry)
        return megaStone.map { store.l.megaFormName(name, variant: $0.variantSuffix) } ?? name
    }

    var body: some View {
        let mega = store.boxMegaSpriteID(individual)
        Button(action: onTap) {
            VStack(spacing: 1) {
                SpriteView(speciesID: mega ?? individual.speciesID, size: Self.thumb, shiny: entry.isShiny,
                           form: mega == nil ? entry.form : nil,
                           female: mega == nil && entry.profile?.gender == .female)
                    .frame(width: Self.thumb, height: Self.thumb)
                    .overlay(alignment: .bottomTrailing) {
                        if let held { HeldItemBadge(ref: held, size: 20) }
                    }
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 1) {
                            if individual.role == .raising { roleIcon("figure.walk", tint: .accentColor) }
                            else if individual.role == .friend { roleIcon("heart.fill", tint: .pink) }
                            if individual.role == .parked { textTag(store.l.parkedBadge, tint: .orange) }
                            if isRepresentative { textTag(store.l.representativeBadge, tint: Color(red: 0.72, green: 0.48, blue: 0)) }
                        }
                        .frame(maxWidth: Self.thumb, alignment: .leading)
                    }
                (Text(displayName) + GenderGlyph.text(entry.profile?.gender, leadingSpace: true))
                    .font(.system(size: 11))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) { levelTag }
            .overlay(alignment: .topTrailing) {
                if entry.isShiny {
                    Text("✨").font(.system(size: 10)).padding(.horizontal, 2)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .padding(2)
            .background(Color.secondary.opacity(individual.role == .raising ? 0.16 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
            }
            .scaleEffect(isHovered ? 1.04 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip)
        .accessibilityLabel(tooltip)
    }

    private var levelTag: some View {
        Text("Lv\(individual.level)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(rarityColor(entry.rarity))
            .padding(.horizontal, 2)
            .background(.regularMaterial, in: Capsule())
    }

    private var isRepresentative: Bool { store.isRepresentative(entry) }

    private func textTag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9), in: Capsule())
    }

    private func roleIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .padding(2)
            .background(.regularMaterial, in: Circle())
            .accessibilityHidden(true)
    }

    var tooltip: String {
        let l = store.l
        var parts = ["#\(individual.speciesID) \(displayName)", "Lv\(individual.level)", l.rarityLabel(entry.rarity)]
        if entry.isShiny { parts.append(l.dexShinyLabel) }
        if individual.role == .raising { parts.append(l.dexRaising) }
        if individual.role == .parked { parts.append(l.parkedBadge) }
        if individual.role == .friend { parts.append(l.friendLabel) }
        if isRepresentative { parts.append(l.representativeBadge) }
        if let held { parts.append("\(l.heldItemLabel): \(held.name(l))") }
        return parts.joined(separator: " · ")
    }
}

/// The held item as a small round badge — the same mark on the Box cell, the Home sprite tile and the battle picks.
@MainActor
struct HeldItemBadge: View {
    let ref: HeldItemRef
    var size: CGFloat = 20

    var body: some View {
        Group {
            switch ref {
            case .item(let kind): ItemIconView(kind: kind, size: size - 4)
            case .stone(let stone): ItemIconView(stone: stone, size: size - 4)
            }
        }
        .frame(width: size, height: size)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
