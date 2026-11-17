import SwiftUI

/// Hop, turn and bubble for one Pokémon of a `PetCrowd`. The hop is a one-shot keyframe per trigger change,
/// never a loop; the crowd only changes its state while motion is allowed.
@MainActor
struct CrowdMember: ViewModifier {
    let crowd: PetCrowd
    let slot: Int
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: crowd.isFacingRight(slot) ? -1 : 1, y: 1)
            .animation(crowd.motionAllowed ? .easeInOut(duration: 0.18) : nil, value: crowd.isFacingRight(slot))
            .keyframeAnimator(initialValue: 0.0, trigger: crowd.hopTick(slot)) { view, lift in
                view.offset(y: lift)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-size * 0.16, duration: 0.14)
                    CubicKeyframe(0, duration: 0.14)
                }
            }
            .overlay(alignment: .top) {
                if let bubble = crowd.bubble(slot) {
                    CrowdBubble(bubble: bubble, size: size)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
            .animation(crowd.motionAllowed ? .spring(response: 0.3, dampingFraction: 0.7) : nil,
                       value: crowd.bubble(slot))
    }
}

extension View {
    func crowdMember(_ crowd: PetCrowd, slot: Int, size: CGFloat) -> some View {
        modifier(CrowdMember(crowd: crowd, slot: slot, size: size))
    }
}

/// A small emoji speech bubble in the pet speech bubble's style, drawn inside the sprite's box so it never
/// grows the floating panel. Shared by Home and the floating pet.
@MainActor
struct CrowdBubble: View {
    let bubble: PetCrowd.Bubble
    let size: CGFloat

    static func emojiSize(for size: CGFloat) -> CGFloat { min(24, max(9, (size * 0.16).rounded())) }

    /// The note emoji is a black glyph, unreadable on the dark bubble, so it is drawn as a text-colored symbol.
    @ViewBuilder private var glyph: some View {
        if bubble == .note {
            Image(systemName: "music.note").foregroundStyle(.primary)
        } else {
            Text(bubble.rawValue)
        }
    }

    var body: some View {
        glyph
            .font(.system(size: Self.emojiSize(for: size)))
            .padding(.horizontal, 3).padding(.vertical, 1)
            .speechBubbleSurface(.mini)
            .allowsHitTesting(false)
    }
}

/// The pet tile inside the Home header and the floating pet: one friend, shrunk to `size`.
@MainActor
struct FriendSprite: View {
    let friend: FriendSubject
    let size: CGFloat
    var animated = true
    var minFrameDelay: TimeInterval = 0
    var spriteStore: SpriteStore = .shared
    var megaEvent: MegaEvolveEvent?
    var reportsVisibleTop = false

    var body: some View {
        MegaEvolveStage(megaSpriteID: friend.megaSpriteID, size: size, event: megaEvent, animated: animated) { mega in
            SpriteView(speciesID: mega ?? friend.speciesID, size: size, animated: animated, shiny: friend.isShiny,
                       minFrameDelay: minFrameDelay, spriteStore: spriteStore, form: mega == nil ? friend.form : nil,
                       female: mega == nil && friend.isFemale, reportsVisibleTop: reportsVisibleTop)
        }
        .frame(width: size, height: size)
    }
}

/// Home: one wide tile with the raised Pokémon and its friends standing on a shared floor line,
/// an add slot while a slot is free, and the picker behind it.
@MainActor
struct HomePetRow<Main: View>: View {
    let store: CompanionStore
    let crowd: PetCrowd
    var spriteStore: SpriteStore = .shared
    var cryPlayer: CryPlayer = .shared
    @ViewBuilder let main: Main
    @State private var picking = false
    @State private var hoveredSlot: Int?
    @State private var hoveringAdd = false

    static var mainSize: CGFloat { 58 }
    static var friendSize: CGFloat { 32 }
    static var tileWidth: CGFloat { mainSize + 2 * friendSize - 2 * slotOverlap + 2 * tileInset }
    static var tileHeight: CGFloat { 72 }
    static var tileInset: CGFloat { 4 }
    /// A friend's box tucks this far behind the raised Pokémon's box (30% of the friend's box).
    static var slotOverlap: CGFloat { (friendSize * 0.3).rounded() }
    static var floorInset: CGFloat { 7 }
    /// Space between the tile and the text column.
    static var headerGap: CGFloat { 10 }

    enum Slot: Equatable { case friend(Int), add }

    /// What stands beside the tile: [friend, active, friend]. The first friend goes on the left, the second
    /// on the right, and the add slot takes the place the next friend would fill.
    struct Arrangement: Equatable {
        var leading: Slot?
        var trailing: Slot?
    }

    static func arrangement(friendCount: Int, canAdd: Bool) -> Arrangement {
        switch friendCount {
        case 0: Arrangement(leading: canAdd ? .add : nil)
        case 1: Arrangement(leading: .friend(0), trailing: canAdd ? .add : nil)
        default: Arrangement(leading: .friend(0), trailing: .friend(1))
        }
    }

    var body: some View {
        let l = store.l
        let friends = store.friendSubjects
        let canAdd = friends.count < CompanionState.maxFriends && !store.friendCandidates.isEmpty
        let layout = Self.arrangement(friendCount: friends.count, canAdd: canAdd)
        HStack(alignment: .bottom, spacing: -Self.slotOverlap) {
            slotView(layout.leading, friends: friends, outer: .topLeading, l: l)
            main.zIndex(1)
            slotView(layout.trailing, friends: friends, outer: .topTrailing, l: l)
        }
        .padding(.horizontal, Self.tileInset)
        .padding(.bottom, Self.floorInset)
        .frame(width: Self.tileWidth, height: Self.tileHeight, alignment: .bottom)
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).fill(Color.secondary.opacity(0.06))
                Capsule().fill(Color.secondary.opacity(0.22)).frame(height: 1)
                    .padding(.horizontal, 10).padding(.bottom, Self.floorInset + 2)
            }
        }
    }

    @ViewBuilder
    private func slotView(_ slot: Slot?, friends: [FriendSubject], outer: Alignment, l: L) -> some View {
        switch slot {
        case .friend(let index):
            if friends.indices.contains(index) { friendSlot(friends[index], slot: index + 1, outer: outer, l: l) }
        case .add:
            addSlot(l: l)
        case nil:
            Color.clear.frame(width: Self.friendSize, height: Self.friendSize)
        }
    }

    private func addSlot(l: L) -> some View {
        Button { picking = true } label: {
            FriendAddDisc(hovering: hoveringAdd)
                .frame(width: Self.friendSize - 6, height: Self.friendSize - 6)
                .frame(width: Self.friendSize, height: Self.friendSize, alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringAdd = $0 }
        .help(l.friendAdd)
        .accessibilityLabel(l.friendAdd)
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            FriendPicker(store: store, spriteStore: spriteStore) { picking = false }
        }
    }

    private func friendSlot(_ friend: FriendSubject, slot: Int, outer: Alignment, l: L) -> some View {
        Button {
            cryPlayer.play(speciesID: friend.speciesID, form: friend.form)
            crowd.clicked(slot: slot)
        } label: {
            FriendSprite(friend: friend, size: Self.friendSize, spriteStore: spriteStore, megaEvent: store.megaEvolveEvent)
                .crowdMember(crowd, slot: slot, size: Self.friendSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l.friendLabel)
        .onHover { inside in
            if inside { hoveredSlot = slot } else if hoveredSlot == slot { hoveredSlot = nil }
        }
        .overlay(alignment: outer) {
            // Only while the pointer is over the friend, on its outer top corner away from the raised Pokémon.
            Button { store.removeFriend(entryID: friend.entryID) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.ptb(.label))
                    .foregroundStyle(.secondary, Color(nsColor: .windowBackgroundColor))
            }
            .buttonStyle(.plain)
            .help(l.friendRemove)
            .accessibilityLabel(l.friendRemove)
            .opacity(hoveredSlot == slot ? 1 : 0)
            .allowsHitTesting(hoveredSlot == slot)
            .offset(x: outer == .topLeading ? 1 : -1, y: -2)
        }
    }
}

/// The add-friend button face: an accent-tinted disc with a primary plus, a little stronger on hover.
@MainActor
struct FriendAddDisc: View {
    var hovering = false

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(hovering ? 0.34 : 0.22))
            .overlay { Image(systemName: "plus").font(.caption2.weight(.bold)).foregroundStyle(.primary) }
    }
}

/// Graduated Pokémon that can join as a friend. Tapping one adds it and closes the picker.
@MainActor
struct FriendPicker: View {
    let store: CompanionStore
    var spriteStore: SpriteStore = .shared
    let onDone: () -> Void

    private static let columns = Array(repeating: GridItem(.fixed(48), spacing: 6), count: 5)

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            Text(l.friendPickerTitle(CompanionState.maxFriends)).font(.caption.weight(.semibold))
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 6) {
                    ForEach(store.friendCandidates) { entry in
                        let friend = FriendSubject(entry)
                        Button {
                            store.addFriend(entryID: entry.id)
                            onDone()
                        } label: {
                            FriendSprite(friend: friend, size: 40, spriteStore: spriteStore)
                                .frame(width: 48, height: 48)
                                .ptbPanel()
                                .overlay(alignment: .topTrailing) {
                                    if friend.isShiny { Text("✨").font(.ptb(.small)) }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .reservesScrollerLane()
            }
            .frame(maxHeight: 210)
        }
        .padding(10)
        .frame(width: 5 * 48 + 4 * 6 + 24)
    }
}
