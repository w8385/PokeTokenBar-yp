import Foundation
import Observation

/// One trade offer in progress: the coworker list, the picked friend and the send result.
/// The Friends tab screen and the Box detail panel both drive this.
@MainActor @Observable
final class TradeOfferModel {
    enum Phase: Equatable { case idle, sending, sent(String), refused(String), failed }

    var give: String?
    var target: String?
    private(set) var coworkers: [TradeCoworker]?
    private(set) var loadFailed = false
    private(set) var phase = Phase.idle
    private let uploader: PartyUploader

    init(uploader: PartyUploader, give: String? = nil, target: String? = nil, coworkers: [TradeCoworker]? = nil) {
        self.uploader = uploader
        self.give = give
        self.target = target
        self.coworkers = coworkers
    }

    var canSend: Bool { give != nil && target != nil && phase != .sending }

    var targetName: String? { coworkers?.first { $0.id == target }?.name }

    func load() async {
        guard coworkers == nil else { return }
        coworkers = await uploader.coworkers()
        loadFailed = coworkers == nil
    }

    func pickGive(_ id: String) {
        give = id
        phase = .idle
    }

    func pickTarget(_ id: String) {
        target = id
        phase = .idle
    }

    func send() async {
        guard canSend, let give, let target, let name = targetName else { return }
        phase = .sending
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
