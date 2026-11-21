import SwiftUI

/// The sections and action buttons of a Box page. Each one reports its frame and whether it is enabled, so tests
/// read the page's order and controls from SwiftUI's layout.
enum BoxDetailMark: String, Hashable, CaseIterable, Sendable {
    case header, quickActions, heldItem, moveTraining, activeMoves, expShare, individual, evolution, exchange
    case battleSlots, raise, resumeLine, resumeStored, representative, friendAdd, friendRemove, dexLink, mint
    case trade, miracle, linkingCord
}

struct BoxDetailMarkValue {
    let bounds: Anchor<CGRect>
    let enabled: Bool
}

struct BoxDetailMarks: PreferenceKey {
    static var defaultValue: [BoxDetailMark: BoxDetailMarkValue] { [:] }

    static func reduce(value: inout [BoxDetailMark: BoxDetailMarkValue],
                       nextValue: () -> [BoxDetailMark: BoxDetailMarkValue]) {
        value.merge(nextValue()) { _, next in next }
    }
}

@MainActor
private struct BoxDetailMarker: ViewModifier {
    let mark: BoxDetailMark
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.anchorPreference(key: BoxDetailMarks.self, value: .bounds) {
            [mark: BoxDetailMarkValue(bounds: $0, enabled: isEnabled)]
        }
    }
}

extension View {
    func boxDetailMark(_ mark: BoxDetailMark) -> some View { modifier(BoxDetailMarker(mark: mark)) }
}
