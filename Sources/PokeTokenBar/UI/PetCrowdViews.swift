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

/// A rounded box with a tail at the bottom center, pointing at the Pokémon below it.
struct MiniBubbleShape: Shape {
    static let tailHeight: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.tailHeight)
        var path = Path(roundedRect: body, cornerRadius: min(6, body.height / 2), style: .continuous)
        path.move(to: CGPoint(x: rect.midX - 3, y: body.maxY - 0.5))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + 3, y: body.maxY - 0.5))
        path.closeSubpath()
        return path
    }
}

/// A small emoji speech bubble in the pet bubbles' colors, drawn inside the sprite's box so it never grows
/// the floating panel. Shared by Home and the floating pet.
@MainActor
struct CrowdBubble: View {
    let bubble: PetCrowd.Bubble
    let size: CGFloat

    static func emojiSize(for size: CGFloat) -> CGFloat { min(24, max(9, (size * 0.16).rounded())) }

    var body: some View {
        Text(bubble.rawValue)
            .font(.system(size: Self.emojiSize(for: size)))
            .padding(.horizontal, 3).padding(.top, 1).padding(.bottom, 1 + MiniBubbleShape.tailHeight)
            .background(MiniBubbleShape().fill(Color.white))
            .overlay(MiniBubbleShape().stroke(Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255), lineWidth: 1))
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

/// Home: friend slots on the sprite tile's bottom edge, an add slot while a slot is free, and the picker behind it.
@MainActor
struct FriendSlotsRow: View {
    let store: CompanionStore
    let crowd: PetCrowd
    var spriteStore: SpriteStore = .shared
    var cryPlayer: CryPlayer = .shared
    @State private var picking = false

    static let slotSize: CGFloat = 28

    enum Slot: Equatable { case friend(Int), add }

    /// What stands under the sprite tile. Friends sit at its bottom corners, so the raised Pokémon is the
    /// middle of [friend, active, friend]; the add slot takes the corner a missing friend would fill.
    /// With no friend yet the add slot is centered.
    struct Arrangement: Equatable {
        var leading: Slot?
        var center: Slot?
        var trailing: Slot?
    }

    static func arrangement(friendCount: Int, canAdd: Bool) -> Arrangement {
        guard friendCount > 0 else { return Arrangement(center: canAdd ? .add : nil) }
        return Arrangement(leading: .friend(0),
                           trailing: friendCount >= 2 ? .friend(1) : (canAdd ? .add : nil))
    }

    var body: some View {
        let l = store.l
        let friends = store.friendSubjects
        let canAdd = friends.count < CompanionState.maxFriends && !store.friendCandidates.isEmpty
        let layout = Self.arrangement(friendCount: friends.count, canAdd: canAdd)
        HStack(spacing: 0) {
            slotView(layout.leading, friends: friends, l: l)
            Spacer(minLength: 0)
            slotView(layout.center, friends: friends, l: l)
            if layout.center != nil { Spacer(minLength: 0) }
            slotView(layout.trailing, friends: friends, l: l)
        }
    }

    @ViewBuilder
    private func slotView(_ slot: Slot?, friends: [FriendSubject], l: L) -> some View {
        switch slot {
        case .friend(let index):
            if friends.indices.contains(index) { friendSlot(friends[index], slot: index + 1, l: l) }
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

    private func friendSlot(_ friend: FriendSubject, slot: Int, l: L) -> some View {
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
        .overlay(alignment: .topTrailing) {
            Button { store.removeFriend(entryID: friend.entryID) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary, Color(nsColor: .windowBackgroundColor))
            }
            .buttonStyle(.plain)
            .help(l.friendRemove)
            .accessibilityLabel(l.friendRemove)
            .offset(x: 5, y: -5)
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
