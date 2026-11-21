import Foundation

extension CompanionStore {
    // MARK: 세대(지역) 도감 완성 추적

    /// Owned species reduced to the (dex number, shiny) pairs the generation math needs.
    private var ownedDexForProgress: [(id: Int, isShiny: Bool)] {
        dexSpecies.map { (id: $0.id, isShiny: $0.isShiny) }
    }

    /// Per-region owned/total progress, in National Dex order. Drives the Pokédex generation chips.
    var dexCompletions: [DexCompletion] {
        DexProgress.regionCompletions(owned: ownedDexForProgress)
    }

    /// National progress for the Pokédex header.
    var nationalDexProgress: (owned: Int, shinyOwned: Int, total: Int) {
        DexProgress.nationalProgress(owned: ownedDexForProgress)
    }

    /// Every completion badge currently earned — derived, never persisted (ownership only grows).
    var earnedDexBadges: [DexBadge] {
        DexProgress.earnedBadges(owned: ownedDexForProgress,
                                 unownFormsCollected: state.collectedForms(speciesID: PokemonForm.unownSpeciesID).count)
    }

    /// Fire a one-time completion notification for every badge earned since the last check.
    /// Idempotent: a badge already in `notifiedDexCompletions` never re-fires. Does not persist on its
    /// own — `save()` calls it just before encoding, so the recorded keys are written in the same pass.
    /// Guarded on seeding so pre-feature completions are announced by `seedDexCompletionsIfNeeded`, not here.
    func checkDexCompletions() {
        guard state.dexCompletionsSeeded else { return }
        let earned = earnedDexBadges
        let rewarded = grantRegionRewards(earned: earned)
        let newly = DexProgress.newlyEarnedBadges(earned: earned,
                                                  alreadyNotified: state.notifiedDexCompletions)
        for badge in newly {
            if case .region(let region) = badge, rewarded.contains(region) {
                state.notifiedDexCompletions.insert(badge.notificationKey)
                continue   // the reward notification already announced it
            }
            let (title, body) = dexCompletionNotification(badge)
            notifyCompanionEvent(title, body)
            state.notifiedDexCompletions.insert(badge.notificationKey)
        }
    }

    func isDexRegionRewarded(_ region: PokedexRegion) -> Bool {
        state.rewardedDexRegions.contains(region.rawValue)
    }

    /// Pay the one-time reward for every completed region not rewarded yet and announce each with the
    /// completion notification plus the reward. The first region ever rewarded also brings the Shiny Charm
    /// if it is not owned. Mutates state only; `save()` persists it in the same pass.
    private func grantRegionRewards(earned: [DexBadge]) -> Set<PokedexRegion> {
        let regions = DexProgress.unrewardedRegions(earned: earned, rewarded: state.rewardedDexRegions)
        for region in regions {
            let isFirst = state.rewardedDexRegions.isEmpty
            state.rewardedDexRegions.insert(region.rawValue)
            let count = DexRegionReward.candyCount
            state.inventory[ItemKind.rareCandy.rawValue, default: 0] += count
            var items = "\(l.itemName(.rareCandy)) ×\(count)"
            if isFirst, itemCount(.shinyCharm) == 0 {
                state.inventory[ItemKind.shinyCharm.rawValue] = 1
                items += ", \(l.itemName(.shinyCharm))"
            }
            notifyCompanionEvent(l.notifDexRegionCompleteTitle(l.regionName(region)),
                                 l.notifDexRegionRewardBody(l.regionName(region), items: items))
        }
        return Set(regions)
    }

    /// On first run after this feature ships, record already-earned badges as announced *without*
    /// firing — a player who finished a region months ago should not get a notification burst.
    func seedDexCompletionsIfNeeded() {
        guard !state.dexCompletionsSeeded else { return }
        state.dexCompletionsSeeded = true
        let keys = earnedDexBadges.map(\.notificationKey)
        // A fresh or just-reset save owns nothing — don't rewrite the state file just to seed an empty
        // set (that would clobber the "corrupt original moved aside, not recreated" invariant). The
        // seeded flag then persists on the next natural save; re-seeding meanwhile is idempotent.
        guard !keys.isEmpty else { return }
        state.notifiedDexCompletions.formUnion(keys)
        save()
    }

    private func dexCompletionNotification(_ badge: DexBadge) -> (title: String, body: String) {
        switch badge {
        case .region(let r):
            return (l.notifDexRegionCompleteTitle(l.regionName(r)), l.notifDexRegionCompleteBody(l.regionName(r)))
        case .regionShiny(let r):
            return (l.notifDexRegionShinyCompleteTitle(l.regionName(r)), l.notifDexRegionShinyCompleteBody(l.regionName(r)))
        case .unown:
            return (l.notifDexUnownCompleteTitle, l.notifDexUnownCompleteBody)
        case .national:
            return (l.notifDexNationalCompleteTitle, l.notifDexNationalCompleteBody)
        case .nationalShiny:
            return (l.notifDexNationalShinyCompleteTitle, l.notifDexNationalShinyCompleteBody)
        }
    }

    func collectedDexSpecies(groupForms: Bool) -> [DexSpecies] {
        // 종별 누적을 한 번에 훑는다(뷰가 body 에서 1회 소비 — 메모이즈 없이 충분).
        var acc: [DexKey: DexAccumulator] = [:]
        for entry in state.dex {
            for id in entry.chainOrder {
                let key = DexKey(id, form: entry.form, groupForms: groupForms)
                var a = acc[key] ?? DexAccumulator(rarity: entry.rarity)
                if let n = entry.names?[id] { a.names = n }   // 이름 없는 구버전 항목이 덮어쓰지 않게
                if entry.isShiny { a.isShiny = true } else { a.hasNormal = true }
                acc[key] = a
            }
        }
        if let active = state.active {
            // 도달분만 — stageIndex 가 pathIDs 범위 안임은 두 입구가 보장한다:
            // MonState.init(from:) 의 clamp, 그리고 SaveTransfer 의 가져오기 정규화.
            for id in active.pathIDs.prefix(active.stageIndex + 1) {
                let key = DexKey(id, form: active.form, groupForms: groupForms)
                var a = acc[key] ?? DexAccumulator(rarity: active.rarity)
                if let n = currentLine?.names[id] { a.names = n }
                if active.displaysShiny { a.isShiny = true } else { a.hasNormal = true }   // 위장 중 숨김 규칙 재사용
                acc[key] = a
            }
        }
        return acc.sorted {
            ($0.key.speciesID, PokemonForm.sortOrder($0.key.form, speciesID: $0.key.speciesID))
                < ($1.key.speciesID, PokemonForm.sortOrder($1.key.form, speciesID: $1.key.speciesID))
        }.map { key, a in
            let name = a.names.flatMap { state.language.resolveName($0) } ?? "#\(key.speciesID)"
            return DexSpecies(
                id: key.speciesID,
                name: groupForms ? formDisplayName(name, speciesID: key.speciesID, form: key.form) : name,
                rarity: a.rarity,
                isShiny: a.isShiny,
                isRaising: key.speciesID == currentSpeciesID && (!groupForms || key.form == currentForm),
                form: key.form,
                names: a.names,
                hasNormal: a.hasNormal)
        }
    }

    /// Resolves the primary localized name of an individual final species for sorting and display.
    func dexEntryName(_ entry: DexEntry) -> String {
        let targetID = entry.finalID
        if let stored = entry.names?[targetID], let localized = state.language.resolveName(stored) {
            return localized
        }
        for id in entry.chainOrder.reversed() {
            if let stored = entry.names?[id], let localized = state.language.resolveName(stored) {
                return localized
            }
        }
        return "#\(targetID)"
    }

    /// The one search rule shared by the Pokédex grid and the Box, so the two screens cannot
    /// drift apart. A query matches a Pokédex number (`25` or `#25`) or part of any stored name
    /// in any language, ignoring case and diacritics ("flabebe" finds Flabébé).
    struct DexSearchMatcher: Sendable {
        private let query: String
        private let number: Int?

        /// `nil` for a blank query, which filters nothing out.
        init?(_ rawQuery: String) {
            let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            query = trimmed
            number = Int(trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed)
        }

        func matches(_ species: DexSpecies) -> Bool {
            matches(ids: [species.id], names: [species.name] + (species.names.map { Array($0.values) } ?? []))
        }

        /// An individual matches through any species of its chain, like its evolution line in the log row.
        func matches(_ entry: DexEntry) -> Bool {
            matches(ids: [entry.baseID, entry.finalID] + entry.chainOrder,
                    names: entry.names?.values.flatMap(\.values) ?? [])
        }

        private func matches(ids: [Int], names: [String]) -> Bool {
            if let number, ids.contains(number) { return true }
            // Partial numbers keep working: "25" also finds #125, "#25" finds #25 and #250.
            if ids.contains(where: { "#\($0)".contains(query) }) { return true }
            return names.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Filters and sorts DexSpecies for the Pokédex grid.
    func filteredDexSpecies(
        query: String = "",
        rarity: Rarity? = nil,
        shinyOnly: Bool = false,
        region: PokedexRegion? = nil,
        includeUnowned: Bool = false,
        sort: DexSortOption = .numberAsc
    ) -> [DexSpecies] {
        let matcher = DexSearchMatcher(query)
        var result = dexSpecies
        if matcher != nil || includeUnowned { result += unownedDexSpecies }
        if let rarity {
            result = result.filter { $0.rarity == rarity }
        }
        if let region {
            result = result.filter { region.dexRange.contains($0.id) }
        }
        if shinyOnly {
            result = result.filter { $0.isShiny }
        }
        if let matcher {
            result = result.filter { matcher.matches($0) }
        }
        return sortDexSpecies(result, by: sort)
    }

    enum SpeciesIndexStatus: Equatable, Sendable { case idle, loading, ready, unavailable }

    /// Fetched on the first search, so people who never search never hit the network.
    func loadSpeciesIndexIfNeeded() async {
        guard speciesIndexStatus == .idle || speciesIndexStatus == .unavailable,
              let speciesIndexProvider else { return }
        speciesIndexStatus = .loading
        do {
            speciesIndex = try await speciesIndexProvider.speciesIndex()
            speciesIndexStatus = .ready
        } catch {
            speciesIndexStatus = .unavailable
            AppLog.write("species index unavailable: \(error)")
        }
    }

    /// Supported species with no entry in the dex, as grid cells. Empty until the index is loaded.
    var unownedDexSpecies: [DexSpecies] {
        guard let speciesIndex else { return [] }
        let owned = Set(dexSpecies.map(\.id))
        return speciesIndex.all.compactMap { entry in
            guard !owned.contains(entry.id), PokemonAssets.isSupported(speciesID: entry.id),
                  let rarity = speciesIndex.rarity(of: entry.id) else { return nil }
            return DexSpecies(id: entry.id,
                              name: state.language.resolveName(entry.names) ?? "#\(entry.id)",
                              rarity: rarity, isShiny: false, isRaising: false,
                              names: entry.names, isOwned: false)
        }
    }

    /// Sorts DexSpecies by the given option.
    func sortDexSpecies(_ species: [DexSpecies], by sort: DexSortOption) -> [DexSpecies] {
        switch sort {
        case .numberAsc:
            return species.sorted { $0.id < $1.id }
        case .numberDesc:
            return species.sorted { $0.id > $1.id }
        case .nameAsc:
            return species.sorted {
                let cmp = $0.name.localizedCompare($1.name)
                return cmp == .orderedAscending ? true : (cmp == .orderedSame ? $0.id < $1.id : false)
            }
        case .nameDesc:
            return species.sorted {
                let cmp = $0.name.localizedCompare($1.name)
                return cmp == .orderedDescending ? true : (cmp == .orderedSame ? $0.id < $1.id : false)
            }
        case .rarityDesc:
            return species.sorted {
                if $0.rarity.sortRank != $1.rarity.sortRank {
                    return $0.rarity.sortRank > $1.rarity.sortRank
                }
                return $0.id < $1.id
            }
        }
    }

    /// Refresh legacy names once, including saves that retained only app-supported languages.
    ///
    /// 격자는 저장된 이름만 읽으므로 백필이 없으면 칸이 종 번호(`#41`)로 남는다. 포획 로그는 행이
    /// 뜰 때 행 단위로 같은 일을 해 왔지만, 로그를 한 번도 안 열면 격자는 계속 번호다.
    /// 라인 조회는 `PokeAPIClient` 가 base 단위로 캐시하므로 같은 라인이 여러 항목이어도 네트워크는 1회.
    /// 오프라인이면 `dexResolveChainNames` 가 저장 없이 폴백만 돌려주므로 다음 진입에서 다시 시도한다.
    func backfillMissingDexNames() async {
        for entry in state.dex where entry.needsNamesRefresh {
            _ = await dexResolveChainNames(entry)   // 성공분만 내부에서 state.dex 에 저장
        }
    }

    /// 도감 항목 진화 체인 각 종의 이름(speciesID → 현재 언어 이름). 저장돼 있으면 즉시(네트워크 0),
    /// 없으면 nil(뷰가 async 조회로 폴백).
    func dexStoredChainNames(_ entry: DexEntry) -> [Int: String]? {
        guard let names = entry.names, !names.isEmpty else { return nil }
        return names.compactMapValues { state.language.resolveName($0) }
    }

    /// Refresh missing/legacy multilingual names; current versions require no lookup.
    /// Offline, keep saved names and use species numbers only where no name is available.
    /// 반환은 chainOrder 전 종을 채운 [speciesID: 현재 언어 이름].
    func dexNameLine(baseID: Int) async throws -> EvoLine {
        if let request = dexNameRequests[baseID] { return try await request.value }
        let provider = self.provider
        let request = Task { try await provider.line(baseSpeciesID: baseID) }
        dexNameRequests[baseID] = request
        defer { dexNameRequests[baseID] = nil }
        return try await request.value
    }

    func dexResolveChainNames(_ entry: DexEntry) async -> [Int: String] {
        // Another row of this evolution line may already have refreshed the stored entry.
        let entry = state.dex.first { $0.id == entry.id } ?? entry
        if !entry.needsNamesRefresh, let stored = dexStoredChainNames(entry) { return stored }
        let oldNames = dexStoredChainNames(entry) ?? [:]
        guard let line = try? await dexNameLine(baseID: entry.baseID) else {
            return Dictionary(uniqueKeysWithValues: entry.chainOrder.map { ($0, oldNames[$0] ?? "#\($0)") })
        }
        // Preserve usable older names if a response is partial. Only a complete chain gets
        // the new version, so partial/offline responses remain eligible for retry.
        func refreshed(_ original: DexEntry) -> DexEntry {
            var result = original
            var merged = original.names ?? [:]
            for id in original.chainOrder {
                if let incoming = line.names[id], !incoming.isEmpty {
                    merged[id] = (merged[id] ?? [:]).merging(incoming) { _, new in new }
                }
            }
            result.names = merged.isEmpty ? nil : merged
            if original.chainOrder.allSatisfy({ line.names[$0]?.isEmpty == false }) {
                result.namesVersion = DexEntry.currentNamesVersion
            }
            return result
        }
        // One successful lookup also refreshes duplicate catches of the same evolution line.
        for index in state.dex.indices where state.dex[index].baseID == entry.baseID
            && state.dex[index].needsNamesRefresh {
            state.dex[index] = refreshed(state.dex[index])
        }
        save()
        let chainNames = refreshed(entry).names ?? [:]
        return Dictionary(uniqueKeysWithValues: entry.chainOrder.map { id in
            (id, chainNames[id].flatMap { state.language.resolveName($0) } ?? "#\(id)")
        })
    }
}
