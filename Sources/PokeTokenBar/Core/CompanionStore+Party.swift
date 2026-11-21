import Foundation

extension CompanionStore {
    // MARK: 동행 포켓몬

    /// Graduates and stored lines that are not friends yet, newest first. Ids are Box ids.
    var friendCandidates: [DexEntry] {
        let graduates = state.dex.filter { !$0.isReleased && $0.id != state.raisedEntryID }
        let stored = state.storedLines.map { storedBoxEntry(id: $0.key, $0.value.mon) }
        return (graduates + stored).filter { !state.isFriend(boxID: $0.id) }
            .sorted { ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast) }
    }

    /// The friend as it stands now; a stored line shows its current species.
    func friendEntry(forKey key: String) -> DexEntry? {
        let id = CompanionState.boxID(ofFriendKey: key)
        if id != key { return state.storedLines[id].map { storedBoxEntry(id: id, $0.mon) } }
        return state.dex.first { $0.id == id && !$0.isReleased }
    }

    /// `entryID` is a Box id: a graduate that is not a friend yet, or a stored line, while a slot is free.
    /// Returns false and keeps the picks otherwise.
    @discardableResult
    func addFriend(entryID: String) -> Bool {
        guard state.friendEntryIDs.count < CompanionState.maxFriends,
              let key = state.friendKey(forBoxID: entryID), !state.friendEntryIDs.contains(key) else { return false }
        state.friendEntryIDs.append(key)
        reevaluateEvolution()
        return true
    }

    func removeFriend(entryID: String) {
        guard state.isFriend(boxID: entryID) else { return }
        state.friendEntryIDs.removeAll { CompanionState.boxID(ofFriendKey: $0) == entryID }
        reevaluateEvolution()
    }

    // MARK: 키우는 포켓몬 지정

    /// A graduate the player may raise: an owned, settled individual that is not already the raised one. A stored
    /// line needs a line to swap with: the egg fields can't wait beside a line in `active`.
    func canRaise(entryID: String) -> Bool {
        guard !isHatching, !isRevealingDitto, entryID != state.raisedEntryID, !isTradeLocked(entryID) else { return false }
        if state.storedLines[entryID] != nil { return state.active != nil }
        guard let entry = state.dex.first(where: { $0.id == entryID }) else { return false }
        return !entry.isReleased && entry.profile != nil && entry.tradeEvolutionPending != true
    }

    /// Raises a graduate or a stored line. For a graduate, the line in `active` (or the egg) is parked as it stands;
    /// a graduate raised before goes back to the Box with the level it reached. A stored line takes `active` back
    /// where it stopped and the line there goes to the Box. Returns false and changes nothing when it can't be raised.
    @discardableResult
    func raise(entryID: String) -> Bool {
        guard canRaise(entryID: entryID) else { return false }
        if state.storedLines[entryID] != nil {
            resumeStoredLine(entryID)
        } else {
            if state.raisedEntryID == nil { state.parkedSpentTokens = state.spentTokens }
            state.raisedEntryID = entryID
            state.reconcileFriends()
        }
        settleRaisedChange()
        return true
    }

    /// Spending and battles while it waited in the Box don't count toward its evolution gate.
    private func resumeStoredLine(_ entryID: String) {
        if state.raisedEntryID != nil { state.resumeParkedLine(now: clock()) }
        storeActiveInBox()
        guard let stored = state.storedLines.removeValue(forKey: entryID) else { return }
        state.dex.removeAll { $0.id == entryID && $0.isReleased }
        var mon = stored.mon
        mon.evolution.spentBaseline += max(0, state.spentTokens - stored.spentAtStore)
        if mon.evolution.battleCursor != nil { mon.evolution.battleCursor = clock() }
        state.active = mon
        currentLine = nil
        state.reconcileFriends()
        state.reconcileRepresentativeSelection()
    }

    /// Moves the line in `active` to the Box as it stands. Its released record keeps the species in the Pokédex.
    /// Returns the stored individual's ID.
    @discardableResult
    func storeActiveInBox() -> String? {
        guard let a = state.active else { return nil }
        let record = releasedDexEntry(from: a)
        state.dex.append(record)
        state.storedLines[record.id] = StoredLine(mon: a, spentAtStore: state.spentTokens)
        state.active = nil
        return record.id
    }

    /// Takes the parked line (or egg) back exactly where it stopped; the raised graduate returns to the Box.
    @discardableResult
    func resumeLine() -> Bool {
        guard state.raisedEntryID != nil, !isHatching, !isRevealingDitto else { return false }
        state.resumeParkedLine(now: clock())
        settleRaisedChange()
        return true
    }

    func settleRaisedChange() {
        activeGeneration += 1
        isHatchRetryDelayed = false
        prefetchedLineID = nil
        justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        celebration = nil
        displayState = isEgg ? .egg : .idle
        reevaluateEvolution()   // saves
        if state.active != nil, !isLineParked, currentLine == nil { Task { await loadCurrentLine() } }
        if raisedGraduate != nil { Task { await checkRaisedGraduateEvolution() } }
        if state.active == nil, !isLineParked { Task { await ensureEggPrefetch() } }
    }

    func refreshFriendSubjects() {
        let next = state.friendEntryIDs.compactMap { key in
            friendEntry(forKey: key).map {
                FriendSubject($0, megaSpriteID: megaSpriteID(instanceID: $0.id, speciesID: $0.finalID))
            }
        }
        if friendSubjects != next { friendSubjects = next }
    }

    func isRepresentative(_ species: DexSpecies) -> Bool {
        state.representativeSpeciesID == species.id
            && (species.form == nil || state.representativeForm == species.form)
    }

    /// Settings describe the selected form, even though the main Pokédex aggregates the species.
    var representativeDexSpecies: DexSpecies? {
        guard let selected = representativeSpeciesID else { return nil }
        let candidates = PokemonForm.hasForms(speciesID: selected) ? formSpecies(speciesID: selected) : dexSpecies
        return candidates.first { isRepresentative($0) }
    }

    // 알 인큐베이션 (active 없을 때)
    var isEgg: Bool { state.active == nil && raisedGraduate == nil }
    var eggStarted: Bool { state.eggUsage > 0 }
    var eggProgress: Double { min(1, max(0, Double(state.eggUsage) / Double(eggHatchThreshold))) }
    var eggTokensToHatch: Int { max(0, eggHatchThreshold - state.eggUsage) }

    var displayName: String {
        if let graduate = raisedGraduate { return formDisplayName(dexEntryName(graduate), speciesID: graduate.finalID, form: graduate.form) }
        guard let a = state.active, let line = currentLine else { return "Token Egg" }
        return formDisplayName(line.localizedName(a.currentID, state.language),
                               speciesID: a.currentID, form: currentForm)
    }
    var currentSpeciesID: Int? { raisedGraduate?.finalID ?? state.active?.currentID }
    var currentForm: PokemonForm? {
        PokemonForm.resolved(speciesID: currentSpeciesID ?? 0, form: raisedGraduate?.form ?? state.active?.form)
    }
    var isFinalStage: Bool {
        if raisedGraduate != nil { return true }
        guard let a = state.active, let line = currentLine else { return false }
        return line.tree.node(withID: a.currentID)?.children(for: a.profile?.gender).isEmpty ?? true
    }
    var stageText: String {
        if let graduate = raisedGraduate {
            let level = "Lv\(graduate.profile?.level ?? 5)"
            return evolvingGraduate == nil ? "\(level) · \(l.finalForm)" : level
        }
        guard let a = state.active else { return "" }
        return isFinalStage ? l.finalForm : l.stage(a.stageIndex + 1, a.totalForms)
    }
    var threshold: Int {
        guard let a = state.active, !isLineParked else { return 1 }
        return stageThreshold(for: a)
    }
    var progress: Double {
        guard let a = state.active, !isLineParked, threshold > 0 else { return 0 }
        return min(1, max(0, Double(a.usedAtStage) / Double(threshold)))
    }
    /// Follow the companion being raised, even when a Pokédex representative is pinned.
    var menuGrowthText: String {
        if let graduate = raisedGraduate { return "Lv\(graduate.profile?.level ?? 5)" }
        let total = isEgg ? eggHatchThreshold : threshold
        let credits = isEgg ? state.eggUsage : (state.active?.usedAtStage ?? 0)
        let used = min(max(0, credits), total)
        // Match Home's integer flooring without losing exact boundaries to Double rounding.
        let percent = total > 0 ? used * 100 / total : 0
        return l.menuGrowthProgress(percent, isEgg: isEgg)
    }
    var tokensToNext: Int {
        guard let a = state.active, !isLineParked else { return 0 }
        return max(0, threshold - a.usedAtStage)
    }

    /// 진화 라인 표시용: 실현된 경로 + 다음 단계 미리보기.
    /// 유일하게 이어지는 단계 뒤에 분기가 있으면, 그 확정 접두어와 하나의 미지 항목을 함께 보여 준다.
    /// 분기 후보는 부화 시 계획됐더라도 실제 진화 전까지 하나의 미지 항목으로 숨긴다.
    var lineNodes: [EvoLineItem] {
        if let graduate = raisedGraduate {
            return Self.realizedLineItems(pathIDs: graduate.chainOrder, stageIndex: max(0, graduate.chainOrder.count - 1))
        }
        guard let a = state.active, let line = currentLine else { return [] }
        var out = Self.realizedLineItems(pathIDs: a.pathIDs, stageIndex: a.stageIndex)
        if let current = line.tree.node(withID: a.currentID) {
            var node = current
            var guaranteedPrefix: [EvoNode] = []
            let gender = a.profile?.gender
            while node.children(for: gender).count == 1, let child = node.children(for: gender).first {
                guaranteedPrefix.append(child)
                node = child
            }

            if node.children(for: gender).count > 1 {
                out += guaranteedPrefix.map { EvoLineItem(.species($0.speciesID), .future) }
                out.append(EvoLineItem(.mystery, .future))
            } else {
                out += guaranteedPrefix.map { EvoLineItem(.species($0.speciesID), .future) }
            }
        }
        return out
    }

    static func realizedLineItems(pathIDs: [Int], stageIndex: Int) -> [EvoLineItem] {
        pathIDs.enumerated().map { i, id in
            EvoLineItem(.species(id), i == stageIndex ? .current : .done)
        }
    }
    /// 도감에는 영구 보존된 졸업 개체와 현재 키우는 포켓몬을 함께 표시한다.
    /// 현재 개체는 영속 dex 에 중복 저장하지 않고 화면용 항목으로 합성한다. 졸업 시 active 가 사라지고
    /// 같은 개체의 영구 DexEntry 가 추가되므로 목록 개수는 그대로 유지된다.
    var activeDexEntry: DexEntry? {
        guard let active = state.active else { return nil }
        return DexEntry(
            id: "active-\(active.baseID)-\(active.currentID)",
            baseID: active.baseID,
            finalID: active.currentID,
            chainOrder: active.pathIDs,
            rarity: active.rarity,
            caughtAt: nil,
            isShiny: active.displaysShiny,   // 위장 메타몽은 리빌 전까지 이로치를 숨긴다(판정 단일 소스)
            nature: active.nature,
            profile: active.profile,
            names: currentLine.map { line in
                Dictionary(uniqueKeysWithValues:
                    active.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
            },
            form: active.form,
            prayers: active.prayers
        )
    }

    /// The Pokédex record of a line sent to the Box (or released, in saves from before the Box kept it).
    ///
    /// **도달한 형태만 담는다**(`pathIDs.prefix(stageIndex + 1)`). 도감이 육성 중 보여주던 범위와
    /// 같아야 놓아준 뒤에도 칸 구성이 그대로 유지된다 — `plannedPathIDs` 나 `pathIDs` 전체를 쓰면
    /// 도달한 적 없는 진화형까지 보유로 잡힌다(`dexSpecies` 가 같은 prefix 규칙을 쓴다).
    ///
    /// 이로치는 `currentIsShiny` — 위장 중인 메타몽은 리빌 전까지 숨긴다(`activeDexEntry` 와 단일 판정).
    /// `caughtAt` 은 놓아준 시각이다.
    private func releasedDexEntry(from a: MonState) -> DexEntry {
        // stageIndex 가 음수·범위 밖이어도 최소 한 형태는 남긴다(손상 상태 파일 방어 — MonState.currentID 와 같은 태도).
        let reached = Array(a.pathIDs.prefix(max(1, a.stageIndex + 1)))
        let chain = reached.isEmpty ? [a.baseID] : reached
        let now = clock()
        return DexEntry(
            id: a.profile?.instanceID ?? UUID().uuidString,
            baseID: a.baseID,
            finalID: chain.last ?? a.baseID,
            chainOrder: chain,
            rarity: a.rarity,
            caughtAt: now,
            isShiny: a.displaysShiny,
            nature: a.nature,
            profile: a.profile,
            names: currentLine.map { line in
                Dictionary(uniqueKeysWithValues:
                    chain.compactMap { id in line.names[id].map { (id, $0) } })
            },
            releasedAt: now, form: a.form, prayers: a.prayers)
    }

    var dexEntries: [DexEntry] {
        guard let activeDexEntry else { return state.dex }
        return state.dex + [activeDexEntry]
    }

    var raisedDexEntry: DexEntry? { activeDexEntry }

    /// 합성된 현재 포켓몬 항목인지 판별한다. caughtAt 이 없는 구버전 졸업 항목과 혼동하지 않는다.
    func isActiveDexEntry(_ entry: DexEntry) -> Bool {
        entry.id == activeDexEntry?.id
    }

    /// 현재 키우는 포켓몬을 맨 앞에 고정하고, 졸업 항목은 기록 시각 최신순.
    /// caughtAt 이 없는 구버전 항목은 .distantPast 로 묶여 맨 뒤에 온다(그들끼리의 순서는 미정).
    var dexEntriesSorted: [DexEntry] {
        let graduated = state.dex.sorted {
            ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast)
        }
        guard let activeDexEntry else { return graduated }
        return [activeDexEntry] + graduated
    }

    enum DexSortOption: String, CaseIterable, Identifiable, Sendable {
        case numberAsc
        case numberDesc
        case nameAsc
        case nameDesc
        case rarityDesc

        var id: String { rawValue }
    }

    /// 도감 한 칸 — 메인 목록은 종별, 폼이 있는 종의 상세 목록은 폼별로 중복 기록을 합친다.
    /// **종 정보만 담는다** — 성격·획득 횟수처럼 개체에 딸린 것은 포획 로그가 개체 단위로 보여준다.
    struct DexSpecies: Sendable {
        let id: Int                     // speciesID = 도감 번호(정렬 키)
        let name: String
        let rarity: Rarity
        let isShiny: Bool               // 이 종을 이로치로 보유한 적이 있는가
        /// 이 종이 현재 키우는 개체의 **현재 형태**인가. 지나온 진화 단계에는 서지 않는다.
        let isRaising: Bool
        var form: PokemonForm? = nil
        var names: [String: String]? = nil
        var hasNormal = false
        /// False only for species listed from the full index, which the user has not obtained.
        var isOwned = true
        /// Set only where one individual is shown (the battle picker); species rows stay default.
        var isFemale = false

        /// Species IDs remain Pokédex numbers; selection also includes the form.
        var collectionID: String {
            guard let form else { return String(id) }
            return "\(id)-\(form.rawValue)"
        }
    }

    struct DexKey: Hashable {
        let speciesID: Int
        let form: PokemonForm?

        init(_ speciesID: Int, form: PokemonForm?, groupForms: Bool) {
            self.speciesID = speciesID
            self.form = groupForms ? PokemonForm.resolved(speciesID: speciesID, form: form) : nil
        }
    }

    /// 종 하나가 모으는 것 — 누적 전용. 병렬 딕셔너리를 여러 개 두면 키 집합이 서로 어긋날 수 있고
    /// (한쪽에만 써서 그 종이 조용히 사라지거나), 읽는 쪽에 도달 불가한 기본값이 생긴다. 하나로 묶어
    /// 두 여지를 함께 없앤다.
    struct DexAccumulator {
        /// 첫 발견 때 확정 — 같은 종은 항상 같은 base 라인에서 오므로 갱신할 값이 없다.
        let rarity: Rarity
        var names: [String: String]?
        var isShiny = false
        var hasNormal = false
    }

    /// 도감 목록 — 보유 종만, 도감 번호 오름차순.
    ///
    /// 포함 종 = 졸업분 `chainOrder` ∪ 현재 개체의 **도달분** `pathIDs[0...stageIndex]`.
    /// `plannedPathIDs`(사전 선택된 전체 경로)는 미도달 단계를 포함하므로 절대 쓰지 않는다 — 쓰면
    /// 아직 진화하지 않은 종이 보유로 잡힌다.
    var dexSpecies: [DexSpecies] {
        collectedDexSpecies(groupForms: false)
    }

    /// Sprite → Pokédex detail link targets (species number → dex cell `collectionID`). Only species
    /// in the dex have a key, so eggs, unreached evolutions and uncaught species are not clickable.
    /// The main dex does not split forms (the form is picked on the detail page), so a
    /// species number maps to exactly one cell.
    var dexLinkTargets: [Int: String] {
        dexSpecies.reduce(into: [:]) { links, species in links[species.id] = species.collectionID }
    }

    /// `dexLinkTargets` plus the unowned dex page (`String(id)`) for each listed species the species
    /// index knows. Empty extras until the index is loaded.
    func dexLinkTargets(including speciesIDs: [Int]) -> [Int: String] {
        var links = dexLinkTargets
        guard let speciesIndex else { return links }
        for id in speciesIDs where links[id] == nil && PokemonAssets.isSupported(speciesID: id)
            && speciesIndex.rarity(of: id) != nil {
            links[id] = String(id)
        }
        return links
    }

    /// Collected form summaries for the detail picker; missing forms remain visible but disabled.
    func formSpecies(speciesID: Int) -> [DexSpecies] {
        guard PokemonForm.hasForms(speciesID: speciesID) else { return [] }
        return collectedDexSpecies(groupForms: true).filter { $0.id == speciesID }
    }
}
