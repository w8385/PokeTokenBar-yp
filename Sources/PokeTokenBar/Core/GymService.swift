import Foundation
import Observation

/// A run in progress (the Elite Four or a hideout): which battle is next and the team's HP and status going
/// into it. The bot keeps nothing between battles, so this is the run. It lives until the app quits.
struct GymRunProgress: Equatable, Sendable {
    let team: [String]
    /// 0-based index into the run's battles.
    let nextIndex: Int
    let carry: [GymCarry?]
}

/// What outlives a screen: the catalog already fetched and the runs under way.
@MainActor
@Observable
final class GymSession {
    static let shared = GymSession()

    private(set) var catalogs: [String: GymCatalog] = [:]
    private(set) var runs: [String: GymRunProgress] = [:]
    /// The region the section shows and whether it shows the badge case; kept so a tab switch does not reset them.
    var regionID = "kanto"
    var showsBadgeCase = false

    func setCatalog(_ catalog: GymCatalog?, for server: String) { catalogs[server] = catalog }
    func setRun(_ run: GymRunProgress?, for id: String) { runs[id] = run }
}

/// One fought battle as the screen shows it.
struct GymFightRecord: Equatable, Sendable {
    let opponent: GymOpponent
    let outcome: GymBattleOutcome
    let reward: GymReward?
}

/// Talks to the bot's gym endpoints and keeps a run's carry-over. Rewards are handed to `applyReward` with the
/// trainer and region; the store behind it owns the save.
@MainActor
@Observable
final class GymService {
    enum Unavailable: Equatable, Sendable {
        case notLinked, rejected, unreachable, botTooOld
    }

    enum Failure: Equatable, Sendable {
        case rateLimited(retryAfter: Double)
        case refused(String)
        case unreachable
        case botTooOld
        case failed
    }

    struct Link: Equatable, Sendable {
        let server: String
        let token: String
    }

    typealias Exchange = @Sendable (URLRequest) async throws -> (Data, Int)

    private(set) var isLoading = false
    private(set) var unavailable: Unavailable?
    /// The opponent being fought now.
    private(set) var inFlight: String?
    private(set) var failure: Failure?
    private(set) var last: GymFightRecord?

    @ObservationIgnored private let link: @MainActor () -> Link?
    @ObservationIgnored private let exchange: Exchange
    @ObservationIgnored private let badges: @MainActor () -> GymBadges
    @ObservationIgnored private let ownedTMs: @MainActor () -> Set<Int>
    @ObservationIgnored private let applyReward: @MainActor (GymReward, GymOpponent, GymRegion) -> Void
    @ObservationIgnored let session: GymSession

    init(link: @escaping @MainActor () -> Link?,
         exchange: @escaping Exchange = PartyUploader.urlSessionFetch,
         badges: @escaping @MainActor () -> GymBadges,
         ownedTMs: @escaping @MainActor () -> Set<Int>,
         applyReward: @escaping @MainActor (GymReward, GymOpponent, GymRegion) -> Void,
         session: GymSession = .shared) {
        self.link = link
        self.exchange = exchange
        self.badges = badges
        self.ownedTMs = ownedTMs
        self.applyReward = applyReward
        self.session = session
    }

    /// The catalog of the linked server, once fetched.
    var catalog: GymCatalog? { link().flatMap { session.catalogs[$0.server] } }

    // MARK: Catalog

    func loadCatalog() async {
        guard !isLoading else { return }
        guard let link = link(), PartyUploader.baseURL(link.server) != nil else {
            unavailable = .notLinked
            return
        }
        if session.catalogs[link.server] != nil {
            unavailable = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        guard let request = Self.catalogRequest(link),
              let (data, status) = try? await exchange(request) else {
            unavailable = .unreachable
            return
        }
        switch status {
        case 200:
            if let catalog = try? GymCatalog.decode(data), !catalog.regions.isEmpty {
                session.setCatalog(catalog, for: link.server)
                unavailable = nil
            } else {
                unavailable = .botTooOld
            }
        case 401: unavailable = .rejected
        case 404: unavailable = .botTooOld
        default: unavailable = .unreachable
        }
    }

    // MARK: Fights

    /// Fights one gym, which stands alone.
    func fightGym(_ gym: GymOpponent, region: GymRegion, team: GymTeam.Team) async {
        await fight(gym, region: region, team: team, carried: nil)
    }

    /// Fights the next battle of a run: the first when no run is under way or the team changed since, else the
    /// one after the last win, carrying the team's HP and status over.
    func fightRun(_ run: String, battles: [GymOpponent], region: GymRegion, team: GymTeam.Team) async {
        let state = session.runs[run].flatMap { $0.team == team.ids && battles.indices.contains($0.nextIndex) ? $0 : nil }
        if state == nil { session.setRun(nil, for: run) }
        await fight(battles[state?.nextIndex ?? 0], region: region, team: team, carried: state?.carry)
    }

    /// Where a run stands for this team: the 1-based step it fights next, `1` when it would start over.
    func nextStep(of run: String, battles: [GymOpponent], team: GymTeam.Team) -> Int {
        guard let state = session.runs[run], state.team == team.ids, battles.indices.contains(state.nextIndex) else { return 1 }
        return state.nextIndex + 1
    }

    func dismissResult() {
        last = nil
        failure = nil
    }

    private func fight(_ opponent: GymOpponent, region: GymRegion, team: GymTeam.Team, carried: [GymCarry?]?) async {
        guard inFlight == nil, let link = link(),
              let request = Self.battleRequest(link, GymBattleRequest(gymId: opponent.id, team: team.members, carried: carried))
        else { return }
        inFlight = opponent.id
        failure = nil
        defer { inFlight = nil }
        guard let (data, status) = try? await exchange(request) else {
            failure = .unreachable
            return
        }
        switch status {
        case 200:
            guard let outcome = try? GymBattleOutcome.decode(data), outcome.gymId == opponent.id else {
                failure = .failed
                return
            }
            finish(outcome, opponent: opponent, region: region, team: team)
        case 400: failure = .refused(Self.message(in: data) ?? "")
        case 401: unavailable = .rejected; failure = .failed
        case 404: failure = .botTooOld
        case 429: failure = .rateLimited(retryAfter: Self.retryAfter(in: data))
        default: failure = .failed
        }
    }

    private func finish(_ outcome: GymBattleOutcome, opponent: GymOpponent, region: GymRegion, team: GymTeam.Team) {
        if let run = opponent.run {
            if outcome.won, let next = outcome.run?.next, let carry = outcome.carry, carry.count == team.members.count,
               let index = Self.index(of: next, in: region, run: run.id) {
                session.setRun(GymRunProgress(team: team.ids, nextIndex: index, carry: carry), for: run.id)
            } else {
                session.setRun(nil, for: run.id)
            }
        }
        var reward: GymReward?
        if outcome.won {
            reward = GymRewards.reward(for: opponent, region: region.id, badges: badges(), ownedTMs: ownedTMs())
            if let reward { applyReward(reward, opponent, region) }
        }
        last = GymFightRecord(opponent: opponent, outcome: outcome, reward: reward)
    }

    private static func index(of battleID: String, in region: GymRegion, run: String) -> Int? {
        let battles = run == region.elite.run ? region.elite.battles : region.hideout.battles
        return battles.firstIndex { $0.id == battleID }
    }

    // MARK: Requests

    nonisolated static func catalogRequest(_ link: Link) -> URLRequest? {
        guard let base = PartyUploader.baseURL(link.server) else { return nil }
        var request = URLRequest(url: base.appending(path: "v1/gyms"), timeoutInterval: 10)
        request.setValue("Bearer \(link.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// The first battle against a trainer makes the bot fetch its foes' moves, so the timeout is long.
    nonisolated static func battleRequest(_ link: Link, _ body: GymBattleRequest) -> URLRequest? {
        guard let base = PartyUploader.baseURL(link.server), let data = try? body.encoded() else { return nil }
        var request = URLRequest(url: base.appending(path: "v1/gym/battle"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(link.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        return request
    }

    private nonisolated static func message(in data: Data) -> String? {
        struct Body: Decodable { let error: String? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error
    }

    private nonisolated static func retryAfter(in data: Data) -> Double {
        struct Body: Decodable { let retryAfter: Double? }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(Body.self, from: data))?.retryAfter ?? 3
    }
}
