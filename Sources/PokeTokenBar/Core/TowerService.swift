import Foundation
import Observation

/// Talks to the bot's tower endpoints. The bot owns every run; each reply goes to `apply` with what the battle paid,
/// and the store behind it mirrors the run into the save and adds the BP.
@MainActor
@Observable
final class TowerService {
    typealias Apply = @MainActor (TowerRun, TowerGain?) -> Void

    private(set) var isLoading = false
    private(set) var unavailable: GymService.Unavailable?
    private(set) var busy = false
    private(set) var failure: GymService.Failure?
    private(set) var runs: [TowerMode: TowerRun] = [:]
    private(set) var ranking: [TowerMode: [TowerRank]] = [:]
    private(set) var last: TowerOutcome?
    var mode: TowerMode = .entry

    @ObservationIgnored private let link: @MainActor () -> GymService.Link?
    @ObservationIgnored private let exchange: GymService.Exchange
    @ObservationIgnored private let apply: Apply
    @ObservationIgnored private let boast: @MainActor () -> Bool

    init(link: @escaping @MainActor () -> GymService.Link?,
         exchange: @escaping GymService.Exchange = PartyUploader.urlSessionFetch,
         boast: @escaping @MainActor () -> Bool = { true },
         apply: @escaping Apply) {
        self.link = link
        self.exchange = exchange
        self.boast = boast
        self.apply = apply
    }

    func load() async {
        guard !isLoading else { return }
        guard let link = link(), PartyUploader.baseURL(link.server) != nil else {
            unavailable = .notLinked
            return
        }
        isLoading = true
        defer { isLoading = false }
        guard let request = Self.request(link, path: "v1/tower/record", body: nil),
              let (data, status) = try? await exchange(request) else {
            unavailable = .unreachable
            return
        }
        switch status {
        case 200:
            guard let record = try? TowerRecord.decode(data) else {
                unavailable = .botTooOld
                return
            }
            unavailable = nil
            for mode in TowerMode.allCases {
                if let run = record.modes[mode.rawValue] { take(run, gain: nil) }
                ranking[mode] = record.ranking[mode.rawValue] ?? []
            }
        case 401: unavailable = .rejected
        case 404: unavailable = .botTooOld
        default: unavailable = .unreachable
        }
    }

    /// Fights the run's next battle. `team` is the entry in `entry` mode; the bot keeps the rentals.
    func fight(_ mode: TowerMode, team: [PartyMember]?) async {
        let body = try? TowerBattleRequest(mode: mode.rawValue, team: mode == .entry ? team : nil, boast: boast()).encoded()
        guard let data = await send("v1/tower/battle", body: body) else { return }
        guard let outcome = try? TowerOutcome.decode(data) else {
            failure = .failed
            return
        }
        take(outcome.run, gain: outcome.gain)
        last = outcome
    }

    enum RentalChange: Equatable, Sendable {
        /// Three different indexes of the offer.
        case pick([Int])
        /// Team slot `give` takes the just-beaten trainer's member `take`.
        case swap(give: Int, take: Int)
    }

    /// The rental run after `change`; with none, a run without a team gets its offer of six.
    func rental(_ change: RentalChange? = nil) async {
        var body: [String: Any] = [:]
        switch change {
        case .pick(let indexes): body["pick"] = indexes
        case .swap(let give, let take): body["swap"] = ["give": give, "take": take]
        case nil: break
        }
        guard let data = await send("v1/tower/rental", body: try? JSONSerialization.data(withJSONObject: body)),
              let run = try? TowerRun.decode(data) else { return }
        take(run, gain: nil)
    }

    /// Ends the mode's run: the streak goes back to 0 and the entry can change again.
    func quit(_ mode: TowerMode) async {
        let body = try? JSONEncoder().encode(["mode": mode.rawValue])
        guard let data = await send("v1/tower/quit", body: body), let run = try? TowerRun.decode(data) else { return }
        take(run, gain: nil)
    }

    func dismissResult() {
        last = nil
        failure = nil
    }

    private func take(_ run: TowerRun, gain: TowerGain?) {
        guard let mode = TowerMode(rawValue: run.mode) else { return }
        runs[mode] = run
        apply(run, gain)
    }

    /// Posts `body` and returns the reply of a 200. Anything else sets `failure`; a 409 (the run moved on elsewhere)
    /// reloads the record so the screen shows where the bot stands.
    private func send(_ path: String, body: Data?) async -> Data? {
        guard !busy, let link = link(), let request = Self.request(link, path: path, body: body) else { return nil }
        busy = true
        failure = nil
        defer { busy = false }
        guard let (data, status) = try? await exchange(request) else {
            failure = .unreachable
            return nil
        }
        switch status {
        case 200: return data
        case 400, 409: failure = .refused(GymService.message(in: data) ?? "")
        case 401: unavailable = .rejected; failure = .failed
        case 404: failure = .botTooOld
        case 429: failure = .rateLimited(retryAfter: GymService.retryAfter(in: data))
        default: failure = .failed
        }
        if status == 409 {
            busy = false
            await load()
        }
        return nil
    }

    /// The first battle against a trainer makes the bot fetch its foes' moves, so the timeout is long.
    nonisolated static func request(_ link: GymService.Link, path: String, body: Data?) -> URLRequest? {
        guard let base = PartyUploader.baseURL(link.server) else { return nil }
        var request = URLRequest(url: base.appending(path: path), timeoutInterval: body == nil ? 10 : 20)
        request.setValue("Bearer \(link.token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }
}
