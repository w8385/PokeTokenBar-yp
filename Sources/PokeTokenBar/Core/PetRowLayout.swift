import CoreGraphics

/// Where the friends stand around the main pet on the floating panel. Pure geometry, so the saved home
/// (the main pet's origin) survives friends coming and going.
struct PetRowLayout: Equatable {
    static let friendScale: CGFloat = 0.7
    static let friendGap: CGFloat = 4

    var friendCount = 0
    /// Friends stand to the left of the main pet unless that would leave the screen.
    var friendsOnLeft = true

    static let single = PetRowLayout()

    static func friendSize(petSize: CGFloat) -> CGFloat { (petSize * friendScale).rounded() }

    func friendsWidth(petSize: CGFloat) -> CGFloat {
        CGFloat(friendCount) * (Self.friendSize(petSize: petSize) + Self.friendGap)
    }

    /// Room the bubble needs on each side of the main pet.
    private func bubbleSide(petSize: CGFloat, bubbleWidth: CGFloat) -> CGFloat {
        max(0, (bubbleWidth - petSize) / 2)
    }

    /// Space left and right of the main pet. Friends fill the margin next to it, so a bubble does not move them.
    func margins(petSize: CGFloat, bubbleWidth: CGFloat?) -> (left: CGFloat, right: CGFloat) {
        let side = bubbleWidth.map { bubbleSide(petSize: petSize, bubbleWidth: $0) } ?? 0
        let friends = friendsWidth(petSize: petSize)
        return friendsOnLeft ? (max(friends, side), side) : (side, max(friends, side))
    }

    func panelWidth(petSize: CGFloat, bubbleWidth: CGFloat?) -> CGFloat {
        let m = margins(petSize: petSize, bubbleWidth: bubbleWidth)
        return m.left + petSize + m.right
    }

    /// Distance from the panel's left edge to the main pet.
    func mainXOffset(petSize: CGFloat, bubbleWidth: CGFloat?) -> CGFloat {
        margins(petSize: petSize, bubbleWidth: bubbleWidth).left
    }

    /// Slots left to right: the main pet is slot 0, friend `i` is slot `i + 1`. The nearest friend stands next to it.
    var slotOrder: [Int] {
        let friends = friendCount > 0 ? Array(1...friendCount) : []
        return friendsOnLeft ? Array(friends.reversed()) + [0] : [0] + friends
    }

    enum Hit: Equatable { case main, friend(Int) }

    /// Which pet a click at `x` (panel coordinates) lands on. Clicks on the margin around the main pet count as the main pet.
    func hit(x: CGFloat, petSize: CGFloat, bubbleWidth: CGFloat?) -> Hit {
        guard friendCount > 0 else { return .main }
        let mainX = mainXOffset(petSize: petSize, bubbleWidth: bubbleWidth)
        let slot = Self.friendSize(petSize: petSize) + Self.friendGap
        if friendsOnLeft {
            let distance = mainX - x
            guard distance > 0 else { return .main }
            let index = Int(distance / slot)
            return index < friendCount ? .friend(index) : .main
        }
        let distance = x - (mainX + petSize)
        guard distance > 0 else { return .main }
        let index = Int(distance / slot)
        return index < friendCount ? .friend(index) : .main
    }
}
