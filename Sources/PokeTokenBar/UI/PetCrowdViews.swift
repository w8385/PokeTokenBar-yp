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

    var body: some View {
        SpriteView(speciesID: friend.spriteSpeciesID, size: size, animated: animated, shiny: friend.isShiny,
                   minFrameDelay: minFrameDelay, spriteStore: spriteStore, form: friend.spriteForm,
                   female: friend.spriteIsFemale)
            .frame(width: size, height: size)
    }
}

/// Home: the raised Pokémon's tile with friend slots standing beside it on the same ground line,
/// an add slot while a slot is free, and the picker behind it.
@MainActor
struct HomePetRow<Main: View>: View {
    let store: CompanionStore
    let crowd: PetCrowd
    var spriteStore: SpriteStore = .shared
    var cryPlayer: CryPlayer = .shared
    @ViewBuilder let main: Main
    @State private var picking = false

    static var slotSize: CGFloat { 24 }
    static var gap: CGFloat { 4 }

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
        HStack(alignment: .bottom, spacing: Self.gap) {
            slotView(layout.leading, friends: friends, outer: .topLeading, l: l)
            main
            slotView(layout.trailing, friends: friends, outer: .topTrailing, l: l)
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
            EmptyView()
        }
    }

    private func addSlot(l: L) -> some View {
        Button { picking = true } label: {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .foregroundStyle(.tertiary)
                .overlay { Image(systemName: "plus").font(.caption).foregroundStyle(.secondary) }
                .frame(width: Self.slotSize, height: Self.slotSize)
        }
        .buttonStyle(.plain)
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
            FriendSprite(friend: friend, size: Self.slotSize, spriteStore: spriteStore)
                .crowdMember(crowd, slot: slot, size: Self.slotSize)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l.friendLabel)
        .overlay(alignment: outer) {
            // On the outer corner, so the remove button never lands on the raised Pokémon's tile.
            Button { store.removeFriend(entryID: friend.entryID) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary, Color(nsColor: .windowBackgroundColor))
            }
            .buttonStyle(.plain)
            .help(l.friendRemove)
            .accessibilityLabel(l.friendRemove)
            .offset(x: outer == .topLeading ? -5 : 5, y: -5)
        }
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
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    if friend.isShiny { Text("✨").font(.system(size: 10)) }
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
