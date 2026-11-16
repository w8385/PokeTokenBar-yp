import Foundation

/// What one region's trainers have been beaten for, saved with the companion state.
struct GymRegionBadges: Codable, Equatable, Sendable {
    /// Gym indexes 1...8 beaten at least once.
    var gyms: Set<Int> = []
    /// The Elite Four run was cleared and the champion beaten.
    var hallOfFame = false
    /// The villain hideout run was cleared and its boss beaten.
    var orgBeaten = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gyms = (try? c.decode(Set<Int>.self, forKey: .gyms)) ?? []
        hallOfFame = (try? c.decode(Bool.self, forKey: .hallOfFame)) ?? false
        orgBeaten = (try? c.decode(Bool.self, forKey: .orgBeaten)) ?? false
    }

    private enum CodingKeys: String, CodingKey { case gyms, hallOfFame, orgBeaten }
}

/// Every region's badges, keyed by region id (`kanto`…`paldea`). A save from before gyms has none.
struct GymBadges: Codable, Equatable, Sendable {
    static let gymsPerRegion = 8

    var regions: [String: GymRegionBadges] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regions = (try? c.decode([String: GymRegionBadges].self, forKey: .regions)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case regions }

    func region(_ id: String) -> GymRegionBadges { regions[id] ?? GymRegionBadges() }

    func badgeCount(_ region: String) -> Int { self.region(region).gyms.count }

    func hasGymBadge(_ region: String, index: Int) -> Bool { self.region(region).gyms.contains(index) }

    /// The Elite Four run opens with `needed` of the region's gym badges.
    func eliteOpen(_ region: GymRegion) -> Bool { badgeCount(region.id) >= region.elite.badgesNeeded }

    var totalBadges: Int { regions.values.reduce(0) { $0 + $1.gyms.count } }

    mutating func update(_ region: String, _ change: (inout GymRegionBadges) -> Void) {
        var badges = self.region(region)
        change(&badges)
        regions[region] = badges
    }
}
