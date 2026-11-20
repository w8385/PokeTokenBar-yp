import Foundation

/// A change the player queued in Slack (`GET /v1/ops`, `bot/API.md` "Remote ops"). `payload` is the op's own JSON
/// object, read by the applier for its `kind`.
struct RemoteOp: Equatable, Sendable {
    let id: Int
    let kind: String
    let payload: Data

    /// The ops of a `GET /v1/ops` reply; nil when the reply is not one. A malformed op is skipped.
    static func decodeList(_ data: Data) -> [RemoteOp]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ops = object["ops"] as? [[String: Any]]
        else { return nil }
        return ops.compactMap { op in
            guard let id = op["id"] as? Int, id > 0, let kind = op["kind"] as? String else { return nil }
            let payload = (op["payload"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            return RemoteOp(id: id, kind: kind, payload: payload ?? Data("{}".utf8))
        }
    }
}

/// What this app did with an op: applied when `reason` is nil, otherwise cancelled with a short code that the bot
/// words for the player.
struct RemoteOpResult: Codable, Equatable, Sendable {
    let id: Int
    var reason: String? = nil
}

enum RemoteOpReason {
    static let unsupported = "unsupported"
}

/// Applies one op's payload. Returns nil when applied, or the reason code when the op cannot be applied.
typealias RemoteOpApplier = @MainActor @Sendable (CompanionStore, Data) -> String?

@MainActor
enum RemoteOpAppliers {
    static let all: [String: RemoteOpApplier] = [:]
}

/// One bag line in the upload; `key` is the inventory key.
struct RemoteBagLine: Encodable, Equatable, Sendable {
    let key: String
    let name: String
    let count: Int
}

/// One thing the shop sells now. `single` is bought once.
struct RemoteShopLine: Encodable, Equatable, Sendable {
    let key: String
    let name: String
    let price: Int
    let category: String
    let single: Bool
}

/// What the bot needs to answer Slack commands while the app is away.
struct RemoteSnapshot: Equatable, Sendable {
    let wallet: Int
    let bag: [RemoteBagLine]
    let shop: [RemoteShopLine]
}

/// What the uploader needs from the store for remote ops; nil keeps the uploader from fetching them.
struct RemoteOpsSync: Sendable {
    /// Applies the ops above `lastID` in id order, records each result and saves.
    let apply: @MainActor @Sendable ([RemoteOp]) -> Void
    /// The highest op id this app has applied or cancelled.
    let lastID: @MainActor @Sendable () -> Int
    /// Results the bot has not acknowledged, oldest first.
    let results: @MainActor @Sendable () -> [RemoteOpResult]
    let acknowledged: @MainActor @Sendable ([Int]) -> Void
    let snapshot: @MainActor @Sendable () -> RemoteSnapshot
}

extension RemoteOpsSync {
    init(store: CompanionStore) {
        self.init(apply: { [weak store] ops in store?.applyRemoteOps(ops) },
                  lastID: { [weak store] in store?.state.remoteOpsLastID ?? 0 },
                  results: { [weak store] in store?.state.remoteOpResults ?? [] },
                  acknowledged: { [weak store] ids in store?.acknowledgeRemoteOps(ids) },
                  snapshot: { [weak store] in store?.remoteSnapshot ?? RemoteSnapshot(wallet: 0, bag: [], shop: []) })
    }
}
