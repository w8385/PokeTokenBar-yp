import Foundation

/// The `buy` remote op: one shop purchase made in Slack (`bot/API.md` "The `buy` op"). It runs the shop's own
/// purchase on the current state, all of it or nothing.
enum RemoteBuy {
    static let kind = "buy"
    static let maxCount = 99

    enum Reason {
        static let notSold = "not_sold"
        static let priceChanged = "price_changed"
        static let noTokens = "no_tokens"
        static let invalid = "invalid"
    }

    struct Payload: Decodable, Equatable {
        let key: String
        let count: Int
        let price: Int
    }

    /// Nil when bought; otherwise the reason it was cancelled with nothing changed. The shop line must still be
    /// sold at the price the player saw.
    @MainActor
    static func apply(_ data: Data, store: CompanionStore) -> String? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), (1...maxCount).contains(payload.count)
        else { return Reason.invalid }
        guard let line = store.remoteShop.first(where: { $0.key == payload.key }) else { return Reason.notSold }
        guard line.price == payload.price else { return Reason.priceChanged }
        guard !line.single || payload.count == 1 else { return Reason.invalid }
        guard line.price * payload.count <= store.availableTokens else { return Reason.noTokens }
        return store.buyFromShop(payload.key, count: payload.count) ? nil : Reason.notSold
    }
}
