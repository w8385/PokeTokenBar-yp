import Foundation
import Observation

/// The player's miracle trade offer as the Box detail shows it: whether the bot offers the feature, the open
/// offer, and the last post or take-down result.
@MainActor @Observable
final class MiracleTradeModel {
    enum Availability: Equatable { case unknown, unavailable, available }
    enum Phase: Equatable { case idle, sending, refused(String), failed }

    private(set) var availability: Availability
    private(set) var offer: MiracleOffer?
    private(set) var phase = Phase.idle
    private let uploader: PartyUploader

    init(uploader: PartyUploader, availability: Availability = .unknown, offer: MiracleOffer? = nil) {
        self.uploader = uploader
        self.availability = availability
        self.offer = offer
    }

    /// The post button: the feature is on, nothing of this player's is up yet, and the Pokémon is tradable.
    static func showsPostButton(availability: Availability, offer: MiracleOffer?, refusal: TradeRefusal?) -> Bool {
        availability == .available && offer == nil && refusal == nil
    }

    func isOffered(_ individualID: String) -> Bool { offer?.giveID == individualID }

    /// An unreachable bot leaves the state as it was.
    func load() async {
        switch await uploader.miracleStatus() {
        case .unavailable: availability = .unavailable
        case .nothingListed: availability = .available; offer = nil
        case .open(let open): availability = .available; offer = open
        case nil: break
        }
    }

    func post(_ individualID: String) async {
        guard phase != .sending else { return }
        phase = .sending
        switch await uploader.postMiracle(give: individualID) {
        case .posted(let posted): offer = posted; phase = .idle
        case .refused(let message): phase = .refused(message)
        case .unavailable: availability = .unavailable; phase = .idle
        case .failed: phase = .failed
        }
    }

    func cancel() async {
        guard phase != .sending else { return }
        phase = .sending
        if await uploader.cancelMiracle() {
            offer = nil
            phase = .idle
        } else {
            phase = .failed
        }
    }
}
