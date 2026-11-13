import SwiftUI

/// Hop, turn and bubble for one Pokémon of a `PetCrowd`. The hop is a one-shot keyframe per trigger change,
/// never a loop; the crowd only changes its state while motion is allowed.
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

/// A small emoji bubble drawn inside the sprite's box, so it never grows the floating panel.
struct CrowdBubble: View {
    let bubble: PetCrowd.Bubble
    let size: CGFloat

    var body: some View {
        Text(bubble.rawValue)
            .font(.system(size: max(10, size * 0.26)))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5))
            .allowsHitTesting(false)
    }
}

/// The pet tile inside the Home header and the floating pet: one friend, shrunk to `size`.
struct FriendSprite: View {
    let friend: FriendSubject
    let size: CGFloat
    var animated = true
    var minFrameDelay: TimeInterval = 0
    var spriteStore: SpriteStore = .shared

    var body: some View {
        SpriteView(speciesID: friend.speciesID, size: size, animated: animated, shiny: friend.isShiny,
                   minFrameDelay: minFrameDelay, spriteStore: spriteStore, form: friend.form, female: friend.isFemale)
            .frame(width: size, height: size)
    }
}

/// Home: friend slots under the sprite, an add slot while a slot is free, and the picker behind it.
@MainActor
struct FriendSlotsRow: View {
    let store: CompanionStore
    let crowd: PetCrowd
    var spriteStore: SpriteStore = .shared
    var cryPlayer: CryPlayer = .shared
    @State private var picking = false

    static let slotSize: CGFloat = 36

    var body: some View {
        let l = store.l
        let friends = store.friendSubjects
        HStack(spacing: 4) {
            ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                friendSlot(friend, slot: index + 1, l: l)
            }
            if friends.count < CompanionState.maxFriends, !store.friendCandidates.isEmpty {
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
            }
            .frame(maxHeight: 210)
        }
        .padding(10)
        .frame(width: 5 * 48 + 4 * 6 + 24)
    }
}
