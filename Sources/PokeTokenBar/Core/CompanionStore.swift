import Foundation
import Observation
import UserNotifications

/// 게임 상태의 출처. 설치 이후 토큰 사용량으로 포켓몬을 진화시키고, 최종체 + 추가 임계 도달 시
/// 도감(라인 전체)에 보존 + 새 알. 진화 트리/희귀도/이름은 PokeProviding 으로 런타임 주입.
@MainActor
@Observable
final class CompanionStore {
    private(set) var state = CompanionState()
    private(set) var displayState: CompanionStateKind = .egg
    /// Time since the last token usage while `displayState == .sulk`, else 0.
    private(set) var sulkIdle: TimeInterval = 0
    /// Mirror of `UsageStore.alwaysFacesBack` (set by `AppDelegate.updateCompanion`): a display preference.
    var alwaysFacesBack = false
    /// The companion shows its back sprite on every surface: while sulking, or always when asked to.
    /// An egg has no back to show.
    var facesBack: Bool { hasRaisedPokemon && (alwaysFacesBack || displayState == .sulk) }
    private(set) var currentLine: EvoLine?
    private(set) var representativeSubject = RepresentativeSubject(speciesID: nil, isShiny: false)
    /// Graduated Pokémon shown beside the active one. Display only: no growth, stats or save effect beyond the pick.
    private(set) var friendSubjects: [FriendSubject] = []
    /// The latest stone put on or taken off a matching Pokémon. Surfaces play the Mega Evolution effect from it.
    private(set) var megaEvolveEvent: MegaEvolveEvent?
    @ObservationIgnored private var megaEvolveCounter = 0
    /// Bumped when the active Pokémon hatches, evolves, graduates or reveals as Ditto; friends cheer on a change.
    private(set) var cheerSeq = 0
    private(set) var isHatching = false
    private(set) var isRevealingDitto = false   // 메타몽 리빌 비동기 중복 방지(isHatching 자매)
    private(set) var justEvolvedTo: String?     // 이름(연출/문구)
    private(set) var justGraduated: String?
    private var eventUntil: Date?

    /// 부화/진화 연출 트리거 — seq 증가로 UI 가 감지, 팝오버가 닫혀 있었어도 다음 오픈에 1회 재생.
    enum Celebration: Equatable { case hatch(shiny: Bool), evolve, dittoReveal(shiny: Bool) }
    private(set) var celebration: Celebration?
    private(set) var celebrationSeq = 0
    private func fireCelebration(_ c: Celebration) { celebration = c; celebrationSeq += 1; cheerSeq += 1 }
    /// 연출 재생 후 UI 가 호출(1회성 보장).
    func consumeCelebration() { celebration = nil }

    /// 사탕 사용 시 "+XP" 순간 표시 — 진화 없이 부분 진행일 때도 피드백. seq 증가로 CompanionHeader 감지.
    private(set) var candyFeedbackSeq = 0
    private(set) var candyFeedbackAmount = 0
    /// "+XP" 표시 1회성 보장 — CompanionHeader 가 재생 후 호출한다. 소비하지 않으면 다른 탭에 갔다
    /// 홈으로 재진입할 때(CompanionHeader 재마운트) @State 가 초기화돼 같은 값이 다시 떠오른다(회귀).
    func consumeCandyFeedback() { candyFeedbackAmount = 0 }

    /// 민트 사용 시 "성격이 X로" 순간 표시 — 사탕 피드백과 동일 1회성 패턴(seq + consume).
    private(set) var mintFeedbackSeq = 0
    private(set) var mintFeedbackNature: PokemonNature?
    func consumeMintFeedback() { mintFeedbackNature = nil }

    private let provider: any PokeProviding
    private var dexNameRequests: [Int: Task<EvoLine, Error>] = [:]
    private let detailProvider: (any PokemonDetailProviding)?
    private let speciesIndexProvider: (any SpeciesIndexProviding)?
    let clock: () -> Date
    private let fileURL: URL
    private var rng: any RandomNumberGenerator
    private let dittoDisguiseRollingEnabled: Bool
    private(set) var speciesIndex: SpeciesIndex?
    private(set) var speciesIndexStatus = SpeciesIndexStatus.idle
    private(set) var pokemonDetailsByID: [Int: PokemonDetails] = [:]
    private(set) var loadingPokemonDetailIDs: Set<Int> = []
    private(set) var failedPokemonDetailIDs: Set<Int> = []
    let defaults: UserDefaults
    /// 세션 내 활성 개체 교체 감지용. await 뒤 이전 개체의 결과가 새 개체를 덮지 않게 한다.
    private var activeGeneration = 0
    private var lastAutoSnapshotDate: Date?
    private var nextEvolutionGateCheck = Date.distantPast
    private(set) var availableSnapshots: [SaveSnapshot] = []
    private var timeMeter = ActiveTimeMeter()
    private var timeActiveNow = false
    private var rebaseUsageOnNextUpdate = false
    private var tokenModeSinceUnsaved = false

    // MARK: 난이도 배율 (설정 — UserDefaults)
    //
    // 세이브(CompanionState)가 아니라 UserDefaults 에 둔다. 이건 진행 상황이 아니라 취향 설정이고
    // (설정창의 다른 슬라이더와 같은 자리), 세이브에 넣으면 남의 세이브를 불러올 때 내 난이도가 조용히
    // 바뀌며 SaveTransfer 의 관대 디코딩·검증까지 새 수치 필드를 떠안는다.

    /// 성장 배율 — 알 부화 임계 + 진화/졸업 임계에 곱한다. 낮을수록 빨리 자란다.
    /// 사탕 XP(RareCandy.xp)는 스케일하지 않는다 — 함께 곱하면 서로 상쇄돼 사탕만 난이도를 안 탄다.
    private(set) var growthDifficulty: Double
    /// 상점 배율 — 아이템·알 가격에 곱한다. 낮을수록 싸다.
    private(set) var shopDifficulty: Double
    /// Moves a stuck raised Pokémon or an idle Exp. Share holder on by itself (`CompanionStore+MoveOn`).
    var autoMoveOn: Bool {
        didSet { defaults.set(autoMoveOn, forKey: Self.autoMoveOnKey) }
    }
    /// The popover is open, so the player can see a stuck Pokémon.
    private(set) var isAttended = false

    init(provider: any PokeProviding = PokeAPIClient.shared,
         detailProvider: (any PokemonDetailProviding)? = nil,
         speciesIndexProvider: (any SpeciesIndexProviding)? = nil,
         clock: @escaping () -> Date = Date.init,
         fileURL: URL? = nil,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
         dittoDisguiseRollingEnabled: Bool = AppEnv.isBundledApp,
         defaults: UserDefaults = .standard) {
        self.provider = provider
        self.detailProvider = detailProvider ?? (provider as? any PokemonDetailProviding)
        self.speciesIndexProvider = speciesIndexProvider ?? (provider as? any SpeciesIndexProviding)
        self.clock = clock
        self.fileURL = fileURL ?? Self.defaultURL()
        self.rng = rng
        self.dittoDisguiseRollingEnabled = dittoDisguiseRollingEnabled
        self.defaults = defaults
        autoMoveOn = defaults.object(forKey: Self.autoMoveOnKey) as? Bool ?? true
        let storedGrowth = defaults.object(forKey: "growthDifficulty") as? Double
        let storedShop = defaults.object(forKey: "shopDifficulty") as? Double
        let difficultyMigrated = defaults.bool(forKey: PokemonBalance.difficultyMigratedKey)
        // Previous releases accepted 0.01%–2000%. Reprice their banked progress before
        // persisting the narrower range, otherwise an upgrade silently changes completion.
        let previousGrowth = storedGrowth.map { $0.isFinite ? min(20, max(0.0001, $0)) : 1 } ?? 1
        if difficultyMigrated {
            growthDifficulty = PokemonBalance.clampDifficulty(storedGrowth ?? PokemonBalance.defaultDifficulty)
            shopDifficulty = PokemonBalance.clampDifficulty(storedShop ?? PokemonBalance.defaultDifficulty)
        } else {
            growthDifficulty = PokemonBalance.migratedDifficulty(storedGrowth)
            shopDifficulty = PokemonBalance.migratedDifficulty(storedShop)
        }
        load()
        if state.tokenModeSince == nil {
            state.tokenModeSince = clock()
            tokenModeSinceUnsaved = true
        }
        if difficultyMigrated, previousGrowth != growthDifficulty {
            rescaleBankedGrowth(from: previousGrowth, to: growthDifficulty)
            save()
        }
        migrateEconomyIfNeeded(previousGrowth: difficultyMigrated ? nil : previousGrowth)
        defaults.set(growthDifficulty, forKey: "growthDifficulty")
        defaults.set(shopDifficulty, forKey: "shopDifficulty")
        if !difficultyMigrated { defaults.set(previousGrowth, forKey: PokemonBalance.legacyGrowthKey) }
        defaults.set(true, forKey: PokemonBalance.difficultyMigratedKey)
        migratePokemonProfilesIfNeeded()
        seedDexCompletionsIfNeeded()
        // A region finished before the reward shipped is paid on the first launch that sees it.
        if !DexProgress.unrewardedRegions(earned: earnedDexBadges, rewarded: state.rewardedDexRegions).isEmpty {
            save()
        }
        refreshRepresentativeSubject()
        refreshFriendSubjects()
        refreshSnapshots()
        if !isEgg { displayState = .idle }
    }

    static func defaultURL() -> URL {
        // 상태 파일 위치. 기본은 Application Support/PokeTokenBar. `PTB_STATE_DIR` 환경변수가 있으면
        // 그 디렉토리를 쓴다 — 개발/QA 격리용(실제 companion 상태를 건드리지 않고 데모 상태로 실행).
        // 프로덕션은 이 변수가 없어 무영향.
        AppStatePaths.directory().appendingPathComponent("companion-state.json")
    }

    // MARK: 파생값 (UI)

    var language: AppLanguage { state.language }
    func setLanguage(_ lang: AppLanguage) { state.language = lang; save() }

    // MARK: 난이도 — 저장할 때만 적용

    /// Keep the earned fraction of this egg/stage. These are progression credits,
    /// not actual usage: lifetime tokens, provider ledgers and wallet never change here.
    func setGrowthDifficulty(_ value: Double) {
        let clamped = PokemonBalance.clampDifficulty(value)
        guard clamped != growthDifficulty else { return }
        rescaleBankedGrowth(from: growthDifficulty, to: clamped)
        growthDifficulty = clamped
        defaults.set(clamped, forKey: "growthDifficulty")
        // Do not evolve, graduate or hatch just because Settings changed.
        save()
    }

    /// Moves a save from the old token tables to the current ones. Credits keep the fraction they had:
    /// the old effective multiplier (`previousGrowth`, in the old tables) is `economyDivisor` times larger
    /// when written against the new tables. Without `previousGrowth` (an import or snapshot restore) the
    /// current difficulty is assumed. Profile growth is table-relative, so it always shrinks by the divisor.
    private func migrateEconomyIfNeeded(previousGrowth: Double?) {
        guard state.economyVersion < PokemonBalance.economyVersion else { return }
        let divisor = Double(PokemonBalance.economyDivisor)
        let from = (previousGrowth ?? growthDifficulty) * divisor
        if state.usedSinceInstall > 0 || state.active != nil || !state.dex.isEmpty,
           FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("companion-state.pre-economy-v2.json")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
        }
        if from != growthDifficulty {
            rescaleBankedGrowth(from: from, to: growthDifficulty, alsoEgg: true)
        }
        if var active = state.active, var profile = active.profile {
            profile.growthTokens /= PokemonBalance.economyDivisor
            active.profile = profile
            state.active = active
        }
        for index in state.dex.indices {
            state.dex[index].profile?.growthTokens /= PokemonBalance.economyDivisor
        }
        state.economyVersion = PokemonBalance.economyVersion
        save()
        AppLog.write("economy migration complete — token tables divided by \(PokemonBalance.economyDivisor)")
    }

    /// The slider the player had before the ÷5 tables, while the migrated slider is still untouched.
    private var legacyGrowthForOldSaves: Double? {
        guard let legacy = defaults.object(forKey: PokemonBalance.legacyGrowthKey) as? Double,
              PokemonBalance.migratedDifficulty(legacy) == growthDifficulty else { return nil }
        return legacy
    }

    private func rescaleBankedGrowth(from old: Double, to new: Double, alsoEgg: Bool = false) {
        func rescaled(_ credits: Int, base: Int) -> Int {
            // Calculate the old threshold without the new range clamp during migration.
            let oldThreshold = max(1, Int((Double(base) * old).rounded()))
            let newThreshold = max(1, Int((Double(base) * new).rounded()))
            let value = Double(credits) / Double(oldThreshold) * Double(newThreshold)
            let rounded = Int(min(Double(SaveTransfer.maxTokenValue), max(0, value.rounded(.down))))
            // Rounding must never turn an incomplete stage into a completed one.
            return credits < oldThreshold ? min(newThreshold - 1, rounded) : rounded
        }
        if var active = state.active {
            active.usedAtStage = rescaled(active.usedAtStage, base: active.phaseThreshold)
            state.active = active
            if alsoEgg { state.eggUsage = rescaled(state.eggUsage, base: PokemonBalance.eggHatchThreshold) }
        } else {
            state.eggUsage = rescaled(state.eggUsage, base: PokemonBalance.eggHatchThreshold)
        }
    }

    /// 상점 배율 변경 — 가격과 소비 진화 조건은 읽을 때 배율을 곱하므로 저장 상태를 고치지 않는다.
    func setShopDifficulty(_ value: Double) {
        let clamped = PokemonBalance.clampDifficulty(value)
        guard clamped != shopDifficulty else { return }
        shopDifficulty = clamped
        defaults.set(clamped, forKey: "shopDifficulty")
    }

    /// 난이도를 반영한 알 부화 임계. 첫 실행 안내 문구도 이 값을 보여준다.
    var eggHatchThreshold: Int {
        PokemonBalance.scaled(PokemonBalance.eggHatchThreshold, by: growthDifficulty)
    }

    /// 난이도를 반영한 단계 임계. **`PokemonBalance.phaseThreshold` 를 직접 부르지 않는다** —
    /// 배율을 빠뜨린 호출부가 생기면 그 경로만 조용히 기본 난이도로 돌아간다.
    func stageThreshold(for mon: MonState) -> Int {
        PokemonBalance.scaled(mon.phaseThreshold, by: growthDifficulty)
    }

    /// 상점 표시·결제에 쓰는 실제 가격 — 기본가 × 상점 난이도. 미판매면 nil.
    func price(of kind: ItemKind) -> Int? {
        let base = kind == .expShare ? ExpShare.price(owned: itemOwnedTotal(kind)) : kind.shopPrice
        return base.map { PokemonBalance.scaled($0, by: shopDifficulty) }
    }

    /// 알을 포함한 상점 한 줄의 실제 가격.
    func price(of entry: ShopEntry) -> Int {
        PokemonBalance.scaled(entry.price, by: shopDifficulty)
    }
    /// 앱 전체 UI 문자열 — language 변경 시 자동 재렌더.
    var l: L { L(language) }

    /// A line Pokémon (not an egg) is the one being raised. False while a graduate is raised: the line is parked.
    var hasActive: Bool { state.active != nil && !isLineParked }
    /// Something other than an egg is the raised Pokémon — a line Pokémon or the raised graduate.
    var hasRaisedPokemon: Bool { state.active != nil || raisedGraduate != nil }
    /// The graduate raised in place of the line. The line (or its egg) waits untouched until it is resumed.
    var raisedGraduate: DexEntry? { state.raisedEntry }
    var isLineParked: Bool { raisedGraduate != nil }
    /// What the Home resume line calls the parked one: its name, or the egg's.
    var parkedLineName: String? {
        guard isLineParked else { return nil }
        return activeDexEntry.map(dexEntryName) ?? l.parkedEggName
    }
    var rarity: Rarity? { raisedGraduate?.rarity ?? state.active?.rarity }
    var currentIsShiny: Bool {   // 위장 중엔 이로치 숨김(리빌 때 공개)
        if let graduate = raisedGraduate { return graduate.isShiny }
        return state.active?.displaysShiny ?? false
    }
    var currentNature: PokemonNature? {
        if let graduate = raisedGraduate { return graduate.nature }
        return state.active?.nature
    }
    var currentGender: PokemonGender? {
        if let graduate = raisedGraduate { return graduate.profile?.gender }
        return state.active?.profile?.gender
    }
    var currentIsFemale: Bool { currentGender == .female }
    var growthMultiplier: Int? {
        guard !isLineParked else { return nil }
        return state.active?.hasGrowthBoost == true ? PokemonBalance.repeatGrowthMultiplier : nil
    }

    /// 메뉴바와 플로팅 펫이 그릴 대표 종과 색. nil 선택은 기존 동작(현재 개체/알)을 보존한다.
    /// 저장된 값이라 상시 렌더링 경로가 도감 전체를 다시 접거나 불필요한 상태를 관찰하지 않는다.
    struct RepresentativeSubject: Equatable, Sendable {
        let speciesID: Int?
        let isShiny: Bool
        var form: PokemonForm? = nil
        var isFemale = false
        /// Mega form sprite shown while the matching Mega Stone is held; species and form stay the base ones.
        var megaSpriteID: Int? = nil

        var spriteSpeciesID: Int? { megaSpriteID ?? speciesID }
        var spriteForm: PokemonForm? { megaSpriteID == nil ? form : nil }
        var spriteIsFemale: Bool { megaSpriteID == nil && isFemale }
    }

    var representativeSpeciesID: Int? { state.representativeSpeciesID }
    var representativeForm: PokemonForm? { state.representativeForm }

    /// 관련 상태가 바뀌어 저장되는 경계에서만 갱신한다. 고정 종 하나의 이로치 여부만 조회하므로
    /// 이름 해석·정렬을 포함한 `dexSpecies` 계산을 메뉴바/플로팅 펫 렌더마다 반복하지 않는다.
    private func refreshRepresentativeSubject() {
        let next: RepresentativeSubject
        if let selected = state.representativeSpeciesID {
            next = RepresentativeSubject(speciesID: selected,
                isShiny: state.ownsShinySpecies(selected, form: state.representativeForm),
                form: PokemonForm.resolved(speciesID: selected, form: state.representativeForm),
                isFemale: state.newestIndividualIsFemale(selected, form: state.representativeForm),
                megaSpriteID: megaSpriteID(forSpecies: selected))
        } else {
            next = RepresentativeSubject(speciesID: currentSpeciesID, isShiny: currentIsShiny,
                                         form: currentForm, isFemale: currentIsFemale,
                                         megaSpriteID: currentMegaSpriteID)
        }
        if representativeSubject != next { representativeSubject = next }
    }

    /// nil 은 자동 추적. 도감에 없는 id 는 저장하지 않는다 — UI 밖 호출이나 손상된 입력도 같은
    /// 불변식을 지키며, 실패한 요청이 기존 선택을 조용히 해제하지 않도록 false 만 반환한다.
    @discardableResult
    func setRepresentativeSpeciesID(_ id: Int?, form: PokemonForm? = nil) -> Bool {
        if let id, !state.ownsSpecies(id, form: form) { return false }
        state.representativeSpeciesID = id
        state.representativeForm = PokemonForm.resolved(speciesID: id ?? 0, form: form)
        save()
        return true
    }

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
    private func storeActiveInBox() -> String? {
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

    private func settleRaisedChange() {
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

    private func refreshFriendSubjects() {
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
    /// 알이 부화 준비(100%)가 되었으나 PokéAPI 요청/후보 선택 실패로 다음 갱신을 기다리는 상태.
    private(set) var isHatchRetryDelayed = false

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
    private var activeDexEntry: DexEntry? {
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

    private struct DexKey: Hashable {
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
    private struct DexAccumulator {
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
    private func seedDexCompletionsIfNeeded() {
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

    private func collectedDexSpecies(groupForms: Bool) -> [DexSpecies] {
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
    private func dexNameLine(baseID: Int) async throws -> EvoLine {
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

    // MARK: 갱신 (AppDelegate 가 UsageStore 값으로 호출)

    /// `timeSinceLastUsage`: nil when unknown (see `UsageStore.timeSinceLastUsage`); unknown never sulks.
    /// It comes from the slower enrichment scan, so a rise in today's total seen here counts as usage at once.
    func update(todayTokensByProvider: [String: Int], todayDate: String, monthTotal: Int,
                burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool,
                timeSinceLastUsage: TimeInterval? = nil) {
        let todayTokens = todayTokensByProvider.values.reduce(0, +)
        // `hasUsageData`는 표시용 snapshot 존재 여부이고, 이 map은 오늘 날짜가 확인된
        // provider 데이터만 담는다. stale snapshot이나 today == nil carrier만 있는 refresh는
        // ledger의 기준점을 움직일 수 있는 관측으로 취급하지 않는다.
        let hasCurrentProviderData = hasUsageData && !todayTokensByProvider.isEmpty
        let idle = effectiveIdle(timeSinceLastUsage: timeSinceLastUsage, todayDate: todayDate,
                                 todayTokens: todayTokens, hasCurrentProviderData: hasCurrentProviderData)
        if state.growthMode == .time, !state.installBaselineSet, !hasCurrentProviderData {
            // Time mode must work with no coding agent at all. A nil ledger seeds from the first usage seen later.
            state.installBaselineSet = true
        }
        if !state.installBaselineSet {
            // 설치 기준선 — 실제 데이터가 도착한 시점의 today 를 baseline 으로(이전 사용량 미카운트).
            // 데이터 도착 전(기동 직후 빈 새로고침)에는 잡지 않는다.
            guard hasCurrentProviderData else {
                // 세이브 불러오기가 baseline 판정을 이 경로에 넘겼을 수 있다(SaveTransfer.rebasedForThisDevice).
                // 그 경우 개체는 이미 들어와 있으므로 알로 표시하면 안 되고, 진화 라인 로드도 계속 재시도해야
                // 한다 — 새 Mac 은 AI CLI 를 처음 쓸 때까지 hasUsageData 가 false 라 여기서 막히면 그날 내내
                // 알로 보인다(재시작해도 동일).
                displayState = isEgg ? .egg : .idle
                kickLineLoadIfNeeded()
                return
            }
            state.installBaselineSet = true
            state.claimedTodayTokensByProvider = todayTokensByProvider
            state.lastDate = todayDate
            save()
        } else {
            // `today == nil` carrier만 남거나 파싱이 실패한 refresh는 현재 map이 비어 있을 수
            // 있다. 그런 관측으로 날짜·ledger를 움직이면 다음 정상 snapshot을 당일 전체 신규
            // 사용량으로 오인할 수 있으므로, 유효한 사용량이 있는 refresh만 ledger를 갱신한다.
            if hasCurrentProviderData {
                let dateChanged = todayDate != state.lastDate
                if state.claimedTodayTokensByProvider == nil {
                    // 구버전 세이브에는 aggregate high-water mark만 있어 프로바이더별로 분해할 수 없다.
                    // 첫 유효 관측을 새 장부의 기준점으로만 저장해 과거 사용량을 소급 지급하지 않는다.
                    state.claimedTodayTokensByProvider = todayTokensByProvider
                    state.lastDate = todayDate
                    AppLog.write("companion provider ledger seeded date=\(todayDate) providers=\(todayTokensByProvider.keys.sorted().joined(separator: ","))")
                } else if dateChanged {
                    // 일자별 snapshot은 서로 비교할 수 없다. 새 날짜에는 이전 날짜의 ledger를
                    // 기준으로 삼지 않고, 현재 날짜의 누적값 전체를 새 날짜 사용량으로 적립한다.
                    // 단, 위의 nil migration 경로는 구버전 aggregate를 분해할 수 없으므로 seed만 한다.
                    //
                    // 이전 날짜에 이미 알려진 provider가 첫 새로고침에서 빠질 수 있다(오늘 데이터
                    // 없음, stale 응답, 일시 실패). 그 provider를 아예 ledger에서 제거하면 같은
                    // 날짜에 복구될 때 현재 누적값을 "이미 적립한 값"으로 seed해 사용량이 누락된다.
                    // 이전 날짜의 숫자는 비교에 사용할 수 없으므로, 알려진 provider의 새 날짜 기준을
                    // 0으로 열어 둔다. 이후 복구된 현재 날짜 값은 그 날짜의 실제 사용량으로 적립되고,
                    // 같은 날짜의 부분 응답에서는 이 기준을 그대로 보존한다.
                    state.lastDate = todayDate
                    var newLedger = Dictionary(uniqueKeysWithValues:
                        state.claimedTodayTokensByProvider!.keys.map { ($0, 0) })
                    for (providerID, current) in todayTokensByProvider {
                        newLedger[providerID] = current
                    }
                    state.claimedTodayTokensByProvider = newLedger
                    creditRealUsage(todayTokensByProvider.values.reduce(0, +))
                } else {
                    var ledger = state.claimedTodayTokensByProvider ?? [:]
                    var delta = 0
                    for (providerID, current) in todayTokensByProvider {
                        guard let previous = ledger[providerID] else {
                            // 새로 관측된 프로바이더의 과거 로그를 소급하지 않는다. 이후 refresh부터
                            // 해당 프로바이더의 증가분을 추적할 수 있도록 현재 값을 seed한다.
                            ledger[providerID] = current
                            continue
                        }
                        if current < previous {
                            // 전체 합계가 아니라 해당 프로바이더의 line만 rebase한다. 다른 프로바이더가
                            // 이번 refresh에서 보고하지 않았거나 carrier snapshot만 남은 경우에는 map에
                            // line 자체가 없으므로 기존 기준값을 건드리지 않는다.
                            ledger[providerID] = current
                            AppLog.write("companion usage regression provider=\(providerID) date=\(todayDate) previous=\(previous) current=\(current) drop=\(previous - current) — rebased provider ledger")
                            continue
                        }
                        delta += current - previous
                        ledger[providerID] = current
                    }
                    state.claimedTodayTokensByProvider = ledger
                    creditRealUsage(delta)
                }
            }
        }
        // 이벤트(진화/졸업/부화) 창 만료 — .levelUp 창이 끝날 때 문구 플래그를 함께 정리한다.
        // justEvolvedTo 는 창 만료(expireEventWindow)에서만 지운다: 과거엔 매 update() 초입에 무조건 nil 로 밀어,
        // 진화 후 4초 창 도중 update 틱이 끼면 "…(으)로 진화했어요"→"성장했어요"로 되돌아갔다(회귀 #4).
        expireEventWindow()
        if state.active == nil, state.raisedEntry == nil, state.installBaselineSet, !isHatching {
            if state.eggUsage >= eggHatchThreshold {
                // ready egg 는 부화를 우선한다. 같은 틱에 프리패치와 별도 Task 로 경쟁시키면
                // 프리패치 락을 본 부화가 반환하고 실패 상태도 놓칠 수 있다.
                Task { await hatchIfNeeded() }
            } else {
                // 임계 전에는 종 pre-roll + 라인/스프라이트 예열(부화 순간 딜레이 제거).
                Task { await ensureEggPrefetch() }
            }
        }
        // active 인데 라인 미로딩(앱 재시작) → 로드
        if state.active != nil, currentLine == nil, !isHatching {
            Task { await loadCurrentLine() }
        }
        // 위장 메타몽이 첫 진화 임계 도달 → 리빌(재시작 등 applyUsage 킥을 못 탄 경우 백업 트리거)
        if let a = state.active, !isLineParked, a.dittoDisguise != nil, !a.dittoRevealed, currentLine != nil,
           !isHatching, !isRevealingDitto,
           a.usedAtStage >= stageThreshold(for: a) {
            Task { await revealDitto() }
        }
        if burnTier == .blazing { recordTokenRain() }
        checkEvolutionGate()
        displayState = computeState(burnTier: burnTier, limitWarning: limitWarning,
                                    hasUsageData: hasUsageData, today: todayTokens,
                                    timeSinceLastUsage: idle)
        sulkIdle = displayState == .sulk ? idle ?? 0 : 0
        rebaseUsageOnNextUpdate = false
        save()
        autoSnapshotIfNeeded()
    }

    /// Real usage: only token mode turns it into growth and wallet.
    private func creditRealUsage(_ delta: Int) {
        guard delta > 0 else { return }
        state.lastUsageAt = clock()
        guard state.growthMode == .token, !rebaseUsageOnNextUpdate else { return }
        state.usedSinceInstall += delta
        creditUsage(delta)
    }

    // MARK: Time mode

    var growthMode: GrowthMode { state.growthMode }

    func setGrowthMode(_ mode: GrowthMode) {
        guard mode != state.growthMode else { return }
        state.growthMode = mode
        if mode == .token {
            state.tokenModeSince = clock()
            rebaseUsageOnNextUpdate = true
        }
        timeMeter.reanchor()
        timeActiveNow = false
        save()
    }

    /// The monitor reports sleep, screen sleep or lock: the next tick only re-anchors.
    func noteActivityBreak() {
        timeMeter.reanchor()
        timeActiveNow = false
    }

    /// One tick of time mode. `uptime` is monotonic and excludes sleep; `idle` is seconds since the last input.
    /// Credits active seconds as virtual tokens to growth and, at its own rate, to the wallet. Returns the growth
    /// tokens credited.
    @discardableResult
    func creditActiveTime(uptime: TimeInterval, idle: TimeInterval, present: Bool) -> Int {
        if tokenModeSinceUnsaved {
            tokenModeSinceUnsaved = false
            save()
        }
        guard state.growthMode == .time else {
            timeMeter.reanchor()
            return 0
        }
        let seconds = timeMeter.step(uptime: uptime, idle: idle, present: present)
        timeActiveNow = present && idle <= PokemonBalance.timeIdleLimit
        let tokens = PokemonBalance.timeTokens(forActiveSeconds: seconds)
        guard tokens > 0 else {
            refreshTimeDisplayState()
            return 0
        }
        state.timeCredit += PokemonBalance.timeTokens(forActiveSeconds: seconds,
                                                      perHour: PokemonBalance.timeWalletTokensPerActiveHour)
        state.installBaselineSet = true
        creditUsage(tokens)
        save()
        if state.active == nil, state.raisedEntry == nil, !isHatching {
            if state.eggUsage >= eggHatchThreshold {
                Task { await hatchIfNeeded() }
            } else {
                Task { await ensureEggPrefetch() }
            }
        }
        refreshTimeDisplayState()
        return tokens
    }

    @discardableResult
    private func expireEventWindow() -> Bool {
        guard let until = eventUntil, clock() > until else { return false }
        justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        return true
    }

    private func refreshTimeDisplayState() {
        guard state.active != nil else { return }
        if expireEventWindow(), displayState == .levelUp { displayState = timeActiveNow ? .working : .sleep }
        switch displayState {
        case .egg, .idle, .working, .sleep, .sulk: displayState = timeActiveNow ? .working : .sleep
        default: break
        }
    }

    /// Token mode with no real usage for `idleTokenHintAfter`: offer time mode once.
    var showsIdleTokenHint: Bool {
        guard state.growthMode == .token, !state.idleHintDismissed else { return false }
        let since = [state.lastUsageAt, state.tokenModeSince].compactMap { $0 }.max() ?? clock()
        return clock().timeIntervalSince(since) >= PokemonBalance.idleTokenHintAfter
    }

    func dismissIdleTokenHint() {
        state.idleHintDismissed = true
        save()
    }

    /// A gate that waits on the clock (day/night) opens without any new usage. Called from every usage update and
    /// from the app's 30-second tick; at most one check per 20 seconds.
    func checkEvolutionGate() {
        checkStuckMoveOn()
        if !state.expShareHolders.isEmpty, clock() >= nextExpShareCheck {
            nextExpShareCheck = clock().addingTimeInterval(20)
            Task { await checkExpShareEvolution() }
        }
        if raisedGraduate != nil {
            guard clock() >= nextEvolutionGateCheck else { return }
            nextEvolutionGateCheck = clock().addingTimeInterval(20)
            Task { await checkRaisedGraduateEvolution() }
            return
        }
        guard let a = state.active, !isLineParked, currentLine != nil, a.dittoDisguise == nil || a.dittoRevealed,
              a.usedAtStage >= stageThreshold(for: a), clock() >= nextEvolutionGateCheck else { return }
        nextEvolutionGateCheck = clock().addingTimeInterval(20)
        applyUsage(0)
    }

    /// The period now and the seconds left in it, on the app's clock.
    func dayPeriodNow() -> (period: DayPeriod, secondsLeft: TimeInterval, degrees: Double) {
        let now = clock()
        return (DayPeriod.at(now), DayPeriod.secondsUntilSwitch(from: now), DayPeriod.cycleDegrees(from: now))
    }

    /// Usage goes to exactly one place: the raised graduate, else the line in `active`, else the egg.
    /// A parked line or egg gets nothing.
    private func creditUsage(_ delta: Int) {
        let raisedID = state.raisedEntry?.id
        let raisingIDs = Set([raisedID, state.active?.profile?.instanceID].compactMap { $0 })
        if raisedID != nil {
            creditRaisedGraduate(delta)
        } else if state.active != nil {
            applyUsage(delta)
        } else {
            state.eggUsage += delta
        }
        creditExpShareHolders(delta / ExpShare.shareDivisor, skipping: raisingIDs)
    }

    /// A graduate grows by level only, on the same curve as the line (`delta` is in the difficulty's units).
    private func growGraduate(at index: Int, by delta: Int) {
        guard var profile = state.dex[index].profile else { return }
        let standard = Int((Double(delta) / PokemonBalance.clampDifficulty(growthDifficulty)).rounded(.down))
        profile.applyGrowth(standard, rarity: state.dex[index].rarity)
        if let details = pokemonDetailsByID[state.dex[index].finalID] { profile.enrich(with: details) }
        state.dex[index].profile = profile
    }

    private func creditRaisedGraduate(_ delta: Int) {
        guard delta > 0, let index = state.dex.firstIndex(where: { $0.id == state.raisedEntryID }),
              state.dex[index].profile != nil else { return }
        growGraduate(at: index, by: delta)
        if var progress = raisedEvolutionProgress {
            progress.graduateXP += delta
            setRaisedEvolutionProgress(progress)
            evolveRaisedGraduateIfReady()
        }
    }

    /// 토큰 증분을 현재 포켓몬에 적용 — 임계 도달 시 진화/졸업.
    /// 라인 미로딩(재시작 직후·오프라인)이어도 사용량은 항상 적립한다 — 여기서 드롭하면
    /// 프로바이더별 ledger 는 이미 전진해 델타가 영구 유실된다. 진화 판정만 라인 로드 후로 미룬다.
    func applyUsage(_ delta: Int) {
        guard state.active != nil, !isLineParked else { return }
        state.active!.usedAtStage += delta
        reconcileActiveProfileGrowth()
        guard let line = currentLine else { save(); return }
        var guardCount = 0
        while state.active != nil, guardCount < 50 {
            guardCount += 1
            let a = state.active!
            let thr = stageThreshold(for: a)
            guard a.usedAtStage >= thr else { break }
            guard let node = line.tree.node(withID: a.currentID) else { break }
            // 위장체는 부화 때는 다형태지만, 에셋 정규화/마이그레이션 뒤 leaf가 될 수 있다.
            // 따라서 terminal 졸업보다 먼저 리빌해야 위장 종이 도감으로 잘못 졸업하지 않는다.
            if a.dittoDisguise != nil, !a.dittoRevealed {
                if !isRevealingDitto { Task { await revealDitto() } }
                break
            }
            let gender = a.profile?.gender
            let options = growthOptions(of: node, gender: gender)
            if options.isEmpty {
                graduate(); break
            } else if holdsEverstone(a.profile?.instanceID) {
                break
            } else {
                let step = lineStep(of: a, at: node, among: options)
                let next = step.next
                let context = evolutionContext(for: a, thresholdOverride: thr)
                let openPath = EvolutionRules.openPath(into: next.speciesID, in: context)
                // A closed gate keeps the stage open: the XP keeps adding up and carries over once it opens.
                guard let openPath else {
                    notifyEvolutionStuckIfNeeded(of: a, into: next, in: line, context: context)
                    break
                }
                if step.replans {
                    replanEvolution(from: node, to: next, base: a)
                    AppLog.write("evolve: replanned path for base \(a.baseID)")
                }
                spendEvolutionRequirements(of: openPath, instanceID: a.profile?.instanceID)
                completeEvolution(of: a, to: next, in: line, usedAtStage: a.usedAtStage - thr)   // 초과분 이월
            }
        }
        reconcileActiveProfileGrowth()
        save()
    }

    /// Tells the player once per blocking reason that the form is ready but a condition is unmet. Time is one
    /// reason however many times the period flips, so a day/night wait is not announced every ten minutes.
    private func notifyEvolutionStuckIfNeeded(of a: MonState, into next: EvoNode, in line: EvoLine, context: EvolutionContext) {
        guard let rule = EvolutionRules.rule(for: next.speciesID) else { return }
        let block = rule.block(in: context)
        let blocking: [EvolutionRequirement]
        switch block {
        case .open: return
        case .clock: blocking = []
        case .conditions(let conditions): blocking = conditions
        }
        let key = ([String(next.speciesID)] + blocking.map { String(describing: $0) }).joined(separator: "|")
        guard a.evolution.stuckNotified != key else { return }
        state.active!.evolution.stuckNotified = key
        let name = formDisplayName(line.localizedName(a.currentID, state.language),
                                   speciesID: a.currentID, form: a.form)
        if case .clock(let period) = block {
            let what = l.notifEvolveStuckWaitsFor(period, minutes: Self.minutes(DayPeriod.secondsUntilSwitch(from: clock())))
            notifyCompanionEvent(l.notifEvolveStuckTitle, l.notifEvolveStuckBody(name, what))
            return
        }
        let what = blocking.map {
            l.evolutionRequirementText($0, speciesName: { speciesIndex?.entry($0)?.names[language.rawValue] ?? "#\($0)" },
                                       shopDifficulty: shopDifficulty)
        }.joined(separator: " + ")
        notifyCompanionEvent(l.notifEvolveStuckTitle, l.notifEvolveStuckSkippableBody(name, what))
    }

    static func minutes(_ seconds: TimeInterval) -> Int { max(1, Int((seconds / 60).rounded(.up))) }

    /// The form a line moves into next: its planned child (else a fresh pick), resolved for the clock and its traits.
    /// `replans` when that is not the plan. The raised line and a stored holder both choose here.
    func lineStep(of a: MonState, at node: EvoNode, among options: [EvoNode]) -> (next: EvoNode, replans: Bool) {
        let nextIndex = a.stageIndex + 1
        let traits = evolutionTraits(of: a)
        let planned = a.plannedPathIDs.indices.contains(nextIndex)
            ? options.first(where: { $0.speciesID == a.plannedPathIDs[nextIndex] }) : nil
        let picked = planned ?? pickPlannedChild(node, baseID: a.baseID, gender: a.profile?.gender, traits: traits)
        let timed = EvoNode.resolvingTimeOfDay(picked, among: options, at: DayPeriod.at(clock()))
        let next = EvolutionRules.resolvingSelector(timed, among: options, traits: traits)
        return (next, planned == nil || next.speciesID != picked.speciesID)
    }

    private func replanEvolution(from node: EvoNode, to next: EvoNode, base a: MonState) {
        let plan = replannedPath(from: node, to: next, base: a)
        state.active!.plannedPathIDs = plan
        state.active!.totalForms = plan.count
    }

    /// 실제로 간 갈래가 계획과 다르면 계획을 그 갈래 아래로 다시 세운다.
    private func replannedPath(from node: EvoNode, to next: EvoNode, base a: MonState) -> [Int] {
        let fallbackRoute = [node.speciesID]
            + makeEvolutionPlan(from: next, baseID: a.baseID, gender: a.profile?.gender, traits: evolutionTraits(of: a))
        return Self.repairedPlan(realizedPath: a.pathIDs, stageIndex: a.stageIndex, fallbackRoute: fallbackRoute)
    }

    /// 다음 형태로 넘어가는 공통 처리 — 경로·단계·프로필·연출·알림. 저장은 호출부가 한다.
    private func completeEvolution(of a: MonState, to next: EvoNode, in line: EvoLine, usedAtStage: Int) {
        state.active!.pathIDs = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [next.speciesID]
        state.active!.stageIndex += 1
        state.active!.usedAtStage = usedAtStage
        state.active!.evolution = a.evolution.nextForm(spentBaseline: state.spentTokens)
        if let details = pokemonDetailsByID[next.speciesID] {
            state.active!.profile?.enrich(with: details)
        } else if detailProvider != nil {
            Task { await self.loadPokemonDetails(speciesID: next.speciesID) }
        }
        let oldName = formDisplayName(line.localizedName(a.currentID, state.language),
                                      speciesID: a.currentID, form: a.form)
        let newName = formDisplayName(line.localizedName(next.speciesID, state.language),
                                      speciesID: next.speciesID, form: a.form)
        if let companion = EvolutionRules.companions[next.speciesID] {
            registerCompanion(companion, evolvedFrom: a, in: line)
        }
        justEvolvedTo = newName
        fireCelebration(.evolve)
        // 짧은 levelUp 창 — 진화 순간 "…(으)로 진화했어요" 문구 노출(hatch/graduate 와 동일 패턴).
        // 이게 없으면 computeState 가 .levelUp 을 안 내 statusEvolved 가 도달 불가(dead code)였다.
        eventUntil = clock().addingTimeInterval(4)
        notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(from: oldName, to: newName))
    }

    // MARK: 특이 진화 조건

    private func registerCompanion(_ species: Int, evolvedFrom a: MonState, in line: EvoLine) {
        let id = UUID().uuidString
        var profile = PokemonProfile.generate(
            seed: PokemonProfileMigration.seed("companion:\(id):\(species)"),
            growthTokens: PokemonBalance.graduationTotal(a.rarity), instanceID: id)
        profile.applyGrowth(0, rarity: a.rarity)
        if let details = pokemonDetailsByID[species] { profile.enrich(with: details) }
        let chain = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [species]
        state.collectedFinals.insert("\(a.baseID):\(species)")
        state.dex.append(DexEntry(id: id, baseID: a.baseID, finalID: species, chainOrder: chain, rarity: a.rarity,
                                  caughtAt: clock(), nature: a.nature, profile: profile,
                                  names: Dictionary(uniqueKeysWithValues: chain.compactMap { sid in
                                      line.names[sid].map { (sid, $0) }
                                  })))
    }

    /// Everything the evolution rules read about `mon` right now.
    func evolutionContext(for mon: MonState, thresholdOverride: Int? = nil) -> EvolutionContext {
        evolutionContext(progress: mon.evolution, speciesID: mon.currentID, profile: mon.profile,
                         stageXP: mon.usedAtStage, stageThreshold: thresholdOverride ?? stageThreshold(for: mon))
    }

    private func evolutionContext(progress: EvolutionProgress, speciesID: Int, profile: PokemonProfile?,
                                  stageXP: Int, stageThreshold: Int) -> EvolutionContext {
        var context = EvolutionContext()
        context.progress = progress
        context.period = DayPeriod.at(clock())
        context.level = profile?.level ?? 5
        if let details = pokemonDetailsByID[speciesID] {
            context.knownMoves = Set(details.levelUpMoves(through: context.level).map(\.name))
            context.learnableMoves = Set(details.moves.filter { move in
                move.learnMethods.contains { $0.method == "level-up" }
            }.map(\.name))
        }
        context.knownMoves.formUnion(profile?.moves.map(\.name) ?? [])
        if let id = profile?.instanceID { context.heldItem = heldItem(of: id) }
        for (kind, count) in ownedItems { context.bag[kind] = count }
        for key in state.friendEntryIDs {
            guard let entry = friendEntry(forKey: key), entry.id != profile?.instanceID else { continue }
            context.friendCount += 1
            context.friendLines.formUnion(entry.chainOrder)
            context.friendLines.insert(entry.finalID)
            context.friendTypes.formUnion(speciesTypes(entry.finalID))
        }
        context.spentTokens = state.spentTokens
        context.shopDifficulty = shopDifficulty
        context.stageXP = stageXP
        context.stageThreshold = stageThreshold
        return context
    }

    func speciesTypes(_ id: Int) -> [String] {
        speciesIndex?.entry(id)?.types ?? pokemonDetailsByID[id]?.types ?? []
    }

    /// The held item and bag item a satisfied path used up.
    private func spendEvolutionRequirements(of path: [EvolutionRequirement], instanceID: String?) {
        for requirement in path {
            switch requirement {
            case .holds:
                if let instanceID { state.heldItems[instanceID] = nil }
            case .bag(let kind):
                state.inventory[kind.rawValue] = max(0, itemCount(kind) - 1)
            default:
                break
            }
        }
    }

    /// The form the raised Pokémon is waiting to take and what it still lacks; nil when nothing special waits.
    func pendingEvolutionGate() -> (rule: EvolutionRule, context: EvolutionContext)? {
        if raisedGraduate != nil { return raisedGraduateGate() }
        guard let a = state.active, let node = currentLine?.tree.node(withID: a.currentID) else { return nil }
        let gender = a.profile?.gender
        let options = growthOptions(of: node, gender: gender)
        let traits = evolutionTraits(of: a)
        let nextIndex = a.stageIndex + 1
        let planned = a.plannedPathIDs.indices.contains(nextIndex)
            ? options.first { $0.speciesID == a.plannedPathIDs[nextIndex] } : nil
        guard let target = planned ?? EvolutionRules.plannable(options, traits: traits).first else { return nil }
        let timed = EvoNode.resolvingTimeOfDay(target, among: options, at: DayPeriod.at(clock()))
        let next = EvolutionRules.resolvingSelector(timed, among: options, traits: traits)
        guard let rule = EvolutionRules.rule(for: next.speciesID), !rule.paths.isEmpty else { return nil }
        return (rule, evolutionContext(for: a))
    }

    // MARK: Moving on from a stuck Pokémon (`CompanionStore+MoveOn`)

    func setAttended(_ attended: Bool) {
        guard attended != isAttended else { return }
        isAttended = attended
        guard state.stuckWatch != nil else { return }
        state.stuckWatch?.since = clock()
        save()
    }

    /// Called from the evolution tick. Starts, resets or clears the watch, and moves on once it has run out unseen.
    func checkStuckMoveOn() {
        guard !isHatching, !isRevealingDitto, !isStuckUnknown else { return }
        let stuck = stuckRaised
        if let stuck, let mark = state.keepWaiting[stuck.id], mark != stuck.speciesID {
            state.keepWaiting[stuck.id] = nil
        }
        guard autoMoveOn, let stuck, !isKeptWaiting(stuck.id, species: stuck.speciesID) else {
            if state.stuckWatch != nil {
                state.stuckWatch = nil
                save()
            }
            return
        }
        guard let watch = state.stuckWatch, watch.id == stuck.id else {
            state.stuckWatch = StuckWatch(id: stuck.id, since: clock())
            save()
            return
        }
        guard !isAttended, clock().timeIntervalSince(watch.since) >= Self.stuckMoveOnDelay else { return }
        moveOn(stuck)
    }

    func keepWaitingOnStuck() {
        guard let stuck = stuckRaised else { return }
        state.keepWaiting[stuck.id] = stuck.speciesID
        state.stuckWatch = nil
        save()
    }

    private func moveOn(_ stuck: StuckRaised) {
        state.stuckWatch = nil
        let next: MoveOnNext
        if stuck.isGraduate {
            let parkedName = parkedLineName ?? l.parkedEggName
            state.resumeParkedLine(now: clock())
            addFriendIfSlotFree(stuck.id)
            if let pick = raiseCandidate(excluding: stuck.id), raise(entryID: pick.id) {
                next = .raise(candidateName(pick.id))
            } else {
                settleRaisedChange()
                next = .resume(parkedName)
            }
        } else if let pick = raiseCandidate(excluding: stuck.id) {
            let name = candidateName(pick.id)
            if state.storedLines[pick.id] != nil {
                raise(entryID: pick.id)
                if state.storedLines[stuck.id] != nil { addFriendIfSlotFree(stuck.id) }
            } else {
                storeActiveForNewEgg(tier: nil, pendingHatchID: nil, attachesBagCopy: false)
                raise(entryID: pick.id)
            }
            next = .raise(name)
        } else {
            storeActiveForNewEgg(tier: nil, pendingHatchID: nil, attachesBagCopy: false)
            next = .egg
        }
        giveBagExpShareToCandidate()
        save()
        AppLog.write("move on: \(stuck.speciesID) stuck, next \(next)")
        notifyCompanionEvent(l.moveOnTitle,
                             l.moveOnBody(stuck.name, requirementsText(stuck.needs), next, toGraduates: stuck.isGraduate))
    }

    // MARK: Skipping a blocked evolution

    /// The active Pokémon is ready but held back by something other than the clock, so it may graduate as it is.
    var canSkipEvolution: Bool {
        guard let a = state.active, hasActive, currentLine != nil, a.dittoDisguise == nil || a.dittoRevealed,
              !holdsEverstone(a.profile?.instanceID), a.usedAtStage >= stageThreshold(for: a),
              let pending = pendingEvolutionGate(), case .conditions = pending.rule.block(in: pending.context)
        else { return false }
        return true
    }

    /// Graduates the active Pokémon in its current form. Its progress toward the blocked step goes with it, so
    /// raising it again later can still evolve it.
    @discardableResult
    func skipEvolutionAndGraduate() -> Bool {
        guard canSkipEvolution, let a = state.active else { return false }
        var progress = a.evolution
        progress.stuckNotified = nil
        progress.graduateXP = max(0, a.usedAtStage - stageThreshold(for: a))
        guard let entryID = graduate() else { return false }
        state.graduateEvolution[entryID] = progress
        save()
        return true
    }

    // MARK: Evolving a raised graduate

    /// The raised graduate's line, loaded by `checkRaisedGraduateEvolution`. In memory only.
    private(set) var raisedGraduateLine: EvoLine?
    private var isLoadingGraduateLine = false

    /// The forms the graduate's current form can grow into, resolved for the clock and its traits now.
    func graduateOptions(_ entry: DexEntry, in line: EvoLine) -> [EvoNode] {
        guard let node = line.tree.node(withID: entry.finalID) else { return [] }
        let options = growthOptions(of: node, gender: entry.profile?.gender)
        let traits = entry.profile.map { EvolutionTraits(seed: $0.seed, ivs: $0.ivs, nature: entry.nature) }
        return EvolutionRules.plannable(options, traits: traits).map { option in
            let timed = EvoNode.resolvingTimeOfDay(option, among: options, at: DayPeriod.at(clock()))
            return EvolutionRules.resolvingSelector(timed, among: options, traits: traits)
        }
    }

    /// A graduate has finished growing, so it counts as having reached its stage threshold; `graduateXP` is what
    /// it has past that. Only the `longStage` requirement reads the two.
    func graduateContext(_ entry: DexEntry) -> EvolutionContext {
        let progress = state.graduateEvolution[entry.id] ?? EvolutionProgress(spentBaseline: state.spentTokens)
        let forms = max(1, entry.chainOrder.count)
        let threshold = PokemonBalance.scaled(
            PokemonBalance.phaseThreshold(rarity: entry.rarity, totalForms: forms + 1, stageIndex: forms - 1),
            by: growthDifficulty)
        return evolutionContext(progress: progress, speciesID: entry.finalID, profile: entry.profile,
                                stageXP: threshold + progress.graduateXP, stageThreshold: threshold)
    }

    /// The raised graduate, when its line is loaded and its form can still evolve.
    var evolvingGraduate: (entry: DexEntry, line: EvoLine)? {
        guard let entry = raisedGraduate, let line = raisedGraduateLine, line.baseID == entry.baseID,
              !graduateOptions(entry, in: line).isEmpty else { return nil }
        return (entry, line)
    }

    func raisedGraduateGate() -> (rule: EvolutionRule, context: EvolutionContext)? {
        guard let graduate = evolvingGraduate else { return nil }
        for option in graduateOptions(graduate.entry, in: graduate.line) {
            if let rule = EvolutionRules.rule(for: option.speciesID), !rule.paths.isEmpty {
                return (rule, graduateContext(graduate.entry))
            }
        }
        return nil
    }

    /// Loads the raised graduate's line once, then evolves it if a step is open. Called on raise and from the tick.
    func checkRaisedGraduateEvolution() async {
        guard let entry = raisedGraduate, !isLoadingGraduateLine else { return }
        if raisedGraduateLine?.baseID != entry.baseID {
            isLoadingGraduateLine = true
            defer { isLoadingGraduateLine = false }
            guard let line = try? await dexNameLine(baseID: entry.baseID) else { return }
            raisedGraduateLine = line
        }
        if evolveRaisedGraduateIfReady() { save() }
    }

    /// Takes every step whose conditions hold now. The caller saves. Returns whether it evolved.
    @discardableResult
    private func evolveRaisedGraduateIfReady() -> Bool {
        guard let id = raisedGraduate?.id, let line = raisedGraduateLine else { return false }
        return evolveGraduateIfReady(id: id, in: line, celebrate: true)
    }

    /// A Box holder evolving only notifies; the celebration on the home screen belongs to the raised Pokémon.
    private func evolveGraduateIfReady(id: String, in line: EvoLine, celebrate: Bool) -> Bool {
        var evolved = false
        for _ in 0..<5 {
            guard let index = state.dex.firstIndex(where: { $0.id == id && !$0.isReleased }),
                  line.baseID == state.dex[index].baseID else { break }
            let entry = state.dex[index]
            let options = graduateOptions(entry, in: line)
            if options.isEmpty {
                state.graduateEvolution[entry.id] = nil
                break
            }
            if holdsEverstone(entry.id) { break }
            let context = graduateContext(entry)
            let step = options.lazy.compactMap { option in
                EvolutionRules.openPath(into: option.speciesID, in: context).map { (speciesID: option.speciesID, path: $0) }
            }.first
            guard let step else { break }
            spendEvolutionRequirements(of: step.path, instanceID: entry.profile?.instanceID)
            evolveGraduate(at: index, to: step.speciesID, in: line, progress: context.progress, celebrate: celebrate)
            evolved = true
        }
        return evolved
    }

    // MARK: Exp. Share

    /// Lines of graduated Exp. Share holders, by base species. In memory only.
    private(set) var expShareLines: [Int: EvoLine] = [:]
    private var loadingExpShareLines: Set<Int> = []
    private var nextExpShareCheck = Date.distantPast

    func holdsExpShare(_ instanceID: String) -> Bool { state.expShareHolders.contains(instanceID) }

    func showsExpShareSlot(for individual: BoxIndividual) -> Bool {
        holdsExpShare(individual.id) || (Self.canHoldExpShare(individual.role) && itemOwnedTotal(.expShare) > 0)
    }

    /// Graduated, friend and stored individuals can hold one; the Pokémon being raised or resting cannot.
    func canAttachExpShare(to instanceID: String) -> Bool {
        guard itemCount(.expShare) > 0, !holdsExpShare(instanceID),
              let individual = boxIndividual(id: instanceID) else { return false }
        return Self.canHoldExpShare(individual.role)
    }

    private static func canHoldExpShare(_ role: BoxIndividual.Role) -> Bool {
        role == .graduated || role == .friend || role == .stored
    }

    @discardableResult
    func attachExpShare(to instanceID: String) -> Bool {
        guard canAttachExpShare(to: instanceID) else { return false }
        let left = itemCount(.expShare) - 1
        state.inventory[ItemKind.expShare.rawValue] = left > 0 ? left : nil
        state.expShareHolders.append(instanceID)
        save()
        Task { await checkExpShareEvolution() }
        return true
    }

    /// A shop or scout egg puts one copy from the bag on the Pokémon it sends to the Box.
    var eggSwapAttachesExpShare: Bool { itemCount(.expShare) > 0 }

    /// A shop or scout egg makes the Pokémon it sends to the Box a friend while a slot is free.
    var eggSwapAddsFriend: Bool { state.friendEntryIDs.count < CompanionState.maxFriends }

    /// The Pokémon leaving the raised slot walks with you while a friend slot is free.
    func addFriendIfSlotFree(_ boxID: String) {
        guard eggSwapAddsFriend, let key = state.friendKey(forBoxID: boxID), !state.friendEntryIDs.contains(key) else { return }
        state.friendEntryIDs.append(key)
    }

    @discardableResult
    func detachExpShare(from instanceID: String) -> Bool {
        guard let index = state.expShareHolders.firstIndex(of: instanceID) else { return false }
        state.expShareHolders.remove(at: index)
        state.inventory[ItemKind.expShare.rawValue, default: 0] += 1
        save()
        return true
    }

    /// Every holder as the Box lists it, oldest holder first.
    func expShareHolderIndividuals(in all: [BoxIndividual]? = nil) -> [BoxIndividual] {
        guard !state.expShareHolders.isEmpty else { return [] }
        let all = all ?? boxIndividuals
        return state.expShareHolders.compactMap { id in all.first { $0.id == id } }
    }

    /// Holders whose copy can move onto `target` in one step. Empty when it can't hold one or already does.
    func expShareMoveSources(to target: BoxIndividual, holders: [BoxIndividual]) -> [BoxIndividual] {
        guard Self.canHoldExpShare(target.role), !holdsExpShare(target.id) else { return [] }
        return holders
    }

    func expShareMoveSources(to instanceID: String) -> [BoxIndividual] {
        let all = boxIndividuals
        guard let target = all.first(where: { $0.id == instanceID }) else { return [] }
        return expShareMoveSources(to: target, holders: expShareHolderIndividuals(in: all))
    }

    /// Moves the copy `source` holds onto `target`. What either has banked stays with it.
    @discardableResult
    func moveExpShare(from source: String, to target: String) -> Bool {
        guard expShareMoveSources(to: target).contains(where: { $0.id == source }),
              let index = state.expShareHolders.firstIndex(of: source) else { return false }
        state.expShareHolders.remove(at: index)
        state.expShareHolders.append(target)
        save()
        Task { await checkExpShareEvolution() }
        return true
    }

    /// A graduate holder levels and builds `graduateXP` like the raised graduate; a stored line banks the share in
    /// its stage and takes the steps that open by themselves (`evolveStoredLineIfReady`).
    private func creditExpShareHolders(_ share: Int, skipping raisingIDs: Set<String>) {
        guard share > 0 else { return }
        for id in state.expShareHolders where !raisingIDs.contains(id) {
            if let stored = state.storedLines[id] {
                var mon = stored.mon
                mon.usedAtStage = min(SaveTransfer.maxTokenValue, mon.usedAtStage + share)
                state.storedLines[id]?.mon = reconciledProfileGrowth(mon)
                if let line = expShareLines[mon.baseID] { _ = evolveStoredLineIfReady(id: id, in: line) }
            } else if let index = state.dex.firstIndex(where: { $0.id == id && !$0.isReleased }) {
                creditExpShareGraduate(at: index, share)
            }
        }
    }

    private func creditExpShareGraduate(at index: Int, _ share: Int) {
        growGraduate(at: index, by: share)
        let entry = state.dex[index]
        guard let line = expShareLines[entry.baseID] else { return }
        if var progress = state.graduateEvolution[entry.id] {
            progress.graduateXP += share
            state.graduateEvolution[entry.id] = progress
        } else if !graduateOptions(entry, in: line).isEmpty {
            var progress = EvolutionProgress(spentBaseline: state.spentTokens)
            progress.graduateXP = share
            state.graduateEvolution[entry.id] = progress
        }
        _ = evolveGraduateIfReady(id: entry.id, in: line, celebrate: false)
    }

    private var expShareGraduates: [DexEntry] {
        let raisingIDs = Set([state.raisedEntry?.id, state.active?.profile?.instanceID].compactMap { $0 })
        return state.expShareHolders.filter { !raisingIDs.contains($0) && state.storedLines[$0] == nil }
            .compactMap { id in state.dex.first { $0.id == id && !$0.isReleased } }
    }

    private var expShareStoredLines: [(id: String, baseID: Int)] {
        state.expShareHolders.compactMap { id in state.storedLines[id].map { (id, $0.mon.baseID) } }
    }

    /// Loads each holder's line once, then takes any step that is open now (a clock gate opens on its own).
    func checkExpShareEvolution() async {
        let baseIDs = Set(expShareGraduates.map(\.baseID)).union(expShareStoredLines.map(\.baseID))
        for baseID in baseIDs where expShareLines[baseID] == nil {
            guard loadingExpShareLines.insert(baseID).inserted else { continue }
            defer { loadingExpShareLines.remove(baseID) }
            if let line = try? await dexNameLine(baseID: baseID) { expShareLines[baseID] = line }
        }
        var evolved = false
        for entry in expShareGraduates {
            guard let line = expShareLines[entry.baseID] else { continue }
            if evolveGraduateIfReady(id: entry.id, in: line, celebrate: false) { evolved = true }
        }
        for holder in expShareStoredLines {
            guard let line = expShareLines[holder.baseID] else { continue }
            if evolveStoredLineIfReady(id: holder.id, in: line) { evolved = true }
        }
        if evolved { save() }
        moveIdleExpShares()
    }

    /// The step a stored line takes in the Box now: the one the raised line would choose, through a path that asks
    /// nothing of the player. Nil while it waits.
    private func storedLineStep(_ stored: StoredLine, in line: EvoLine) -> (node: EvoNode, next: EvoNode, replans: Bool)? {
        let mon = stored.mon
        let threshold = stageThreshold(for: mon)
        guard line.baseID == mon.baseID, mon.usedAtStage >= threshold, mon.dittoDisguise == nil || mon.dittoRevealed,
              !holdsEverstone(mon.profile?.instanceID), let node = line.tree.node(withID: mon.currentID) else { return nil }
        let options = growthOptions(of: node, gender: mon.profile?.gender)
        guard !options.isEmpty else { return nil }
        let step = lineStep(of: mon, at: node, among: options)
        guard EvolutionRules.pathOpenByItself(into: step.next.speciesID, in: storedLineContext(stored)) != nil else {
            return nil
        }
        return (node, step.next, step.replans)
    }

    /// Takes every step a stored holder can take in the Box. It never graduates there. The caller saves.
    private func evolveStoredLineIfReady(id: String, in line: EvoLine) -> Bool {
        var evolved = false
        for _ in 0..<5 {
            guard let stored = state.storedLines[id], let step = storedLineStep(stored, in: line) else { break }
            var mon = stored.mon
            if step.replans {
                mon.plannedPathIDs = replannedPath(from: step.node, to: step.next, base: mon)
                mon.totalForms = mon.plannedPathIDs.count
            }
            completeStoredEvolution(id: id, mon, to: step.next, in: line, spentAtStore: stored.spentAtStore)
            evolved = true
        }
        return evolved
    }

    /// Like `completeEvolution` without the Home celebration; the released Pokédex record follows the new species.
    private func completeStoredEvolution(id: String, _ a: MonState, to next: EvoNode, in line: EvoLine, spentAtStore: Int) {
        var mon = a
        mon.pathIDs = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [next.speciesID]
        mon.stageIndex += 1
        mon.usedAtStage = a.usedAtStage - stageThreshold(for: a)
        mon.evolution = a.evolution.nextForm(spentBaseline: spentAtStore)
        if let details = pokemonDetailsByID[next.speciesID] {
            mon.profile?.enrich(with: details)
        } else if detailProvider != nil {
            Task { await self.loadPokemonDetails(speciesID: next.speciesID) }
        }
        state.storedLines[id]?.mon = mon
        if let index = state.dex.firstIndex(where: { $0.id == id && $0.isReleased }) {
            state.dex[index].chainOrder = Array(mon.pathIDs.prefix(mon.stageIndex + 1))
            state.dex[index].finalID = next.speciesID
            Self.mergeNames(of: line, into: &state.dex[index])
        }
        if let companion = EvolutionRules.companions[next.speciesID] {
            registerCompanion(companion, evolvedFrom: a, in: line)
        }
        let oldName = formDisplayName(line.localizedName(a.currentID, state.language), speciesID: a.currentID, form: a.form)
        let newName = formDisplayName(line.localizedName(next.speciesID, state.language), speciesID: next.speciesID,
                                      form: a.form)
        notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(from: oldName, to: newName))
    }

    /// Spending while it waits in the Box does not count toward its gate (`resumeStoredLine`).
    func storedLineContext(_ stored: StoredLine) -> EvolutionContext {
        var context = evolutionContext(for: stored.mon)
        context.spentTokens = stored.spentAtStore
        return context
    }

    /// The step a stored line waits on in the Box and what it still lacks, for its Box page. Without a loaded line
    /// (it holds no Exp. Share) the step is its planned one.
    func storedLineGate(id: String) -> (rule: EvolutionRule, context: EvolutionContext)? {
        guard let stored = state.storedLines[id] else { return nil }
        guard holdsExpShare(id), let line = expShareLines[stored.mon.baseID],
              let node = line.tree.node(withID: stored.mon.currentID) else {
            guard let rule = plannedStoredStep(stored.mon), !rule.paths.isEmpty else { return nil }
            return (rule, storedLineContext(stored))
        }
        let mon = stored.mon
        let options = growthOptions(of: node, gender: mon.profile?.gender)
        let traits = evolutionTraits(of: mon)
        let nextIndex = mon.stageIndex + 1
        let planned = mon.plannedPathIDs.indices.contains(nextIndex)
            ? options.first { $0.speciesID == mon.plannedPathIDs[nextIndex] } : nil
        guard let target = planned ?? EvolutionRules.plannable(options, traits: traits).first else { return nil }
        let timed = EvoNode.resolvingTimeOfDay(target, among: options, at: DayPeriod.at(clock()))
        let next = EvolutionRules.resolvingSelector(timed, among: options, traits: traits)
        guard let rule = EvolutionRules.rule(for: next.speciesID), !rule.paths.isEmpty else { return nil }
        return (rule, storedLineContext(stored))
    }

    private static func mergeNames(of line: EvoLine, into entry: inout DexEntry) {
        var names = entry.names ?? [:]
        for id in entry.chainOrder {
            if let incoming = line.names[id], !incoming.isEmpty {
                names[id] = (names[id] ?? [:]).merging(incoming) { _, new in new }
            }
        }
        entry.names = names.isEmpty ? nil : names
        entry.namesVersion = entry.chainOrder.allSatisfy { line.names[$0]?.isEmpty == false }
            ? DexEntry.currentNamesVersion : nil
    }

    /// The same individual (id, profile, shininess, held item) becomes the next species; the old one stays in
    /// its chain, so the Pokédex still counts it.
    private func evolveGraduate(at index: Int, to speciesID: Int, in line: EvoLine, progress: EvolutionProgress,
                                celebrate: Bool) {
        var entry = state.dex[index]
        let fromID = entry.finalID
        if !entry.chainOrder.contains(speciesID) { entry.chainOrder.append(speciesID) }
        entry.finalID = speciesID
        Self.mergeNames(of: line, into: &entry)
        if let details = pokemonDetailsByID[speciesID] {
            entry.profile?.enrich(with: details)
        } else if detailProvider != nil {
            Task { await self.loadPokemonDetails(speciesID: speciesID) }
        }
        state.dex[index] = entry
        state.collectedFinals.insert("\(entry.baseID):\(speciesID)")
        state.graduateEvolution[entry.id] = progress.nextForm(spentBaseline: state.spentTokens)
        state.reconcileRepresentativeSelection()
        let oldName = formDisplayName(line.localizedName(fromID, state.language), speciesID: fromID, form: entry.form)
        let newName = formDisplayName(line.localizedName(speciesID, state.language), speciesID: speciesID, form: entry.form)
        if celebrate {
            justEvolvedTo = newName
            fireCelebration(.evolve)
            eventUntil = clock().addingTimeInterval(4)
        }
        notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(from: oldName, to: newName))
    }

    /// The progress record the raised Pokémon's next step reads: the line's, or the evolving graduate's.
    private var raisedEvolutionProgress: EvolutionProgress? {
        if hasActive { return state.active!.evolution }
        if let id = raisedGraduate?.id, let saved = state.graduateEvolution[id] { return saved }
        guard evolvingGraduate != nil else { return nil }
        return EvolutionProgress(spentBaseline: state.spentTokens)
    }

    private func setRaisedEvolutionProgress(_ progress: EvolutionProgress) {
        if hasActive {
            state.active!.evolution = progress
        } else if let id = raisedGraduate?.id, state.graduateEvolution[id] != nil || evolvingGraduate != nil {
            state.graduateEvolution[id] = progress
        }
    }

    /// A gate may be waiting for what just happened (a pet, a friend, a gesture): run the stage check again.
    func reevaluateEvolution() {
        if raisedGraduate != nil {
            evolveRaisedGraduateIfReady()
            save()
            return
        }
        guard let a = state.active, !isLineParked, currentLine != nil, a.usedAtStage >= stageThreshold(for: a) else {
            save()
            return
        }
        applyUsage(0)
    }

    func recordPet() {
        guard var progress = raisedEvolutionProgress else { return }
        progress.pets += 1
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func recordFlip() {
        guard var progress = raisedEvolutionProgress, !progress.flipped else { return }
        progress.flipped = true
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func recordSpin() {
        guard var progress = raisedEvolutionProgress, !progress.spun else { return }
        progress.spun = true
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func recordTokenRain() {
        guard var progress = raisedEvolutionProgress, !progress.rained else { return }
        progress.rained = true
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func chooseTower(_ tower: String) {
        guard var progress = raisedEvolutionProgress, progress.tower == nil else { return }
        progress.tower = tower
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    func recordBattle(key: String, result: EvolutionRequirement.Tally) {
        guard var progress = raisedEvolutionProgress else { return }
        progress.record(battle: key, result: result)
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    /// Reads the bot's recent-battle list. Only battles after the cursor count; the first read just sets it.
    func syncBattles(_ battles: [BattleInfo.RecentBattle]) {
        guard var progress = raisedEvolutionProgress else { return }
        guard let cursor = progress.battleCursor else {
            progress.battleCursor = clock()
            setRaisedEvolutionProgress(progress)
            save()
            return
        }
        var newest = cursor
        for battle in battles.sorted(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) {
            guard let date = battle.date, date > cursor else { continue }
            newest = max(newest, date)
            let key = "\(battle.at ?? "")|\(battle.opponentName ?? "")|\(battle.result)"
            let result: EvolutionRequirement.Tally = battle.isWin ? .won : (battle.result == "loss" ? .lost : .played)
            progress.record(battle: key, result: result)
        }
        progress.battleCursor = newest
        setRaisedEvolutionProgress(progress)
        reevaluateEvolution()
    }

    enum EvolutionGesture: Equatable { case flip, spin }

    /// Gestures the waiting step still asks for; the Home sprite offers them in its context menu.
    var evolutionGestures: [EvolutionGesture] {
        guard let pending = pendingEvolutionGate(), let progress = raisedEvolutionProgress else { return [] }
        let requirements = pending.rule.paths.flatMap { $0 }
        var gestures: [EvolutionGesture] = []
        if requirements.contains(.flipped), !progress.flipped { gestures.append(.flip) }
        if requirements.contains(.spun), !progress.spun { gestures.append(.spin) }
        return gestures
    }

    /// Children growth reaches by itself. Item-only forms (an apple, an armor) are reached by using the item.
    func growthOptions(of node: EvoNode, gender: PokemonGender?) -> [EvoNode] {
        EvolutionRules.growthChildren(node.children(for: gender))
    }

    private func evolutionTraits(of mon: MonState) -> EvolutionTraits? {
        mon.profile.map { EvolutionTraits(seed: $0.seed, ivs: $0.ivs, nature: mon.nature) }
    }

    private func pickPlannedChild(_ node: EvoNode, baseID: Int, gender: PokemonGender?,
                                  traits: EvolutionTraits?) -> EvoNode {
        let options = EvolutionRules.plannable(growthOptions(of: node, gender: gender), traits: traits)
        let fresh = options.filter { ch in
            ch.finalIDs(for: gender).contains { !state.collectedFinals.contains("\(baseID):\($0)") }
        }
        let pool = fresh.isEmpty ? options : fresh
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    private func makeEvolutionPlan(from root: EvoNode, baseID: Int, gender: PokemonGender?,
                                   traits: EvolutionTraits? = nil) -> [Int] {
        var plan = [root.speciesID]
        var node = root
        while !growthOptions(of: node, gender: gender).isEmpty {
            let next = pickPlannedChild(node, baseID: baseID, gender: gender, traits: traits)
            plan.append(next.speciesID)
            node = next
        }
        return plan
    }

    static func repairedPlan(realizedPath: [Int], stageIndex: Int, fallbackRoute: [Int]) -> [Int] {
        guard !realizedPath.isEmpty else { return fallbackRoute }
        let currentIndex = min(stageIndex, realizedPath.count - 1)
        let prefix = Array(realizedPath.prefix(currentIndex + 1))
        guard fallbackRoute.first == prefix.last else { return prefix }
        return prefix + fallbackRoute.dropFirst()
    }

    /// 루트부터 실제로 이어지는 가장 긴 ID 경로와 마지막 유효 노드. 첫 ID가 루트와 다르면 루트로 복구한다.
    private func longestValidPath(_ ids: [Int], from root: EvoNode,
                                  gender: PokemonGender?) -> (path: [Int], lastNode: EvoNode) {
        var path = [root.speciesID]
        var node = root
        guard ids.first == root.speciesID else { return (path, node) }
        for id in ids.dropFirst() {
            guard let child = node.children(for: gender).first(where: { $0.speciesID == id }) else { break }
            path.append(id)
            node = child
        }
        return (path, node)
    }

    /// 저장된 실제 경로와 계획을 현재 에셋 트리에 맞춘다. 완전한 계획만 재사용해 재시작 시 RNG를 소비하지 않는다.
    private func normalizedEvolutionState(_ saved: MonState, from root: EvoNode) -> MonState {
        var normalized = saved
        let gender = saved.profile?.gender
        // Evolutions already taken stay, whatever the gender rules say now.
        let realized = longestValidPath(saved.pathIDs, from: root, gender: nil)
        let candidate = longestValidPath(saved.plannedPathIDs, from: root, gender: gender)
        let aheadIsItemOnly = candidate.path.dropFirst(realized.path.count).contains {
            EvolutionRules.rule(for: $0)?.isItemOnly == true
        }
        let canReusePlan = candidate.path == saved.plannedPathIDs
            && candidate.path.starts(with: realized.path)
            && growthOptions(of: candidate.lastNode, gender: gender).isEmpty
            && !aheadIsItemOnly
        let plan: [Int]
        if canReusePlan {
            plan = candidate.path
        } else {
            let suffix = makeEvolutionPlan(from: realized.lastNode, baseID: saved.baseID, gender: gender,
                                           traits: evolutionTraits(of: saved))
            plan = realized.path + suffix.dropFirst()
        }
        normalized.pathIDs = realized.path
        normalized.plannedPathIDs = plan
        normalized.stageIndex = realized.path.count - 1
        normalized.totalForms = plan.count
        return normalized
    }

    /// Returns the new dex entry's id.
    @discardableResult
    private func graduate() -> String? {
        guard var a = state.active else { return nil }
        a.profile?.advanceGrowth(to: PokemonBalance.graduationTotal(a.rarity), rarity: a.rarity)
        if let details = pokemonDetailsByID[a.currentID] { a.profile?.enrich(with: details) }
        let finalID = a.currentID
        let entryID = a.profile?.instanceID ?? UUID().uuidString
        state.collectedFinals.insert("\(a.baseID):\(finalID)")
        state.dex.append(DexEntry(id: entryID,
                                  baseID: a.baseID, finalID: finalID,
                                  chainOrder: a.pathIDs, rarity: a.rarity, caughtAt: clock(),
                                  isShiny: a.isShiny, nature: a.nature,
                                  profile: a.profile,
                                  names: currentLine.map { line in   // 체인 각 종의 다국어 이름 저장(표시 즉시)
                                      Dictionary(uniqueKeysWithValues:
                                          a.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
                                  }, form: a.form, prayers: a.prayers))
        let name = formDisplayName(currentLine?.localizedName(finalID, state.language) ?? "",
                                   speciesID: finalID, form: a.form)
        justGraduated = name
        notifyCompanionEvent(l.notifGraduateTitle, l.notifGraduateBody(name))
        eventUntil = clock().addingTimeInterval(6)
        state.active = nil
        cheerSeq += 1
        state.reconcileRepresentativeSelection()   // 졸업 체인이 dex 로 옮겨져 선택은 정상적으로 유지된다
        activeGeneration += 1
        currentLine = nil
        state.eggUsage = 0   // 새 알은 처음부터 인큐베이션
        state.resetEggPrayers()
        isHatchRetryDelayed = false
        // eggTier 는 손대지 않는다 — 여기 도달했다는 건 활성 포켓몬이 있었다는 뜻이라 보증은 이미 nil 이다
        // (부화가 소비, 디스크/불러오기는 sanitized 가 정규화). 소비 지점은 hatchCore 한 곳으로 유지한다.
        // "알을 받는 순간" 즉시 프리패칭 시작 — 다음 부화의 종·라인·스프라이트 예열.
        Task { await self.ensureEggPrefetch() }
        return entryID
    }

    // MARK: 인벤토리 / 이상한 사탕

    var rareCandyCount: Int { itemCount(.rareCandy) }
    func itemCount(_ kind: ItemKind) -> Int { state.inventory[kind.rawValue] ?? 0 }
    /// 이로치 부적 보유 여부 — 보유형이라 개수>0 = 소유(부화 shiny 분모를 낮춘다).
    var ownsShinyCharm: Bool { itemCount(.shinyCharm) > 0 }

    /// 소유 아이템(개수>0) — 가방 목록. 정렬은 ItemKind.allCases 순서.
    var ownedItems: [(kind: ItemKind, count: Int)] {
        ItemKind.allCases.compactMap { k in
            let c = itemCount(k)
            return c > 0 ? (k, c) : nil
        }
    }

    func ownedItems(in category: ItemCategory?) -> [(kind: ItemKind, count: Int)] {
        guard let category else { return ownedItems }
        return ownedItems.filter { $0.kind.category == category }
    }

    /// The bag's flat list for a chip. In the held tab and the all view, battle items move to `ownedBattleSections`.
    func bagListItems(in category: ItemCategory?) -> [(kind: ItemKind, count: Int)] {
        let items = ownedItems(in: category)
        guard category == nil || category == .heldItem else { return items }
        return items.filter { $0.kind.battleGroup == nil }
    }

    var ownedBattleSections: [BattleItemSection] { BattleItemGroup.sections(of: ownedItems.map(\.kind)) }

    // MARK: 지닌 도구 (개체에 달았다 뗀다 — 다는 동안 가방에서 빠지고 떼면 돌아온다)

    func heldItem(of instanceID: String) -> ItemKind? {
        state.heldItems[instanceID].flatMap(ItemKind.init(rawValue:))
    }

    func holdsEverstone(_ instanceID: String?) -> Bool {
        instanceID.map { heldItem(of: $0) == .everstone } ?? false
    }

    /// `kind` 를 `instanceID` 에 단다. 이미 다른 도구를 들고 있으면 그건 가방으로 돌아온다.
    /// 가방에 없거나 지닌 도구가 아니거나 가진 개체가 아니면 false.
    @discardableResult
    func equip(_ kind: ItemKind, to instanceID: String) -> Bool {
        kind.isEquippable && equip(inventoryKey: kind.rawValue, to: instanceID)
    }

    @discardableResult
    func equip(_ stone: MegaStone, to instanceID: String) -> Bool {
        equip(inventoryKey: stone.inventoryKey, to: instanceID)
    }

    private func equip(inventoryKey key: String, to instanceID: String) -> Bool {
        guard !isTradeLocked(instanceID), state.inventory[key, default: 0] > 0,
              state.ownedInstanceIDs.contains(instanceID) else { return false }
        if state.heldItems[instanceID] == key { return true }
        let megaBefore = megaSpriteID(ofInstance: instanceID)
        if let previous = state.heldItems[instanceID] { state.inventory[previous, default: 0] += 1 }
        state.inventory[key, default: 0] -= 1
        state.heldItems[instanceID] = key
        announceMegaChange(of: instanceID, from: megaBefore)
        reevaluateEvolution()
        return true
    }

    private func megaSpriteID(ofInstance instanceID: String) -> Int? {
        let species = state.dex.first { $0.id == instanceID && $0.releasedAt == nil }?.finalID
            ?? (state.active?.profile?.instanceID == instanceID ? state.active?.currentID : nil)
        return megaSpriteID(instanceID: instanceID, speciesID: species)
    }

    private func announceMegaChange(of instanceID: String, from before: Int?) {
        let after = megaSpriteID(ofInstance: instanceID)
        guard before != after, let sprite = after ?? before else { return }
        megaEvolveCounter += 1
        megaEvolveEvent = MegaEvolveEvent(id: megaEvolveCounter, kind: after == nil ? .unequip : .equip,
                                          instanceID: instanceID, megaSpriteID: sprite, at: Date())
    }

    // MARK: 메가스톤 (포켓몬마다 한 개 — 키 `mega-stone:<slug>`)

    func megaStoneCount(_ stone: MegaStone) -> Int { state.inventory[stone.inventoryKey] ?? 0 }

    /// 가방의 메가스톤 — 도감 번호 순.
    func ownedMegaStones(in category: ItemCategory? = nil) -> [(stone: MegaStone, count: Int)] {
        guard category == nil || category == .megaStone else { return [] }
        return MegaStone.all.compactMap { stone in
            let count = megaStoneCount(stone)
            return count > 0 ? (stone, count) : nil
        }
    }

    func heldMegaStone(of instanceID: String) -> MegaStone? {
        state.heldItems[instanceID].flatMap(MegaStone.stone(inventoryKey:))
    }

    /// 이 개체가 `speciesID` 로서 들고 있는 메가스톤 — 종이 맞을 때만 메가진화한다.
    func megaStone(of instanceID: String, speciesID: Int) -> MegaStone? {
        heldMegaStone(of: instanceID).flatMap { $0.speciesID == speciesID ? $0 : nil }
    }

    /// The bag plus every Pokémon holding it. The shop sells a stone only while this is zero.
    func megaStoneOwnedTotal(_ stone: MegaStone) -> Int {
        megaStoneCount(stone) + state.heldItems.values.filter { $0 == stone.inventoryKey }.count
    }

    func canBuy(_ stone: MegaStone) -> Bool {
        megaStoneOwnedTotal(stone) == 0 && availableTokens >= price(of: .megaStone(stone))
    }

    @discardableResult
    func buy(_ stone: MegaStone) -> Bool {
        guard canBuy(stone) else { return false }
        completePurchase(key: stone.inventoryKey, count: 1, cost: price(of: .megaStone(stone)))
        return true
    }

    // MARK: 기술머신 (기술마다 한 개 — 키 `tm:<moveID>`, 소모되지 않는다)

    func ownsTM(_ moveID: Int) -> Bool { (state.inventory[MachineMove.inventoryKey(moveID)] ?? 0) > 0 }

    func tmPrice(power: Int, isWeather: Bool) -> Int {
        PokemonBalance.scaled(PokemonBalance.machinePrice(power: power, isWeather: isWeather), by: shopDifficulty)
    }

    func canBuyTM(power: Int, isWeather: Bool) -> Bool { availableTokens >= tmPrice(power: power, isWeather: isWeather) }

    @discardableResult
    func buyTM(moveID: Int, power: Int, isWeather: Bool) -> Bool {
        guard !ownsTM(moveID), canBuyTM(power: power, isWeather: isWeather) else { return false }
        completePurchase(key: MachineMove.inventoryKey(moveID), count: 1, cost: tmPrice(power: power, isWeather: isWeather))
        return true
    }

    /// Gives the TM for free (battle rewards). False when it is already owned.
    @discardableResult
    func grantTM(moveID: Int) -> Bool {
        guard !ownsTM(moveID) else { return false }
        state.inventory[MachineMove.inventoryKey(moveID)] = 1
        save()
        return true
    }

    /// 상점 메가스톤 목록 — 가진 포켓몬의 돌이 먼저, 나머지는 도감 번호 순.
    var megaStoneShopEntries: [ShopEntry] {
        let owned = state.ownedSpeciesIDs
        let (mine, others) = (MegaStone.all.filter { owned.contains($0.speciesID) }, MegaStone.all.filter { !owned.contains($0.speciesID) })
        let crystal = ShopEntry.item(.stellarCrystal)
        let stones = (mine + others).map(ShopEntry.megaStone)
        let crystalIndex = owned.contains(TeraForm.terapagos) ? mine.count : stones.count
        return Array(stones[..<crystalIndex]) + [crystal] + Array(stones[crystalIndex...])
    }

    /// 홈·플로팅 펫·메뉴바가 그릴 메가 스프라이트 id. 표시만 바꾼다 — 종·레벨·저장 데이터는 그대로다.
    func megaSpriteID(instanceID: String?, speciesID: Int?) -> Int? {
        guard let instanceID, let speciesID else { return nil }
        return megaStone(of: instanceID, speciesID: speciesID)?.spriteID
            ?? teraForm(of: instanceID, speciesID: speciesID)?.id
    }

    /// The form a mask or the Stellar Crystal gives this individual — only on its own species.
    func teraForm(of instanceID: String, speciesID: Int) -> TeraForm.Sprite? {
        guard let kind = heldItem(of: instanceID), kind.holderSpeciesID == speciesID else { return nil }
        return kind.formSprite
    }

    /// The bag plus every Pokémon holding it.
    func itemOwnedTotal(_ kind: ItemKind) -> Int {
        if kind == .expShare { return itemCount(kind) + state.expShareHolders.count }
        return itemCount(kind) + state.heldItems.values.filter { $0 == kind.rawValue }.count
    }

    /// An item the shop sells once: a bought passive item, or a single-copy item that is in the bag or on a holder.
    func isSoldOut(_ kind: ItemKind) -> Bool {
        (kind.isBoughtOnce && itemCount(kind) > 0) || (kind.isSingleCopy && itemOwnedTotal(kind) > 0)
            || (kind == .expShare && itemOwnedTotal(kind) >= ExpShare.maxOwned)
    }

    /// 그 종의 개체 중 맞는 메가스톤을 든 개체가 있으면 그 메가 스프라이트 id.
    func megaSpriteID(forSpecies speciesID: Int) -> Int? {
        var holders = state.dex.filter { $0.releasedAt == nil && $0.finalID == speciesID }.map(\.id)
        if state.active?.currentID == speciesID, let id = state.active?.profile?.instanceID { holders.append(id) }
        return holders.lazy.compactMap { self.megaSpriteID(instanceID: $0, speciesID: speciesID) }.first
    }

    /// 지금 키우는 개체가 메가진화 중으로 보일 때의 스프라이트 id.
    var currentMegaSpriteID: Int? {
        megaSpriteID(instanceID: raisedGraduate?.id ?? state.active?.profile?.instanceID, speciesID: currentSpeciesID)
    }

    @discardableResult
    func unequip(from instanceID: String) -> Bool {
        guard !isTradeLocked(instanceID), let key = state.heldItems[instanceID] else { return false }
        let megaBefore = megaSpriteID(ofInstance: instanceID)
        state.inventory[key, default: 0] += 1
        state.heldItems[instanceID] = nil
        announceMegaChange(of: instanceID, from: megaBefore)
        if key == ItemKind.everstone.rawValue { reevaluateEvolution() } else { save() }
        return true
    }

    /// 가방에 아이템이 있는 분류 — 빈 분류는 탭에서 숨긴다.
    var bagCategories: [ItemCategory] {
        var present = Set(ownedItems.map { $0.kind.category })
        if !ownedScoutTickets.isEmpty { present.insert(.scout) }
        if !ownedPrizeEggs.isEmpty { present.insert(.egg) }
        if !ownedMegaStones().isEmpty { present.insert(.megaStone) }
        if !ownedBattleSections.isEmpty { present.insert(.heldItem) }
        return ItemCategory.allCases.filter(present.contains)
    }

    /// 이상한 사탕 사용 가능 — 활성 포켓몬 + 라인 로딩 완료 + 재고>0.
    /// 라인 미로딩(재시작 직후·오프라인)이면 비활성 — 사탕이 진화 없이 적립만 되는 것 방지.
    var canUseRareCandy: Bool { maxRareCandyUseCount > 0 }

    /// Use the same rounded, difficulty-adjusted thresholds as actual growth.
    /// Preview the apparent evolution path so hidden identities cannot change the picker.
    private var rareCandyStageCosts: [Int] {
        guard var mon = state.active, !isLineParked, currentLine != nil else { return [] }
        if mon.dittoDisguise != nil && !mon.dittoRevealed && mon.usedAtStage >= stageThreshold(for: mon) {
            // The accepted batch is already saved. Wait for the reveal before accepting another.
            return []
        }
        return (mon.stageIndex..<mon.totalForms).map { stage in
            mon.stageIndex = stage
            return stageThreshold(for: mon)
        }
    }

    var maxRareCandyUseCount: Int {
        let remaining = max(0, rareCandyStageCosts.reduce(0, +) - (state.active?.usedAtStage ?? 0))
        let needed = remaining / RareCandy.xp + (remaining % RareCandy.xp == 0 ? 0 : 1)
        return min(rareCandyCount, needed)
    }

    struct RareCandyUsePlan {
        let count: Int
        var xp: Int { count * RareCandy.xp }
        let evolves: Bool
        let graduates: Bool
        let carryoverXP: Int
        let discardedXP: Int
    }

    func planRareCandyUse(count requested: Int) -> RareCandyUsePlan? {
        let count = min(max(0, requested), maxRareCandyUseCount)
        guard count > 0, let mon = state.active else { return nil }
        let costs = rareCandyStageCosts
        var remaining = mon.usedAtStage + count * RareCandy.xp
        var evolves = false
        for (index, cost) in costs.enumerated() {
            guard remaining >= cost else { break }
            remaining -= cost
            if index == costs.count - 1 {
                return RareCandyUsePlan(count: count, evolves: evolves, graduates: true,
                                       carryoverXP: 0, discardedXP: remaining)
            }
            evolves = true
        }
        return RareCandyUsePlan(count: count, evolves: evolves, graduates: false,
                               carryoverXP: evolves ? remaining : 0, discardedXP: 0)
    }

    /// 사탕 사용 결과 — UI 피드백 분기용.
    enum CandyUseResult: Equatable { case evolved, graduated, progressed, unavailable }

    /// Spend only the candies needed by the current growth plan, preserving unused inventory.
    /// 사탕 XP 는 usedAtStage(진화 진행)에만 반영 — usedSinceInstall/오늘 토큰(실사용 통계)엔 안 잡힌다.
    @discardableResult
    func useRareCandy(count: Int = 1) -> CandyUseResult {
        guard let preview = planRareCandyUse(count: count) else { return .unavailable }
        var consumed = preview.count
        if let mon = state.active, mon.dittoDisguise != nil && !mon.dittoRevealed {
            // Keep the picker indistinguishable from the apparent Pokémon, but preserve whole
            // candies beyond the surprise reveal. Only the last consumed candy's XP carries over.
            let remaining = max(0, stageThreshold(for: mon) - mon.usedAtStage)
            let needed = remaining / RareCandy.xp + (remaining % RareCandy.xp == 0 ? 0 : 1)
            consumed = min(consumed, needed)
        }
        let xp = consumed * RareCandy.xp
        state.inventory[ItemKind.rareCandy.rawValue] = rareCandyCount - consumed
        let beforeStage = state.active?.stageIndex ?? 0
        state.active?.evolution.candies += consumed
        // 진화 안 될 때(부분 진행)도 즉시 "+XP" 피드백 — CompanionHeader 가 연출과 별개로 표시.
        candyFeedbackAmount = xp
        candyFeedbackSeq += 1
        applyUsage(xp)   // Saves inventory and growth together, with existing evolution effects.
        if state.active == nil { return .graduated }
        if state.active!.stageIndex > beforeStage { return .evolved }
        return .progressed
    }

    // MARK: Training items (Mint, Ability Capsule and Patch, Bottle Caps, form tools)

    /// Applies `change` to one individual when it does something; `pay` runs just before the write and may
    /// refuse. Nothing is used up or paid for otherwise. Saves once.
    private func train(_ id: String, pay: () -> Bool, _ change: (inout TrainableIndividual) -> Void) -> TrainingResult {
        guard !isTradeLocked(id), let before = trainable(id: id) else { return .unavailable }
        var after = before
        change(&after)
        guard after != before else { return .unchanged }
        guard pay() else { return .short }
        if state.active?.profile?.instanceID == id {
            state.active?.nature = after.nature
            state.active?.profile = after.profile
            state.active?.form = after.form
        } else if state.storedLines[id] != nil {
            state.storedLines[id]?.mon.nature = after.nature
            state.storedLines[id]?.mon.profile = after.profile
            state.storedLines[id]?.mon.form = after.form
        } else if let index = state.dex.firstIndex(where: { $0.id == id && !$0.isReleased }) {
            state.dex[index].nature = after.nature
            state.dex[index].profile = after.profile
            state.dex[index].form = after.form
        }
        save()
        return .changed
    }

    private func useOne(_ kind: ItemKind) -> Bool {
        guard itemCount(kind) > 0 else { return false }
        state.inventory[kind.rawValue] = itemCount(kind) - 1
        return true
    }

    /// Sets the picked nature with a Mint from the bag, or buys one and uses it in the same step.
    @discardableResult
    func changeNature(of id: String, to nature: PokemonNature) -> TrainingResult {
        let result = train(id, pay: { useOrBuy(.mint, mintPayment) }) { $0.nature = nature }
        if result == .changed, id == homeBoxID {
            mintFeedbackNature = nature
            mintFeedbackSeq += 1
        }
        return result
    }

    /// Unlocks the individual's attacking egg moves with a Mirror Herb from the bag, or buys one and uses it in the
    /// same step.
    @discardableResult
    func useMirrorHerb(on id: String) -> TrainingResult {
        guard let individual = trainable(id: id), EggMoves.hasAttacking(speciesID: individual.speciesID) else {
            return .unavailable
        }
        return train(id, pay: { useOrBuy(.mirrorHerb, mirrorHerbPayment) }) { $0.profile.mirrorHerb = true }
    }

    private func useOrBuy(_ kind: ItemKind, _ payment: MintPayment) -> Bool {
        switch payment {
        case .stock: return useOne(kind)
        case .buy(let price):
            state.spentTokens += price
            return true
        case .short: return false
        }
    }

    @discardableResult
    func useAbilityCapsule(on id: String) -> TrainingResult {
        guard itemCount(.abilityCapsule) > 0, let target = trainable(id: id).flatMap(capsuleTarget) else {
            return .unavailable
        }
        return train(id, pay: { useOne(.abilityCapsule) }) { $0.profile.setAbility(target) }
    }

    @discardableResult
    func useAbilityPatch(on id: String) -> TrainingResult {
        guard itemCount(.abilityPatch) > 0, let target = trainable(id: id).flatMap(patchTarget) else {
            return .unavailable
        }
        return train(id, pay: { useOne(.abilityPatch) }) { $0.profile.setAbility(target) }
    }

    @discardableResult
    func useBottleCap(on id: String, stat: String) -> TrainingResult {
        guard itemCount(.bottleCap) > 0, PokemonStatCalculator.order.contains(stat) else { return .unavailable }
        return train(id, pay: { useOne(.bottleCap) }) { $0.profile.ivs[stat] = BottleCap.maxIV }
    }

    @discardableResult
    func useGoldBottleCap(on id: String) -> TrainingResult {
        guard itemCount(.goldBottleCap) > 0 else { return .unavailable }
        return train(id, pay: { useOne(.goldBottleCap) }) { individual in
            for stat in PokemonStatCalculator.order { individual.profile.ivs[stat] = BottleCap.maxIV }
        }
    }

    /// Switches the individual to `form` with the key item its species needs; the item stays in the bag.
    @discardableResult
    func changeForm(of id: String, to form: PokemonForm) -> TrainingResult {
        guard let individual = trainable(id: id), ownedFormTool(speciesID: individual.speciesID) != nil,
              PokemonForm.forms(speciesID: individual.speciesID).contains(form) else { return .unavailable }
        guard PokemonForm.resolved(speciesID: individual.speciesID, form: individual.form) != form else { return .unchanged }
        return train(id, pay: { true }) { $0.form = form }
    }

    // MARK: 진화의 돌

    /// 돌 사용 결과 — wrongStone 이면 돌은 그대로 남는다.
    enum StoneUseResult: Equatable { case evolved, wrongStone, unavailable, notReady, everstone }

    /// 돌을 쓸 수 있는 상태 — 돌 재고 + 활성 포켓몬 + 라인 로딩 완료(위장 중인 메타몽 제외).
    func canUseStone(_ kind: ItemKind) -> Bool {
        guard kind.isEvolutionStone, itemCount(kind) > 0, let a = state.active, !isLineParked, currentLine != nil else { return false }
        return a.dittoDisguise == nil || a.dittoRevealed
    }

    /// 현재 형태가 이 돌로 진화하는 갈래를 가졌나.
    func stoneFits(_ kind: ItemKind) -> Bool {
        stoneTarget(kind) != nil
    }

    private func stoneTarget(_ kind: ItemKind) -> EvoNode? {
        guard let item = kind.evolutionItemName, let a = state.active, !isLineParked,
              let node = currentLine?.tree.node(withID: a.currentID) else { return nil }
        return node.children(for: a.profile?.gender).first { $0.evolves(withItem: item) }
    }

    /// 돌 1개로 그 돌의 갈래로 바로 진화 — 현재 단계 XP는 그대로 이어진다. 안 맞는 돌이면 소모 없이 wrongStone.
    @discardableResult
    func useEvolutionStone(_ kind: ItemKind) -> StoneUseResult {
        guard canUseStone(kind), let line = currentLine, let a = state.active,
              let node = line.tree.node(withID: a.currentID) else { return .unavailable }
        guard let next = stoneTarget(kind) else { return .wrongStone }
        if holdsEverstone(a.profile?.instanceID) { return .everstone }
        var rest: [EvolutionRequirement] = []
        if let path = EvolutionRules.rule(for: next.speciesID)?.path(usingBag: kind) {
            rest = path.filter { $0 != .bag(kind) }
            let context = evolutionContext(for: a)
            guard rest.allSatisfy({ $0.isMet(in: context) }) else { return .notReady }
        }
        spendEvolutionRequirements(of: rest, instanceID: a.profile?.instanceID)
        state.inventory[kind.rawValue] = itemCount(kind) - 1
        replanEvolution(from: node, to: next, base: a)
        completeEvolution(of: a, to: next, in: line, usedAtStage: a.usedAtStage)
        applyUsage(0)   // 이어받은 XP가 다음 임계를 넘었으면 이어서 진화하고, 저장한다.
        return .evolved
    }

    // MARK: 상점 (재화 = 사용한 토큰)

    /// 상점에서 쓸 수 있는 토큰(재화) = 실사용 누적 − 상점 지출 누적. 성장 미터(usedSinceInstall)는
    /// 여기선 읽기만 — 구매는 spentTokens 만 올려 잔액을 깎는다(진화 진행·오늘/주/월 통계 무영향).
    /// Time-mode credit is wallet income too; it never enters `usedSinceInstall`.
    var availableTokens: Int { max(0, state.usedSinceInstall + state.timeCredit - state.spentTokens) }

    /// 상점 판매 아이템 — shopPrice 있는 것만. 가격 저렴한 순, 단 구매 완료한 보유형은 맨 아래로.
    var purchasableItems: [ItemKind] {
        ItemKind.allCases
            .filter { $0.shopPrice != nil && !$0.isEvolutionStone && !$0.isEvolutionHeld && !$0.isLinkingCord
                && $0.category != .megaStone }
            .sorted { a, b in
                // 구매 완료한 보유형(이로치 부적 등)은 맨 아래로 — 재구매 불가라 위에 있을 이유가 없다.
                let aDone = a.isBoughtOnce && itemCount(a) > 0
                let bDone = b.isBoughtOnce && itemCount(b) > 0
                if aDone != bDone { return !aDone }
                return (a.shopPrice ?? 0) < (b.shopPrice ?? 0)   // 나머지는 가격 저렴한 순
            }
    }

    /// Every battle item by effect group. Metal Coat, Razor Claw and the Stellar Crystal also stay in their own tab.
    var shopBattleSections: [BattleItemSection] { BattleItemGroup.sections(of: ItemKind.allCases) }

    /// 상점 "진화" 구역의 돌 — 별도 구역이라 `shopEntries` 의 가격순 목록에는 넣지 않는다.
    var evolutionStoneItems: [ItemKind] { ItemKind.allCases.filter(\.isEvolutionStone) }

    /// The shop's evolution section: what is used up, the Linking Cord, then what is held.
    var shopEvolutionItems: [ItemKind] {
        evolutionStoneItems + [.linkingCord] + ItemKind.allCases.filter(\.isEvolutionHeld)
    }

    /// The evolution section of the all view; battle items are already listed in `shopBattleSections` there.
    var shopAllViewEvolutionItems: [ItemKind] { shopEvolutionItems.filter { $0.battleGroup == nil } }

    /// 상점 표시 순서 — 판매 아이템 + 알 3종을 하나의 가격 오름차순 목록으로 병합.
    /// 정렬 규칙은 purchasableItems 와 동일: 구매 완료한 보유형은 맨 아래, 나머지는 가격 저렴한 순.
    /// 알은 즉시 액션이라 '보유' 개념이 없어 가격 순서에만 참여한다.
    ///
    /// 알은 활성 포켓몬이 없어도(알 상태) 목록에 남는다 — 구매는 `canBuyEgg` 의 `hasActive` 게이트가
    /// 막고, EggCard 가 비활성 버튼 + 사유 한 줄로 보여준다. 목록에서 통째로 빼면 "상점에 알이 원래
    /// 없다"로 읽혀서, 게이트는 유지하되 존재는 계속 보이게 한다.
    ///
    /// 등급 알끼리 붙여 '티어 사다리'로 묶어 보이게 하는 안도 검토했으나 채택하지 않았다 — 지금의 순수
    /// 가격 오름차순은 "알이 무조건 맨 아래로 append 돼 더 비싼 부적보다 아래에 놓이던" 표시 회귀를
    /// 고치며 들어온 규칙이라(ShopTests 참조), 그룹 배치는 그 회귀를 부분적으로 되살린다. 티어 관계는
    /// 카드의 등급 배지로 읽히게 한다.
    var shopEntries: [ShopEntry] {
        var entries: [ShopEntry] = purchasableItems.map { ShopEntry.item($0) }
        entries += FreshEgg.shopTiers.map { ShopEntry.egg($0) }
        return entries.sorted { a, b in
            let aDone = isPurchasedPassive(a)
            let bDone = isPurchasedPassive(b)
            if aDone != bDone { return !aDone }
            return price(of: a) < price(of: b)
        }
    }

    /// 분류 탭 필터 — nil 은 전체. 순서는 shopEntries 그대로다(가격 오름차순 규칙 유지). 진화의 돌은
    /// 별도 구역(`evolutionStoneItems`)이라 여기에 없다.
    func shopEntries(in category: ItemCategory?) -> [ShopEntry] {
        guard let category else { return shopEntries }
        if category == .megaStone { return megaStoneShopEntries }
        return shopEntries.filter { $0.category == category }
    }

    /// 상점에 항목이 있는 분류 — 빈 분류는 탭에서 숨긴다. 메가스톤 92개·기술머신은 전체 목록에 넣지 않고 각자 탭에서만 판다.
    var shopCategories: [ItemCategory] {
        let present = Set(shopEntries.map(\.category)).union(evolutionStoneItems.map(\.category))
            .union([.scout, .megaStone, .machine])
        return ItemCategory.allCases.filter(present.contains)
    }

    /// 구매 완료한 보유형(이로치 부적 등)인지 — shopEntries 정렬에서 맨 아래로 보낼 판정.
    private func isPurchasedPassive(_ entry: ShopEntry) -> Bool {
        guard case .item(let kind) = entry else { return false }   // 알은 즉시 액션 — 보유 개념 없음
        return kind.isBoughtOnce && itemCount(kind) > 0
    }

    /// 구매 가능 — 잔액이 그 아이템 가격 이상(상점 미판매면 false). 활성/알 무관(재고는 미리 쌓아둘 수 있음).
    func canBuy(_ kind: ItemKind) -> Bool {
        guard let price = price(of: kind) else { return false }
        if isSoldOut(kind) { return false }   // 보유형·단품은 1회만(재구매 불가)
        return availableTokens >= price
    }

    /// 한 번에 살 수 있는 최대 개수 — 잔액 ÷ 가격. 보유형은 1회 구매라 최대 1, 이미 보유했거나
    /// 미판매·잔액 부족이면 0.
    func maxBuyCount(_ kind: ItemKind) -> Int {
        guard canBuy(kind), let price = price(of: kind), price > 0 else { return 0 }
        return kind.isBoughtOnce || kind.isSingleCopy || kind == .expShare ? 1 : availableTokens / price
    }

    /// 아이템 count 개 구매 — 지갑에서 price × count 차감, 인벤토리 +count. usedSinceInstall(성장·통계)·
    /// 진화 진행엔 무영향(지출 원장만 증가). 잔액 부족/미판매/범위 밖 개수면 부분 구매 없이 no-op(false).
    @discardableResult
    func buy(_ kind: ItemKind, count: Int = 1) -> Bool {
        guard count >= 1, count <= maxBuyCount(kind), let price = price(of: kind) else { return false }
        completePurchase(key: kind.rawValue, count: count, cost: price * count)
        return true
    }

    // MARK: 구매 되돌리기 (확인창 대신 5초 안에 취소)

    /// Purchases that can still be taken back, by inventory key (one per shop row). A row shows its entry for
    /// `PurchaseReceipt.window` seconds; the view calls `dismissReceipt` when that ends.
    private(set) var purchaseReceipts: [String: PurchaseReceipt] = [:]

    private func completePurchase(key: String, count: Int, cost: Int) {
        state.spentTokens += cost
        state.inventory[key, default: 0] += count
        purchaseReceipts[key] = PurchaseReceipt(inventoryKey: key, count: count, cost: cost,
                                                expiresAt: clock().addingTimeInterval(PurchaseReceipt.window))
        save()
    }

    /// Undo is open while the window lasts and the bought copies are still in the bag — an item that was
    /// equipped, used or traded away in the meantime cannot be refunded.
    func canUndo(_ receipt: PurchaseReceipt) -> Bool {
        clock() < receipt.expiresAt && purchaseReceipts[receipt.inventoryKey] == receipt
            && state.inventory[receipt.inventoryKey, default: 0] >= receipt.count
    }

    /// Gives the exact cost back and takes the copies out of the bag. False (nothing changes) when `canUndo` is false.
    @discardableResult
    func undoPurchase(_ receipt: PurchaseReceipt) -> Bool {
        guard canUndo(receipt) else { return false }
        state.spentTokens = max(0, state.spentTokens - receipt.cost)
        let left = state.inventory[receipt.inventoryKey, default: 0] - receipt.count
        state.inventory[receipt.inventoryKey] = left > 0 ? left : nil
        purchaseReceipts[receipt.inventoryKey] = nil
        save()
        return true
    }

    func dismissReceipt(_ receipt: PurchaseReceipt) {
        if purchaseReceipts[receipt.inventoryKey] == receipt { purchaseReceipts[receipt.inventoryKey] = nil }
    }

    // 사탕 전용 래퍼 — 기존 호출부/테스트 호환.
    var canBuyRareCandy: Bool { canBuy(.rareCandy) }
    @discardableResult
    func buyRareCandy() -> Bool { buy(.rareCandy) }

    // MARK: 알 (현재 포켓몬은 박스로, 도감·확률 무영향)

    /// 현재 알이 보증하는 등급 하한(UI 표시용). 활성 포켓몬이 있으면 알이 없으므로 nil.
    var eggGuarantee: Rarity? { isEgg ? state.eggTier : nil }

    /// 알 구매 가능 — 박스로 보낼 활성 포켓몬이 있고 지갑이 그 티어 가격 이상일 때만.
    /// 알 상태에서는 살 수 없다 — 알끼리 교체하는 동작은 만들지 않는다.
    /// 항목 자체는 알 상태에서도 상점에 남는다(shopEntries) — 이 게이트는 구매만 막는다.
    func canBuyEgg(_ tier: Rarity?) -> Bool {
        // 파는 티어인지 먼저 확인한다 — 만족 불가능한 보증(전설: capture_rate 로 표현 불가)을 사면
        // 두 롤 경로 모두 후보가 0개라 알이 영영 안 깨지고, 부화가 없으니 보증도 안 풀리며,
        // 새 알 구매는 `hasActive` 에 막혀 되돌릴 수단이 없다. 가격만 계산되면 값이 빠져나가므로
        // 판매 목록을 여기서 강제한다(호출부 하나가 실수하면 토큰이 통째로 사라진다).
        guard FreshEgg.shopTiers.contains(tier) else { return false }
        return hasActive && availableTokens >= price(of: .egg(tier))
    }

    /// 알 구매 — 현재 포켓몬을 박스로 보내고 처음부터 인큐베이션하는 새 알로. 지갑에서 가격 차감.
    /// `collectedFinals`(최종체 완성·분기 가중)는 손대지 않는다 — 끝까지 키운 게 아니다.
    ///
    /// 여기서 종을 롤하지 않는다 — 롤에는 네트워크가 필요해서 오프라인이면 토큰만 사라진다. 보증만
    /// 상태(`eggTier`)에 적고, 실제 롤은 프리패치/부화 경로가 그 보증을 읽어 수행한다.
    @discardableResult
    func buyEgg(_ tier: Rarity?) -> Bool {
        guard canBuyEgg(tier) else { return false }
        state.spentTokens += price(of: .egg(tier))
        storeActiveForNewEgg(tier: tier, pendingHatchID: nil)
        return true
    }

    /// 활성 포켓몬을 박스로 보내고 처음부터 인큐베이션하는 새 알로 — 상점 알과 스카우트가 같이 쓴다.
    /// `pendingHatchID` 가 있으면(스카우트) 그 종으로 미리 정해 두고 메타몽 위장도 끈다.
    func storeActiveForNewEgg(tier: Rarity?, pendingHatchID: Int?, shiny: Bool = false, attachesBagCopy: Bool = true) {
        if let storedID = storeActiveInBox() {
            addFriendIfSlotFree(storedID)
            if attachesBagCopy { attachExpShare(to: storedID) }
        }
        state.reconcileRepresentativeSelection()
        activeGeneration += 1
        currentLine = nil
        state.eggUsage = 0            // 새 알은 처음부터 인큐베이션(재부화에 부화 임계만큼 필요)
        state.resetEggPrayers()
        isHatchRetryDelayed = false
        state.eggTier = tier          // 등급 보증(nil = 보증 없음)
        state.pendingHatchID = pendingHatchID   // nil 이면 새 보증으로 처음부터 롤(활성 포켓몬이 있는 동안엔 원래 비어 있다)
        state.pendingForm = pendingHatchID.flatMap { shiny ? PokemonForm.lineForms(baseID: $0).first : rollLineForm(baseID: $0) }
        state.scoutedEgg = pendingHatchID != nil
        state.shinyEgg = shiny
        prefetchedLineID = nil
        justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        AppLog.write("egg purchased: active stored in the Box, tier=\(tier?.rawValue ?? "none") scouted=\(pendingHatchID.map(String.init) ?? "no")")
        Task { await self.ensureEggPrefetch() }   // 다음 부화 예열
        save()
    }

    // MARK: 스카우트 (티켓 → 후보 10종 → 하나 골라 그 종의 알)

    func scoutTicketCount(_ pool: ScoutPool) -> Int { max(0, state.inventory[pool.inventoryKey] ?? 0) }

    /// 가방에 든 티켓 — 지역 순서(전국 마지막).
    var ownedScoutTickets: [(pool: ScoutPool, count: Int)] {
        ScoutPool.all.compactMap { pool in
            let count = scoutTicketCount(pool)
            return count > 0 ? (pool, count) : nil
        }
    }

    var scoutPrice: Int { PokemonBalance.scaled(ScoutTicket.price, by: shopDifficulty) }
    var canBuyScoutTicket: Bool { availableTokens >= scoutPrice }

    @discardableResult
    func buyScoutTicket(_ pool: ScoutPool) -> Bool {
        guard canBuyScoutTicket else { return false }
        completePurchase(key: pool.inventoryKey, count: 1, cost: scoutPrice)
        return true
    }

    /// 이 티켓으로 이미 뽑아 둔 후보. 없으면 nil.
    func scoutDraw(for pool: ScoutPool) -> [Int]? {
        guard scoutTicketCount(pool) > 0, let ids = state.scoutDraws[pool.key], !ids.isEmpty else { return nil }
        return ids
    }

    /// 후보를 돌려준다 — 이미 뽑아 둔 게 있으면 그대로, 없으면 알이 쓰는 가중치로 10종을 뽑아 저장한다.
    /// 티켓은 여기서 쓰지 않는다(고를 때 쓴다). 종 인덱스를 못 받으면 nil — 티켓은 그대로다.
    func drawScout(_ pool: ScoutPool) async -> [Int]? {
        guard scoutTicketCount(pool) > 0 else { return nil }
        if let existing = scoutDraw(for: pool) { return existing }
        guard let full = try? await provider.baseSpeciesIndex() else { return nil }
        // await 사이에 다른 호출이 먼저 뽑았거나 티켓이 줄었을 수 있다.
        guard scoutTicketCount(pool) > 0 else { return nil }
        if let existing = scoutDraw(for: pool) { return existing }
        let candidates = full.filter { pool.dexRange.contains($0.id) && PokemonAssets.isSupported(speciesID: $0.id) }
        let drawn = SpeciesRoll.drawDistinct(from: candidates, count: ScoutTicket.drawSize,
                                             isCollected: { state.hasCollectedFinal(forBaseID: $0) }, rng: &rng)
        guard !drawn.isEmpty else { return nil }
        state.scoutDraws[pool.key] = drawn
        save()
        return drawn
    }

    /// 고르기는 박스로 보낼 포켓몬이 있을 때만 — 알 상태에서 알을 바꾸는 동작은 상점 알과 같은 이유로 만들지 않는다.
    var canPickScout: Bool { hasActive }

    /// 고른 종의 알로 바꾼다 — 티켓 1장과 그 풀의 후보를 지운다. 현재 포켓몬은 박스로 간다.
    @discardableResult
    func pickScout(_ pool: ScoutPool, speciesID: Int) -> Bool {
        guard canPickScout, scoutTicketCount(pool) > 0, scoutDraw(for: pool)?.contains(speciesID) == true else { return false }
        state.inventory[pool.inventoryKey] = scoutTicketCount(pool) - 1
        state.scoutDraws[pool.key] = nil
        storeActiveForNewEgg(tier: nil, pendingHatchID: speciesID)
        return true
    }

    // MARK: Hidden boss prize eggs

    func prizeEggCount(speciesID: Int) -> Int {
        max(0, state.inventory[HiddenBossPrize.eggKey(speciesID)] ?? 0)
    }

    /// Prize eggs in the bag, in prize-table order.
    var ownedPrizeEggs: [(speciesID: Int, count: Int)] {
        HiddenBossPrize.all.compactMap { prize in
            let count = prizeEggCount(speciesID: prize.eggSpeciesID)
            return count > 0 ? (prize.eggSpeciesID, count) : nil
        }
    }

    /// Same gate as a scout pick: the active Pokémon goes to the Box to make room for the egg.
    var canHatchPrizeEgg: Bool { hasActive }

    @discardableResult
    func hatchPrizeEgg(speciesID: Int) -> Bool {
        guard canHatchPrizeEgg, prizeEggCount(speciesID: speciesID) > 0 else { return false }
        state.inventory[HiddenBossPrize.eggKey(speciesID)] = prizeEggCount(speciesID: speciesID) - 1
        storeActiveForNewEgg(tier: nil, pendingHatchID: speciesID, shiny: true)
        return true
    }

    /// 후보 한 칸의 표시 정보 — 종 인덱스(이름·타입·전설 여부)가 있어야 만든다.
    struct ScoutPick: Identifiable {
        let species: DexSpecies
        let types: [String]
        var id: Int { species.id }
    }

    func scoutPicks(_ ids: [Int]) -> [ScoutPick] {
        guard let speciesIndex else { return [] }
        return ids.compactMap { id in
            guard let entry = speciesIndex.entry(id), let rarity = speciesIndex.rarity(of: id) else { return nil }
            let species = DexSpecies(id: id, name: state.language.resolveName(entry.names) ?? "#\(id)",
                                     rarity: rarity, isShiny: false, isRaising: false,
                                     names: entry.names, isOwned: state.ownsSpecies(id))
            return ScoutPick(species: species, types: entry.types)
        }
    }

    // MARK: 클릭 성장

    enum ClickGrowthResult: Equatable { case counted(Int), tooSoon }

    /// In memory only: a restart allows one extra click inside the interval, which is harmless.
    private var lastCountedClickAt: Date?

    /// One click or pat on the pet. Grows the egg or Pokémon like tokens do, at most once per `ClickGrowth.minInterval`.
    @discardableResult
    func growByClick() -> ClickGrowthResult {
        let now = clock()
        if let last = lastCountedClickAt, now.timeIntervalSince(last) < ClickGrowth.minInterval { return .tooSoon }
        lastCountedClickAt = now
        let xp = ClickGrowth.tokensPerClick
        state.clickGrowth += xp
        if state.raisedEntry != nil {
            recordPet()
            creditRaisedGraduate(xp)
            save()
        } else if state.active == nil {
            state.eggUsage += xp
            save()
            if state.eggUsage >= eggHatchThreshold { Task { await hatchIfNeeded() } }
        } else {
            recordPet()
            applyUsage(xp)
        }
        return .counted(xp)
    }

    /// Pray over the egg. A placebo: it only counts, and never touches an RNG or a roll — the species is
    /// usually already in `pendingHatchID` (prefetched at purchase) long before anyone prays.
    func pray() {
        guard state.active == nil, state.raisedEntry == nil else { return }
        var record = state.eggPrayers ?? PrayerRecord(count: 0)
        record.count += 1
        state.eggPrayers = record
        save()
    }

    // 보증 없는 기본 알 래퍼 — 기존 호출부/테스트 호환.
    var canBuyFreshEgg: Bool { canBuyEgg(nil) }
    @discardableResult
    func buyFreshEgg() -> Bool { buyEgg(nil) }

    /// Parse an epoch string into a Date, supporting Unix timestamp (seconds or ms) or ISO8601 strings.
    static func parseEpochDate(_ string: String) -> Date? {
        if let ts = Double(string) {
            if ts > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: ts / 1000.0)
            } else if ts > 100_000_000 {
                return Date(timeIntervalSince1970: ts)
            }
        }
        return ISO8601Parser.date(from: string)
    }

    /// Determines if a new epoch represents an actual window advancement (reset) rather than
    /// volatile network jitter (e.g. Codex ±1s) or fractional-second differences (Claude microseconds).
    /// For session windows (≈5h), requires advancing forward by at least 30 minutes.
    /// For weekly windows (7d), requires advancing forward by at least 24 hours.
    /// Non-date strings (used in synthetic unit tests) fall back to string inequality.
    static func isNewEpoch(previous: String, current: String, kind: WindowClass) -> Bool {
        guard previous != current else { return false }
        guard let dPrev = parseEpochDate(previous), let dCurr = parseEpochDate(current) else {
            return true
        }
        let delta = dCurr.timeIntervalSince(dPrev)
        let minAdvance: TimeInterval = kind == .weekly ? 86400 : 1800
        return delta >= minAdvance
    }

    /// 지급 판정(순수·엣지 트리거) — 한도 창이 100% 를 새로 넘어선 순간에만 지급.
    /// - 100% 미만 → 맵에서 제거(재무장).
    /// - 같은 key 라도 epoch(`resets_at`)가 바뀌면 새 창으로 보고 재무장 — 슬립·종료로 &lt;100% 샘플을
    ///   못 본 채 다시 100%만 관측해도 지급 누락이 없다(#326). key 자체엔 epoch 를 넣지 않는다
    ///   (알림 dedup 과 같은 이유로 매 fetch 새 키 폭탄 방지).
    /// - epoch 없는 창(Codex)은 100% 미만 관측으로만 재무장한다.
    /// - 이미 지급한 창(tier≥1)은 재지급 안 함. session=1개·weekly=weeklyGrant.
    /// - 부수효과(인벤토리·알림)와 분리해 xctest 가능. (evaluateLimitAlerts 자매)
    static func evaluateCandyGrants(
        windows: [CandyWindow],
        grantTier: inout [String: Int],
        windowEpoch: inout [String: String]
    ) -> [CandyGrant] {
        var grants: [CandyGrant] = []
        for w in windows {
            if let epoch = w.epoch {
                if let previousEpoch = windowEpoch[w.key] {
                    if isNewEpoch(previous: previousEpoch, current: epoch, kind: w.kind) {
                        grantTier[w.key] = nil
                        windowEpoch[w.key] = epoch
                    }
                } else {
                    windowEpoch[w.key] = epoch
                }
            }
            guard w.utilization >= 100 else {
                grantTier[w.key] = nil
                if let epoch = w.epoch {
                    windowEpoch[w.key] = epoch
                }
                continue
            }
            let previous = grantTier[w.key] ?? 0
            guard previous < 1 else { continue }
            grantTier[w.key] = 1
            if let epoch = w.epoch {
                windowEpoch[w.key] = epoch
            }
            let count = w.kind == .weekly ? RareCandy.weeklyGrant : 1
            grants.append(CandyGrant(windowKey: w.key, windowName: w.name, count: count))
        }
        return grants
    }

    /// 한도 창 상태로부터 사탕 지급(엣지·영속). AppDelegate 가 매 refresh 완료 시(한도 로드 후) 호출.
    /// - 첫 실행: 현재 100% 창을 지급 없이 tier 시드만 → 이후 "새로 넘어서는" 순간부터 지급(소급 차단).
    /// - limitsReady=false(한도 미로딩)면 시드/지급 모두 대기(다음 refresh 에 재시도).
    func grantCandies(from windows: [CandyWindow], limitsReady: Bool) {
        guard limitsReady else { return }
        if !state.candyFeatureSeeded {
            // 한계(수용): 첫 refresh 에 한 프로바이더 한도만 로드되면 그 프로바이더 창만 시드된다.
            // 이후 다른 프로바이더가 이미 100%인 채 로드되면 소급 지급될 수 있으나, 1회·소수 캔디라
            // 1인 로컬에서 무시(YAGNI). refresh() 는 전 프로바이더 fetch 를 await 후 onRefresh 하므로
            // 정상 경로(둘 다 성공)에선 원자적 시드다.
            for w in windows where w.utilization >= 100 {
                state.candyGrantTier[w.key] = 1
                if let epoch = w.epoch { state.candyWindowEpoch[w.key] = epoch }
            }
            state.candyFeatureSeeded = true
            save()
            return
        }
        let beforeTier = state.candyGrantTier
        let beforeEpoch = state.candyWindowEpoch
        var grantTier = state.candyGrantTier
        var windowEpoch = state.candyWindowEpoch
        let grants = Self.evaluateCandyGrants(
            windows: windows,
            grantTier: &grantTier,
            windowEpoch: &windowEpoch)
        state.candyGrantTier = grantTier
        state.candyWindowEpoch = windowEpoch
        for g in grants {
            state.inventory[ItemKind.rareCandy.rawValue, default: 0] += g.count
            // 지급 자체는 알림 여부와 무관(상태 변경). 알림은 "왜 받는지"(그 창 한도를 다 채운 수고) 명시.
            notifyCompanionEvent(l.notifCandyTitle(item: l.itemName(.rareCandy), count: g.count),
                                 l.notifCandyBody(window: g.windowName), showsOnPet: false)
        }
        // 지급이 없어도 재무장(util dip / epoch 교체)은 영속해야 한다 —
        // 안 하면 재시작 시 stale tier=1 로 다음 100% 도달이 "이미 지급"으로 오판돼 지급 누락(회귀).
        if !grants.isEmpty
            || state.candyGrantTier != beforeTier
            || state.candyWindowEpoch != beforeEpoch {
            save()
        }
    }

    /// companion 이벤트 시스템 알림(.app + 토글 ON 일 때만). 한도 알림과 독립.
    private var notifSeq = 0
    /// The newest hatch / evolution / graduation / Ditto line; the floating pet pops it once. Recorded before the
    /// bundled-app guard below so a dev build (no system notifications) shows it too.
    /// `seq` tells a new event from one already shown, even when two share a clock instant.
    struct CompanionEvent: Equatable { let seq: Int; let text: String; let at: Date }
    private(set) var latestEvent: CompanionEvent?
    private var eventSeq = 0

    func notifyCompanionEvent(_ title: String, _ body: String, showsOnPet: Bool = true) {
        if showsOnPet {
            eventSeq += 1
            latestEvent = CompanionEvent(seq: eventSeq, text: body, at: clock())
        }
        guard AppEnv.isBundledApp else { return }
        guard UserDefaults.standard.object(forKey: "companionNotifications") as? Bool ?? true else { return }
        notifSeq += 1
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "companion-event-\(notifSeq)", content: content, trigger: nil))
    }

    // MARK: 부화

    func hatchIfNeeded() async {
        guard state.active == nil, state.raisedEntry == nil, !isHatching, state.eggUsage >= eggHatchThreshold else { return }
        // 프리패치가 "종 롤 중"(pending 미확정)일 때만 대기 — 이중 rng 소비 방지.
        // pending 확정 후의 예열(라인/스프라이트)과는 동시 진행해도 안전하다.
        guard state.pendingHatchID != nil || !prefetchInFlight else { return }
        // isHatching 을 롤~부화 전체에 defer 로 잠근다. 과거엔 chooseBase 후 isHatching 을 잠깐
        // 내렸다가(hatch 자체 가드 통과용) hatch 를 호출해, 그 await 창에서 다른 update 틱이
        // 두 번째 종을 롤하는 경합이 있었다. hatchCore 는 isHatching 을 재검사하지 않으므로
        // 여기서 소유한 락 하나로 롤·부화가 원자적으로 보호된다.
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        // 프리패칭된 종이 있으면 그대로 사용(라인·스프라이트 예열됨 → 딜레이 ~0), 없으면 지금 롤.
        let base: Int?
        if let pending = state.pendingHatchID {
            base = pending
        } else {
            base = await chooseBase()
        }
        guard isCurrentReadyEgg(generation: generation) else {
            AppLog.write("hatch: discarded before result handling — subject replaced during species roll")
            kickLineLoadIfNeeded()
            return
        }
        guard let base else {
            isHatchRetryDelayed = true
            return
        }
        let pendingForm = state.pendingHatchID == base ? state.pendingForm : nil
        await hatchCore(baseID: base, generation: generation, form: pendingForm)
    }

    /// 부화가 폐기된 뒤 남은 개체(대개 방금 불러온 개체)의 진화 라인을 다시 로드한다.
    /// `loadCurrentLine` 은 `!isHatching` 을 요구하므로 부화 중에 걸린 로드는 조용히 실패한다 —
    /// 아무도 재시도하지 않으면 다음 update 틱(기본 120초)까지 이름이 "Token Egg" 로 남는다.
    /// Task 본문은 현재 동기 실행(= defer 로 isHatching 해제)이 끝난 뒤 돌므로 락이 이미 풀려 있다.
    private func kickLineLoadIfNeeded() {
        guard state.active != nil, currentLine == nil else { return }
        Task { await loadCurrentLine() }
    }

    // MARK: 알 프리패칭

    private var prefetchInFlight = false
    private var prefetchedLineID: Int?   // 라인·스프라이트 예열 완료한 종(세션 메모리)

    private func isCurrentEgg(generation: Int) -> Bool {
        activeGeneration == generation && state.active == nil && state.raisedEntry == nil
    }

    private func isCurrentReadyEgg(generation: Int) -> Bool {
        isCurrentEgg(generation: generation) && state.eggUsage >= eggHatchThreshold
    }

    private func markHatchRetryDelayedIfReady(generation: Int) {
        guard isCurrentReadyEgg(generation: generation) else { return }
        isHatchRetryDelayed = true
    }

    private func finishEggPrefetch(generation: Int, shouldHatch: Bool) {
        prefetchInFlight = false
        guard shouldHatch, isCurrentReadyEgg(generation: generation) else { return }
        Task { await self.hatchIfNeeded() }
    }

    /// 알 상태에서 부화를 미리 준비 — ① 종 pre-roll(pendingHatchID, 영속) ② 진화 라인
    /// fetch(provider 캐시 적재) ③ 스프라이트 예열(정적+애니메이션+shiny 애니메이션).
    /// 전부 성공하면 부화 순간 네트워크 0. 실패 지점부터 다음 update 틱에 이어서 재시도.
    private func ensureEggPrefetch() async {
        guard state.active == nil, state.raisedEntry == nil, !isHatching, !prefetchInFlight else { return }
        let generation = activeGeneration
        var shouldHatch = false
        prefetchInFlight = true
        defer { finishEggPrefetch(generation: generation, shouldHatch: shouldHatch) }

        if state.pendingHatchID == nil {
            let selected = await chooseBase()
            // await 사이에 부화가 끝났거나(active != nil) 상태가 통째로 교체됐으면(세이브 불러오기)
            // 이 롤을 버린다 — 안 그러면 불러온 알의 pre-roll 을 남의 롤로 덮어쓴다.
            guard isCurrentEgg(generation: generation) else { return }
            guard let id = selected else {
                markHatchRetryDelayedIfReady(generation: generation)
                return
            }
            state.pendingHatchID = id
            state.pendingForm = rollLineForm(baseID: id)
            save()
        }
        guard let id = state.pendingHatchID else { return }
        if prefetchedLineID == id {
            isHatchRetryDelayed = false
            shouldHatch = true
            return
        }
        let form = state.pendingForm
        let line: EvoLine
        do {
            line = try await provider.line(baseSpeciesID: id)
        } catch {
            markHatchRetryDelayedIfReady(generation: generation)
            return
        }
        guard isCurrentEgg(generation: generation), state.pendingHatchID == id else { return }
        // 스프라이트 예열 — 부화 직후 보일 것들: base 정적+애니메이션, shiny 롤(1/64) 대비 shiny 애니메이션.
        // .app 번들에서만(단위 테스트가 실네트워크에 닿지 않도록 — 알림과 동일한 게이트).
        if AppEnv.isBundledApp {
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: false, shiny: false, form: form)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: false, form: form)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: true, form: form)
            if PokemonForm.hasForms(speciesID: line.baseID) {
                _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: false, shiny: true, form: form)
            }
            await loadFormNames(baseID: line.baseID, form: form)
        }
        guard isCurrentEgg(generation: generation), state.pendingHatchID == id else { return }
        prefetchedLineID = id
        isHatchRetryDelayed = false
        shouldHatch = true
    }

    /// Draws only for lines with forms, so other species keep their random sequence.
    private func rollLineForm(baseID: Int) -> PokemonForm? {
        let forms = PokemonForm.lineForms(baseID: baseID)
        guard !forms.isEmpty else { return nil }
        return PokemonForm.roll(rng.next(), among: forms, collected: state.collectedLineForms(baseID: baseID))
    }

    /// Warms the localized names the hatch, evolution and graduation messages of this line show.
    private func loadFormNames(baseID: Int, form: PokemonForm?) async {
        await loadFormNames(PokemonForm.formSpecies(baseID: baseID).compactMap {
            PokemonForm.nameResource(speciesID: $0, form: form)
        })
    }

    /// The raised Pokémon's form names, for its title and its evolution and graduation messages.
    func loadActiveFormNames() async {
        if let graduate = raisedGraduate {
            await loadFormNames(baseID: graduate.baseID, form: graduate.form)
        } else if let active = state.active {
            await loadFormNames(baseID: active.baseID, form: active.form)
        }
    }

    func loadFormNames(_ resources: [PokemonNameResource]) async {
        for resource in Set(resources) {
            _ = await PokemonNameDisplayStore.shared.load(resource, provider: PokemonNameClient.shared)
        }
    }

    func formDisplayName(_ name: String, speciesID: Int, form: PokemonForm?) -> String {
        PokemonForm.displayName(name, speciesID: speciesID, form: form, language: state.language)
    }

    func hatch(baseID: Int) async {
        guard !isHatching, state.raisedEntry == nil else { return }
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        await hatchCore(baseID: baseID, generation: generation)
    }

    // MARK: 메타몽 위장/리빌

    /// 메타몽 위장 롤 판정(순수) — common·≥2형태만, 미리 뽑은 roll 값으로 1/128. (부수효과 없이 xctest)
    nonisolated static func dittoDisguiseHit(rarity: Rarity, totalForms: Int, roll: UInt64) -> Bool {
        rarity == .common && totalForms >= 2 && roll % PokemonOdds.dittoDisguiseDenominator == 0
    }

    /// 이로치 부화 분모 — 부적 보유 48, 없으면 64. 판정과 알림 문구가 같은 값을 쓰도록 여기가 단일 소스다.
    nonisolated static func shinyDenominator(charmOwned: Bool) -> UInt64 {
        charmOwned ? ShinyCharm.shinyDenominator : PokemonOdds.shinyDenominator
    }

    /// 지금 부화하면 적용될 이로치 분모.
    var shinyDenominator: UInt64 { Self.shinyDenominator(charmOwned: ownsShinyCharm) }

    /// 이로치 부화 판정(순수) — 미리 뽑은 roll 값 % 분모==0. (부수효과 없이 xctest)
    nonisolated static func rollsShiny(roll: UInt64, charmOwned: Bool) -> Bool {
        roll % shinyDenominator(charmOwned: charmOwned) == 0
    }

    /// 실제 부화 로직 — isHatching 락은 호출자(hatch / hatchIfNeeded)가 소유·해제한다.
    private func hatchCore(baseID: Int, generation: Int, form pendingForm: PokemonForm? = nil) async {
        let line: EvoLine
        do {
            line = try await provider.line(baseSpeciesID: baseID).prunedTradeOnly()
        } catch {
            markHatchRetryDelayedIfReady(generation: generation)
            AppLog.write("hatch: line fetch failed for base \(baseID) — egg kept, retry next tick")
            return
        }
        // 라인 fetch 창(네트워크) 동안 활성 개체가 교체됐으면 이 부화 결과를 폐기한다. 세이브 불러오기가
        // 그 창에 들어오면, 여기서 멈추지 않는 한 갓 부화한 개체가 방금 불러온 개체를 덮어쓴다.
        // (loadCurrentLine·revealDitto 와 같은 세대 가드 — isHatching 락은 같은 앱 내 중복 부화만 막는다.)
        guard activeGeneration == generation else {
            AppLog.write("hatch: discarded — active subject replaced during line fetch")
            kickLineLoadIfNeeded()
            return
        }
        // 산 보증을 지키는 마지막 관문 — 진짜 등급을 아는 건 여기뿐이다(후보 인덱스엔 capture_rate 만
        // 있고 is_legendary 가 없다). 필터가 어긋났으면(인덱스 stale 등) 낮은 등급을 그냥 내주지 말고
        // 알을 유지한 채 pre-roll 만 버려 다음 틱에 다시 뽑는다 — 사용자는 산 보증을 계속 들고 있는다.
        if let tier = state.eggTier, line.rarity.sortRank < tier.sortRank {
            AppLog.write("hatch: rolled \(line.rarity) below guaranteed \(tier) — discarded, re-roll next tick")
            state.pendingHatchID = nil
            state.pendingForm = nil
            prefetchedLineID = nil
            markHatchRetryDelayedIfReady(generation: generation)
            save()
            return
        }
        state.pendingHatchID = nil
        state.pendingForm = nil
        // A later egg can roll the same species with another form and must warm its own sprite.
        prefetchedLineID = nil
        currentLine = line
        isHatchRetryDelayed = false
        // 부화 임계 초과분은 부화체 성장에 이월(낭비 없음).
        let overflow = max(0, state.eggUsage - eggHatchThreshold)
        state.eggUsage = 0
        state.eggTier = nil   // 보증은 이 부화로 소비된다(다음 알은 다시 무보증)
        let scouted = state.scoutedEgg
        state.scoutedEgg = false
        let prizeShiny = state.shinyEgg
        state.shinyEgg = false
        let prayers = state.eggPrayers   // 부화체에 옮기고 알 쪽은 비운다
        state.resetEggPrayers()
        // 개체 롤 — shiny(1/64, 부적 1/48)·성격(25종)은 부화 순간 확정, 진화해도 유지.
        // 알림 문구는 이 판정과 같은 분모를 보여준다.
        let shinyOdds = shinyDenominator
        let isShiny = Self.rollsShiny(roll: rng.next(), charmOwned: ownsShinyCharm) || prizeShiny
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        // 메타몽 위장 롤 — common·≥2형태에 한해 1/128. .app 게이트(&& 단락 → 비앱에선 rng 미소비로
        // 기존 테스트 RNG 시퀀스 무영향). 위장/리빌 로직은 상태 기반으로 별도 테스트한다.
        var dittoDisguise: Int?
        if dittoDisguiseRollingEnabled, !scouted,   // 스카우트로 고른 종이 메타몽으로 바뀌면 산 걸 못 받는다
           Self.dittoDisguiseHit(rarity: line.rarity, totalForms: line.totalForms, roll: rng.next()) {
            dittoDisguise = line.baseID
        }
        // Gender is rolled before the plan: it decides which evolutions the individual can take.
        var profile = PokemonProfile.generate(seed: rng.next())
        if let rate = line.genderRate { profile.assignGender(genderRate: rate) }
        let evolutionPlan = makeEvolutionPlan(
            from: line.tree, baseID: line.baseID, gender: profile.gender,
            traits: EvolutionTraits(seed: profile.seed, ivs: profile.ivs, nature: nature))
        if let details = pokemonDetailsByID[line.baseID] { profile.enrich(with: details) }
        let hasGrowthBoost = state.hasCollectedFinal(forBaseID: line.baseID)
        let form = pendingForm ?? rollLineForm(baseID: line.baseID)
        // 위장 중엔 이로치를 숨긴다 — 부화 알림·연출도 일반체로(정체는 리빌 때 공개).
        let showShiny = isShiny && dittoDisguise == nil
        activeGeneration += 1
        state.active = MonState(baseID: line.baseID, pathIDs: [line.baseID], plannedPathIDs: evolutionPlan,
                                stageIndex: 0, usedAtStage: 0, rarity: line.rarity, totalForms: evolutionPlan.count,
                                isShiny: isShiny, nature: nature, profile: profile, hasGrowthBoost: hasGrowthBoost,
                                dittoDisguise: dittoDisguise, form: form, prayers: prayers, tradeGated: true)
        state.active!.evolution = EvolutionProgress(spentBaseline: state.spentTokens, battleCursor: clock())
        AppLog.write("hatch: base=\(line.baseID) rarity=\(line.rarity) shiny=\(isShiny) forms=\(evolutionPlan.count) boost=\(hasGrowthBoost) ditto=\(dittoDisguise != nil)")
        let name = formDisplayName(line.localizedName(line.baseID, state.language),
                                   speciesID: line.baseID, form: form)
        let hatchBody: String
        if let prayers, prayers.count > 0 {
            hatchBody = l.notifPrayerHatchBody(name, prayers: prayers.count, shiny: showShiny,
                                               rarity: line.rarity)
        } else {
            hatchBody = showShiny ? l.notifShinyHatchBody(name, odds: shinyOdds) : l.notifHatchBody(name)
        }
        notifyCompanionEvent(showShiny ? l.notifShinyHatchTitle : l.notifHatchTitle, hatchBody)
        justEvolvedTo = nil        // 새 부화는 "성장" 문구(진화 아님) — 직전 진화명이 남아 표시되지 않게
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(4)
        if overflow > 0 { applyUsage(overflow) }   // 이월분 즉시 반영(필요 시 진화/리빌까지)
        // 연출은 이월 진화 뒤에 발화 — 이월 evolve 가 shiny 부화 버스트를 덮지 않도록
        // 마지막 이벤트를 hatch 로 유지한다. 이월로 즉시 졸업한 극단 케이스면 생략(이미 도감행).
        if state.active != nil { fireCelebration(.hatch(shiny: showShiny)) }
        save()
        if detailProvider != nil { Task { await self.loadPokemonDetails(speciesID: line.baseID) } }
    }

    /// 위장 → 리빌: 진화 못 하는 메타몽이 "첫 진화 임계"에서 진화 대신 정체를 드러내는 순간.
    /// Ditto 라인 로드 후 상태 변환(rare·단일형태·초과분 이월, isShiny/nature 유지) + 연출·알림.
    private func revealDitto() async {
        guard let a = state.active, a.dittoDisguise != nil, !a.dittoRevealed, !isRevealingDitto else { return }
        let generation = activeGeneration
        let firstEvoThr = stageThreshold(for: a)
        guard a.usedAtStage >= firstEvoThr else { return }   // 임계 미달 방어
        isRevealingDitto = true
        defer { isRevealingDitto = false }
        guard let dittoLine = try? await provider.line(baseSpeciesID: PokemonOdds.dittoSpeciesID) else {
            AppLog.write("ditto reveal: line fetch failed — retry next tick"); return
        }
        guard activeGeneration == generation,
              var m = state.active, m.dittoDisguise != nil, !m.dittoRevealed else { return }
        let latestFirstEvoThr = stageThreshold(for: m)
        guard m.usedAtStage >= latestFirstEvoThr else { return }
        let disguiseName = currentLine?.localizedName(m.baseID, state.language) ?? "#\(m.baseID)"
        let carryOver = max(0, m.usedAtStage - latestFirstEvoThr)   // 위장체 첫 진화 초과분 → 메타몽 성장 이월
        // 메타몽으로 전환 — rarity/forms 는 로드한 라인에서, isShiny/nature/dittoDisguise 는 유지.
        let previousRarity = m.rarity
        m.baseID = dittoLine.baseID
        let evolutionPlan = makeEvolutionPlan(from: dittoLine.tree, baseID: dittoLine.baseID, gender: nil)
        m.pathIDs = [dittoLine.baseID]
        m.plannedPathIDs = evolutionPlan
        m.stageIndex = 0
        m.rarity = dittoLine.rarity
        m.totalForms = evolutionPlan.count
        m.usedAtStage = carryOver
        m.dittoRevealed = true
        m.form = nil
        // The hatch boost came from the disguise's line; from now on only a repeat Ditto earns it.
        m.hasGrowthBoost = state.hasCollectedFinal(forBaseID: dittoLine.baseID)
        m.profile?.rebaseForSpeciesIdentity(from: previousRarity, to: dittoLine.rarity)
        if let details = pokemonDetailsByID[dittoLine.baseID] {
            m.profile?.enrich(with: details)
        }
        let shiny = m.isShiny
        state.active = m
        state.reconcileRepresentativeSelection()   // 위장 종만 근거였던 선택은 리빌과 함께 제거
        currentLine = dittoLine
        AppLog.write("ditto reveal: disguise=\(m.dittoDisguise ?? -1) → ditto rarity=\(dittoLine.rarity) shiny=\(shiny)")
        fireCelebration(.dittoReveal(shiny: shiny))
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(5)
        notifyCompanionEvent(shiny ? l.notifShinyDittoRevealTitle : l.notifDittoRevealTitle,
                             shiny ? l.notifShinyDittoRevealBody(disguiseName) : l.notifDittoRevealBody(disguiseName))
        save()
        applyUsage(0)   // 이월분으로 메타몽 졸업 재평가(rare 3B라 보통 즉시 졸업 아님)
        isRevealingDitto = false   // Details are enrichment, not part of the reveal transaction.
        if detailProvider != nil {
            await loadPokemonDetails(speciesID: PokemonOdds.dittoSpeciesID)
        }
    }

    private func loadCurrentLine() async {
        guard let a = state.active, currentLine == nil, !isHatching else { return }
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        if let fullLine = try? await provider.line(baseSpeciesID: a.baseID) {
            let line = a.tradeGated == true
                ? fullLine.prunedTradeOnly(keeping: Set(a.pathIDs + a.plannedPathIDs)) : fullLine
            // await 중 사용량·민트 등 활성 상태는 계속 바뀔 수 있다. 요청 당시 스냅샷을 다시 쓰지 말고
            // 같은 개체가 아직 활성인 경우에만 최신 상태를 정규화한다.
            guard activeGeneration == generation,
                  var latest = state.active, latest.baseID == a.baseID, currentLine == nil else { return }
            // Old saves rolled gender only once details arrived; settle it before the plan is checked.
            if let rate = line.genderRate { latest.profile?.assignGender(genderRate: rate) }
            state.active = normalizedEvolutionState(latest, from: line.tree)
            state.reconcileRepresentativeSelection()   // 손상 경로 정규화로 사라진 단계가 대표로 남지 않게
            currentLine = line
            save()   // 마이그레이션 선택을 사용량 재평가 전에 영속화해 재시작마다 다시 롤리지 않는다.
            applyUsage(0)   // 라인 미로딩 동안 적립된 사용량이 임계를 넘었으면 지금 진화 판정
            // Path normalization can change currentID without entering the regular evolution branch.
            isHatching = false   // Do not hold the line-load lock across detail HTTP requests.
            // After a relaunch only the popover loads form names; evolution and graduation
            // notifications need them before it is opened.
            if AppEnv.isBundledApp { await loadActiveFormNames() }
            if let speciesID = state.active?.currentID, detailProvider != nil {
                await loadPokemonDetails(speciesID: speciesID)
            }
        }
    }

    /// 부화 종 선정 — 하드코딩 풀 없이 PokéAPI 지원 범위 base 전체에서 가중 선택.
    ///   ① base 인덱스(id + capture_rate)를 GraphQL 1쿼리로 취득(30일 디스크 캐시 → 보통 0콜)
    ///   ② 가중치 = 공식 capture_rate 그대로(캐터피 255 vs 뮤츠 3 = 85:1, 전설군 ≈ 0.77%)
    ///      단, 이미 수집한 base 는 가중치 ½(미수집 부스트 — 재부화/shiny 사냥은 열어둠)
    ///   ③ 누적 가중치에서 정확히 1롤 — 루프/재롤 없음, 시간 상한 확정적
    /// 인덱스 취득 실패(오프라인 + 캐시 없음) 시 nil → 알 유지, 다음 갱신 틱 재시도.
    private func chooseBase() async -> Int? {
        let tier = state.eggTier
        if let full = try? await provider.baseSpeciesIndex(), !full.isEmpty {
            // 등급 보증 알은 후보를 먼저 좁힌다 — capture_rate 상한이 곧 등급 하한이므로
            // (Rarity.captureRateCeiling) 전설도 자연히 포함된다("희귀 이상"에 전설이 들어가는 게 정상).
            // 좁힌 결과가 비면 보증을 못 지키므로 전체 풀로 폴백하지 말고 알을 유지한다(다음 틱 재시도).
            let index = tier.map { t in full.filter { t.includes(captureRate: $0.captureRate) } } ?? full
            guard !index.isEmpty else {
                AppLog.write("hatch: no candidate for guaranteed \(tier?.rawValue ?? "none") — egg kept, retry next tick")
                return nil
            }
            return SpeciesRoll.pick(from: index, isCollected: { state.hasCollectedFinal(forBaseID: $0) }, rng: &rng)?.id
        }
        // GraphQL base 인덱스 엔드포인트 장애 → REST 폴백. 부화가 한 엔드포인트에 묶이지 않게.
        AppLog.write("hatch: base index unavailable — REST fallback")
        return await chooseBaseViaREST()
    }

    /// REST 폴백 — animated 에셋 지원 범위에서 무작위 id 를 뽑아 base 인지 확인(rejection sampling).
    /// GraphQL 인덱스가 죽어도 부화가 되게 한다. 가중치(capture_rate)는 생략 — 희귀도는 부화 후
    /// line() 이 실제 capture_rate 로 계산하므로 결과 개체의 등급은 정확하다. 인덱스 복구 시 가중 선택 재개.
    private func chooseBaseViaREST() async -> Int? {
        let tier = state.eggTier
        for attempt in 1...16 {
            let ids = PokemonAssets.supportedSpeciesIDs
            let id = Int(rng.next() % UInt64(ids.count)) + ids.lowerBound
            do {
                if let bs = try await provider.baseSpecies(id: id) {
                    // 등급 보증은 가중 경로와 **같은 기준**으로 여기서도 걸러야 한다 — 이 폴백만 빠지면
                    // GraphQL 인덱스 장애 때 보증이 조용히 깨진다. 못 찾으면 알 유지(구매 소멸 금지).
                    if let tier, !tier.includes(captureRate: bs.captureRate) { continue }
                    AppLog.write("hatch: REST fallback picked base \(id) (cap \(bs.captureRate), \(attempt) tries)")
                    return id
                }
                // nil = base 아님(진화 중간체) → 다음 시도
            } catch {
                AppLog.write("hatch: REST fallback network error — retry next tick: \(error)")
                return nil   // REST 도 불가 → 알 유지, 다음 update 틱 재시도
            }
        }
        AppLog.write("hatch: REST fallback exhausted 16 tries")
        return nil
    }

    /// Today's total at the previous refresh, and when a rise in it was last seen. The enrichment scan's
    /// `lastUsage` lags a refresh behind, so without this the companion would keep its back turned for a
    /// while after usage resumed. Not persisted: after a launch there is nothing to compare with.
    private var lastSeenToday: (date: String, total: Int)?
    private var lastObservedUsage: Date?

    /// `timeSinceLastUsage`, capped by how long ago this store itself saw today's total rise.
    /// A new day or a first sighting only sets the baseline — it is not usage, so a midnight rollover
    /// neither un-sulks nor sulks by itself. nil stays nil: unknown is never idle.
    private func effectiveIdle(timeSinceLastUsage: TimeInterval?, todayDate: String, todayTokens: Int,
                               hasCurrentProviderData: Bool) -> TimeInterval? {
        if hasCurrentProviderData {
            if let seen = lastSeenToday, seen.date == todayDate, todayTokens > seen.total {
                lastObservedUsage = clock()
            }
            lastSeenToday = (todayDate, todayTokens)
        }
        guard let reported = timeSinceLastUsage else { return nil }
        guard let observed = lastObservedUsage else { return reported }
        return min(reported, max(0, clock().timeIntervalSince(observed)))
    }

    private func computeState(burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool, today: Int,
                              timeSinceLastUsage: TimeInterval? = nil) -> CompanionStateKind {
        if isEgg { return .egg }
        if justGraduated != nil || (eventUntil != nil && clock() < eventUntil!) { return .levelUp }
        if limitWarning { return .tired }
        if state.growthMode == .time { return timeActiveNow ? .working : .sleep }
        if hasUsageData, let idle = timeSinceLastUsage, idle >= PokemonBalance.sulkAfterIdle {
            return .sulk
        }
        if !hasUsageData || today == 0 { return .sleep }
        switch burnTier {
        case .idle: return .idle
        case .normal: return .working
        case .fast, .blazing: return .focus
        }
    }

    // MARK: 세이브 이전 (기기 교체)

    /// 덮어쓰기 확인에 쓸 "이 기기의 현재 진행" 요약.
    var transferSummary: SaveSummary { SaveSummary(state: state) }

    /// 저장 패널에 채울 기본 파일명. 봉투의 `exportedAt` 과 **같은 시계**에서 뽑는다 — 뷰가 따로
    /// `Date()` 를 부르면 파일명 날짜와 내용의 날짜가 갈릴 수 있다(자정 경계).
    var suggestedExportFileName: String { SaveTransfer.suggestedFileName(date: clock()) }

    /// 내보내기 페이로드. 파일 쓰기는 호출자(UI)가 사용자가 고른 위치에 수행한다.
    func exportedSaveData(appVersion: String, deviceName: String) throws -> Data {
        try SaveTransfer.encode(state: state, appVersion: appVersion, deviceName: deviceName, now: clock())
    }

    /// 검증된 세이브를 이 기기에 적용 — 기존 상태 백업 → 기기 기준 재정렬 → 저장 → 라인 재로딩.
    /// 백업을 못 남기면 **적용하지 않고** throw 한다 — 확인창이 "직전 상태가 남는다"고 약속하므로,
    /// 그 약속을 못 지키는 채로 덮어쓰면 사용자는 되돌릴 수단 없이 진행을 잃는다.
    func applySave(_ envelope: SaveEnvelope, todayTokensByProvider: [String: Int], todayDate: String,
                   hasUsageData: Bool) throws {
        try backupStateBeforeImport()
        state = SaveTransfer.rebasedForThisDevice(envelope.state,
                                                  current: state,
                                                  todayTokensByProvider: todayTokensByProvider,
                                                  todayDate: todayDate,
                                                  hasUsageData: hasUsageData)
        // 이전 개체 기준으로 진행 중이던 비동기·연출을 전부 무효화한다. activeGeneration 을 올리지
        // 않으면 먼저 떠 있던 라인 로드가 완료되며 새로 불러온 개체를 덮어쓴다.
        activeGeneration += 1
        timeMeter.reanchor()
        currentLine = nil
        prefetchedLineID = nil
        justEvolvedTo = nil
        justGraduated = nil
        eventUntil = nil
        celebration = nil
        isHatchRetryDelayed = false
        // 이전 개체 기준의 1회성 피드백(사탕 +XP·민트 성격)도 비운다 — 안 비우면 불러온 직후 남의
        // 개체에 대한 "+XP" 가 새 개체 위에 떠오른다.
        candyFeedbackAmount = 0
        mintFeedbackNature = nil
        displayState = isEgg ? .egg : .idle
        migrateEconomyIfNeeded(previousGrowth: legacyGrowthForOldSaves)
        migratePokemonProfilesIfNeeded()
        seedDexCompletionsIfNeeded()
        save()
        if state.active != nil { Task { await loadCurrentLine() } }
        if detailProvider != nil { Task { await preparePokemonProfiles() } }
        AppLog.write("save imported from \(envelope.sourceDevice): dex=\(state.dex.count) lifetime=\(state.usedSinceInstall)")
    }

    /// 덮어쓰기 직전 현재 상태를 옆에 남긴다 — 잘못 불러왔을 때 되돌릴 수단.
    /// 슬롯을 하나만 쓰면 두 번째 불러오기가 **원본**을 덮어써, "잘못 불러왔으니 되돌린다"는 바로 그
    /// 상황에서 되돌릴 대상이 사라진다. 불러올 때마다 새 슬롯을 쓰고 오래된 것부터 정리한다.
    @discardableResult
    private func backupStateBeforeImport() throws -> URL {
        guard let data = try? JSONEncoder().encode(state) else { throw SaveTransferError.backupFailed }
        let dir = fileURL.deletingLastPathComponent()
        let backup = dir.appendingPathComponent(SaveTransfer.backupFileName(date: clock()))
        do {
            try data.write(to: backup, options: .atomic)
        } catch {
            AppLog.write("save import aborted — backup write failed: \(error)")
            throw SaveTransferError.backupFailed
        }
        pruneImportBackups(in: dir)
        return backup
    }

    /// 최근 N 개만 남기고 오래된 백업을 지운다. 파일명이 `yyyy-MM-dd-HHmmss` 라 사전순 = 시간순이다.
    private func pruneImportBackups(in dir: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let backups = names.filter { $0.hasPrefix(SaveTransfer.backupFilePrefix) }.sorted()
        guard backups.count > SaveTransfer.backupsToKeep else { return }
        for stale in backups.dropLast(SaveTransfer.backupsToKeep) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale))
        }
    }

    // MARK: 스냅샷 (로컬 자동 백업 & 복원)

    func refreshSnapshots() {
        availableSnapshots = SaveSnapshotManager.listSnapshots(for: fileURL)
    }

    @discardableResult
    func createManualSnapshot(now: Date? = nil) throws -> SaveSnapshot {
        let timestamp = now ?? clock()
        let snapshot = try SaveSnapshotManager.createSnapshot(
            state: state,
            for: fileURL,
            date: timestamp,
            appVersion: SaveSnapshotManager.defaultAppVersion,
            deviceName: SaveSnapshotManager.defaultDeviceName
        )
        lastAutoSnapshotDate = timestamp
        refreshSnapshots()
        return snapshot
    }

    private var automaticSnapshotInterval: TimeInterval {
        SaveSnapshotManager.minAutoSnapshotInterval
    }

    func autoSnapshotIfNeeded(now: Date? = nil) {
        let timestamp = now ?? clock()
        let newest = availableSnapshots.first

        guard newest == nil ||
              timestamp.timeIntervalSince(newest!.date) >= automaticSnapshotInterval
        else {
            return
        }

        guard state.usedSinceInstall > 0 || !state.dex.isEmpty || state.active != nil else { return }

        _ = try? createManualSnapshot(now: timestamp)
    }

    func restoreSnapshot(
        _ snapshot: SaveSnapshot,
        todayTokensByProvider: [String: Int] = [:],
        todayDate: String = "",
        hasUsageData: Bool = false
    ) throws {
        // Read and validate the selected snapshot before taking the safety snapshot: at the retention
        // limit, that extra file prunes the oldest one, which may be the snapshot being restored.
        // A snapshot that no longer decodes also fails here, before anything is written or pruned.
        let envelope = try SaveSnapshotManager.loadEnvelope(from: snapshot.fileURL)
        _ = try? createManualSnapshot()
        try applySave(envelope,
                      todayTokensByProvider: todayTokensByProvider,
                      todayDate: todayDate,
                      hasUsageData: hasUsageData)
        refreshSnapshots()
        AppLog.write("snapshot restored: \(snapshot.id)")
    }

    // MARK: Pokémon combat profiles / details

    /// Exact current/final individuals for a Pokédex species. Earlier evolution stages remain
    /// species reference pages; the same evolved individual is not duplicated as a second creature.
    func pokemonIndividuals(speciesID: Int, form: PokemonForm? = nil) -> [DexEntry] {
        let form = PokemonForm.resolved(speciesID: speciesID, form: form)
        return dexEntriesSorted.filter {
            $0.finalID == speciesID && $0.profile != nil
                && PokemonForm.resolved(speciesID: speciesID, form: $0.form) == form
        }
    }

    /// Loads immutable PokéAPI metadata and persists any deferred profile fields exactly once.
    func loadPokemonDetails(speciesID: Int) async {
        if let details = pokemonDetailsByID[speciesID] {
            enrichProfiles(for: speciesID, with: details)
            return
        }
        guard let detailProvider, !loadingPokemonDetailIDs.contains(speciesID) else { return }
        loadingPokemonDetailIDs.insert(speciesID)
        failedPokemonDetailIDs.remove(speciesID)
        defer { loadingPokemonDetailIDs.remove(speciesID) }
        do {
            let details = try await detailProvider.pokemonDetails(speciesID: speciesID)
            pokemonDetailsByID[speciesID] = details
            enrichProfiles(for: speciesID, with: details)
        } catch {
            failedPokemonDetailIDs.insert(speciesID)
            AppLog.write("pokemon details fetch failed id=\(speciesID): \(error)")
        }
    }

    /// Startup/background warmup for the only profile needed before a detail page is opened.
    func preparePokemonProfiles() async {
        guard let speciesID = raisedGraduate?.finalID ?? state.active?.currentID else { return }
        await loadPokemonDetails(speciesID: speciesID)
    }

    private func enrichProfiles(for speciesID: Int, with details: PokemonDetails) {
        var changed = false
        if var active = state.active, active.currentID == speciesID, var profile = active.profile {
            let before = profile
            profile.enrich(with: details)
            if profile != before {
                active.profile = profile
                state.active = active
                changed = true
            }
        }
        for index in state.dex.indices where state.dex[index].finalID == speciesID {
            guard var profile = state.dex[index].profile else { continue }
            let before = profile
            profile.enrich(with: details)
            if profile != before {
                state.dex[index].profile = profile
                changed = true
            }
        }
        if changed { save() }
    }

    /// Additive migration for pre-profile saves. It never needs network and therefore cannot block launch.
    /// Deferred fields (gender/ability/moves) are filled after the cached/detail fetch succeeds.
    private func migratePokemonProfilesIfNeeded() {
        var changed = false
        if var active = state.active, active.profile == nil {
            let key = "active:\(active.baseID):\(active.pathIDs.map(String.init).joined(separator: ",")):\(state.lastDate)"
            active.profile = PokemonProfile.generate(seed: PokemonProfileMigration.seed(key))
            state.active = active
            changed = true
        }
        for index in state.dex.indices {
            let entry = state.dex[index]
            if entry.profile == nil {
                let graduated = !entry.isReleased
                // Released entries only persisted their reached `chainOrder`, not the originally
                // planned form count. Treating that count as `totalForms` is the best recoverable
                // estimate, but it is an upper bound when release happened before the planned final.
                let growth = graduated
                    ? PokemonBalance.graduationTotal(entry.rarity)
                    : Self.reconstructedGrowthTokens(
                        rarity: entry.rarity, totalForms: max(1, entry.chainOrder.count),
                        completedStages: max(0, entry.chainOrder.count - 1), currentStageUsage: 0)
                var profile = PokemonProfile.generate(
                    seed: PokemonProfileMigration.seed("dex:\(entry.id):\(entry.finalID)"),
                    growthTokens: growth,
                    instanceID: entry.id)
                profile.applyGrowth(0, rarity: entry.rarity)
                state.dex[index].profile = profile
                changed = true
            }
        }
        let before = state.active?.profile
        reconcileActiveProfileGrowth()
        if !changed {
            if before != state.active?.profile { save() }
            return
        }

        // One recoverable snapshot before the first format expansion. Never overwrite it.
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("companion-state.pre-profiles-v1.json")
        if FileManager.default.fileExists(atPath: fileURL.path),
           !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
        save()
        AppLog.write("pokemon profile migration complete — previous state kept as \(backup.lastPathComponent)")
    }

    /// Completed phases retain their earned credit. Only the current raw phase is repriced
    /// by difficulty/repeat boost; its profile high-water mark prevents level loss.
    private func reconcileActiveProfileGrowth() {
        guard let active = state.active else { return }
        state.active = reconciledProfileGrowth(active)
    }

    private func reconciledProfileGrowth(_ mon: MonState) -> MonState {
        var active = mon
        guard var profile = active.profile else { return mon }
        let completed = Self.reconstructedGrowthTokens(
            rarity: active.rarity, totalForms: active.totalForms,
            completedStages: active.stageIndex, currentStageUsage: 0)
        let standardPhase = PokemonBalance.phaseThreshold(
            rarity: active.rarity, totalForms: active.totalForms, stageIndex: active.stageIndex)
        let fraction = min(1, max(0, Double(active.usedAtStage) / Double(max(1, stageThreshold(for: active)))))
        let candidate = min(PokemonBalance.graduationTotal(active.rarity),
                            completed + Int((Double(standardPhase) * fraction).rounded(.down)))
        profile.advanceGrowth(to: candidate, rarity: active.rarity)
        if let details = pokemonDetailsByID[active.currentID] { profile.enrich(with: details) }
        active.profile = profile
        return active
    }

    static func reconstructedGrowthTokens(rarity: Rarity, totalForms: Int,
                                          completedStages: Int, currentStageUsage: Int) -> Int {
        let forms = max(1, totalForms)
        let completed = min(max(0, completedStages), forms)
        let completedGrowth = (0..<completed).reduce(0) { total, stage in
            total + PokemonBalance.phaseThreshold(rarity: rarity, totalForms: forms, stageIndex: stage)
        }
        return min(SaveTransfer.maxTokenValue,
                   completedGrowth + min(SaveTransfer.maxTokenValue, max(0, currentStageUsage)))
    }

    // MARK: 교환

    /// The newest trade arrival or Linking Cord evolution, shown once by the popover banner.
    struct TradeArrival: Equatable, Identifiable {
        let id: Int
        let entryID: String
        /// Nil for a Linking Cord evolution, which has no trade partner.
        let fromName: String?
        let receivedID: Int
        /// The sender's wording until the evolution line is known.
        var receivedName: String
        var evolvedID: Int?
        var evolvedName: String?
        let isShiny: Bool
    }
    private(set) var tradeArrival: TradeArrival?
    @ObservationIgnored private var tradeArrivalSeq = 0
    @ObservationIgnored private var isResolvingTradeEvolutions = false

    func dismissTradeArrival() { tradeArrival = nil }

    enum TradeEvolutionResult: Equatable { case evolved, noEvolution, notReady, unavailable, everstone }
    /// `wrongTarget` and `notReady` (it evolves by trade, but the item or friend it needs is missing) leave the
    /// cord in the bag.
    /// `listed`: the individual is in an open trade, and a cord evolution would use up the item the trade carries.
    enum CordUseResult: Equatable { case evolved, wrongTarget, notReady, unavailable, listed, everstone }

    private static let appliedTradeLimit = 200
    /// An offer lives 24 hours on the bot; a lock the bot stops reporting is dropped at the next sync, and one it
    /// can no longer report (bot unreachable) lapses with the offer.
    private static let tradeLockLifetime: TimeInterval = 24 * 3600

    /// Individuals in an open trade, each locked until the time shown. Their item slot stays as it was when the
    /// offer was made, because that item travels with the Pokémon.
    private(set) var tradeLocks: [String: Date] = [:]

    func isTradeLocked(_ instanceID: String) -> Bool {
        tradeLocks[instanceID].map { $0 > clock() } ?? false
    }

    func lockForTrade(_ instanceID: String) {
        tradeLocks[instanceID] = clock().addingTimeInterval(Self.tradeLockLifetime)
    }

    func setTradeLocked(_ ids: Set<String>) {
        let expiry = clock().addingTimeInterval(Self.tradeLockLifetime)
        tradeLocks = Dictionary(uniqueKeysWithValues: ids.map { ($0, expiry) })
    }

    func tradePool(fightingIDs: Set<String>) -> [TradePoolEntry] {
        TradePool.build(state: state, fightingIDs: fightingIDs, name: dexEntryName)
    }

    func tradeRefusal(for entry: DexEntry, fightingIDs: Set<String>) -> TradeRefusal? {
        if state.storedLines[entry.id] != nil { return .unavailable }
        return TradePool.refusal(for: entry, fightingIDs: fightingIDs, activeID: activeDexEntry?.id,
                          raisedID: state.raisedEntryID, lineParked: isLineParked)
    }

    /// Newest first, the same order the bot's pool uses.
    func tradableEntries(fightingIDs: Set<String>) -> [DexEntry] {
        state.dex
            .filter { tradeRefusal(for: $0, fightingIDs: fightingIDs) == nil }
            .sorted { ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast) }
    }

    /// Applies completed trades once each and returns the ids safe to acknowledge (applied now or earlier).
    /// A delivery this build cannot show is left out, so the bot offers it again after an update.
    @discardableResult
    func applyTrades(_ deliveries: [TradeDelivery]) -> [String] {
        var settled: [String] = []
        var changed = false
        for delivery in deliveries {
            if state.appliedTradeIDs.contains(delivery.tradeID) {
                settled.append(delivery.tradeID)
                continue
            }
            let now = clock()
            let sender = Self.cleanedTrainerName(delivery.fromName)
            let given = state.dex.first { $0.id == delivery.giveID && $0.releasedAt == nil }
            guard let arrived = Self.receivedEntry(delivery.receive.entry, from: sender, partner: given?.finalID,
                                                   now: now) else { continue }
            if let index = state.dex.firstIndex(where: { $0.id == delivery.giveID && $0.releasedAt == nil }) {
                state.dex[index].releasedAt = now
                state.dex[index].tradedTo = sender
                settleSentItem(of: delivery)
            }
            state.dex.append(arrived)
            state.appliedTradeIDs.append(delivery.tradeID)
            if state.appliedTradeIDs.count > Self.appliedTradeLimit {
                state.appliedTradeIDs.removeFirst(state.appliedTradeIDs.count - Self.appliedTradeLimit)
            }
            settled.append(delivery.tradeID)
            changed = true
            tradeArrivalSeq += 1
            let name = delivery.receive.name
            tradeArrival = TradeArrival(id: tradeArrivalSeq, entryID: arrived.id, fromName: sender,
                                        receivedID: arrived.finalID, receivedName: name, isShiny: arrived.isShiny)
            notifyCompanionEvent(l.notifTradeTitle, l.notifTradeBody(name, from: sender))
        }
        guard changed else { return settled }
        state.reconcileRepresentativeSelection()
        save()
        Task { await resolveTradeEvolutions() }
        return settled
    }

    /// The trade item the bot says left with the Pokémon is taken out of the game: off the Pokémon if it still
    /// holds it, else out of the bag where an earlier unequip put it. Anything else it holds goes back to the bag
    /// with the orphan sweep in `save()`. An older bot does not say, so only a held trade item is removed.
    private func settleSentItem(of delivery: TradeDelivery) {
        let id = delivery.giveID
        guard delivery.reportsGiveHeldItem else {
            if heldItem(of: id)?.isTradeEvolutionItem == true { state.heldItems[id] = nil }
            return
        }
        guard let traveled = delivery.giveHeldItem.flatMap(ItemKind.init(rawValue:))?.tradeItemKey else { return }
        if state.heldItems[id] == traveled {
            state.heldItems[id] = nil
        } else {
            state.inventory[traveled] = max(0, (state.inventory[traveled] ?? 0) - 1)
        }
    }

    /// A received individual is a new one here: fresh id, no names, evolution pending until the line is known.
    /// `partner` is the species this side gave for it; the wire's own value is never trusted.
    nonisolated static func receivedEntry(_ wire: DexEntry, from sender: String, partner: Int? = nil,
                                          now: Date) -> DexEntry? {
        guard var profile = wire.profile,
              PokemonAssets.isSupported(speciesID: wire.baseID), PokemonAssets.isSupported(speciesID: wire.finalID)
        else { return nil }
        var entry = wire
        let id = UUID().uuidString
        profile.instanceID = id
        profile.sanitize()
        entry.id = id
        entry.profile = profile
        entry.names = nil
        entry.namesVersion = nil
        entry.releasedAt = nil
        entry.tradedTo = nil
        entry.caughtAt = now
        entry.originalTrainer = sender
        entry.tradeEvolutionPending = true
        entry.tradeHeldItem = wire.tradeHeldItem.flatMap { ItemKind(rawValue: $0)?.tradeItemKey }
        entry.tradePartnerID = partner
        if entry.chainOrder.last != entry.finalID {
            entry.chainOrder = entry.baseID == entry.finalID ? [entry.baseID] : [entry.baseID, entry.finalID]
        }
        return entry
    }

    nonisolated static func cleanedTrainerName(_ raw: String) -> String {
        let name = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let trimmed = String(String.UnicodeScalarView(name)).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(40))
    }

    /// Evolves every received individual that has a trade evolution. Offline, the flag stays and the next
    /// launch or sync tries again.
    func resolveTradeEvolutions() async {
        guard !isResolvingTradeEvolutions else { return }
        isResolvingTradeEvolutions = true
        defer { isResolvingTradeEvolutions = false }
        let pending = state.dex.filter { $0.tradeEvolutionPending == true && $0.releasedAt == nil }.map(\.id)
        for id in pending {
            _ = await evolveByTrade(entryID: id, withCord: false)
        }
    }

    /// Spends a Linking Cord to evolve a graduated individual as if it had been traded.
    @discardableResult
    func useLinkingCord(on entryID: String) async -> CordUseResult {
        if isTradeLocked(entryID) { return .listed }
        guard itemCount(.linkingCord) > 0,
              state.dex.contains(where: { $0.id == entryID && $0.releasedAt == nil && $0.profile != nil })
        else { return .unavailable }
        switch await evolveByTrade(entryID: entryID, withCord: true) {
        case .evolved: return .evolved
        case .noEvolution: return .wrongTarget
        case .notReady: return .notReady
        case .unavailable: return .unavailable
        case .everstone: return .everstone
        }
    }

    /// With the cord, the item it holds and the species the player has as friends count; on arrival, the item
    /// it was sent with and the species this side gave for it.
    private func evolveByTrade(entryID: String, withCord: Bool) async -> TradeEvolutionResult {
        func owned(_ entry: DexEntry) -> Bool { entry.id == entryID && entry.releasedAt == nil }
        if holdsEverstone(entryID) { return .everstone }
        guard let baseID = state.dex.first(where: owned)?.baseID else { return .noEvolution }
        guard let line = try? await dexNameLine(baseID: baseID) else { return .unavailable }
        // The store may have changed while the line loaded; read the entry again.
        guard let index = state.dex.firstIndex(where: owned) else { return .noEvolution }
        var entry = state.dex[index]
        let node = line.tree.node(withID: entry.finalID)
        let held = withCord ? heldItem(of: entryID) : entry.tradeHeldItem.flatMap(ItemKind.init(rawValue:))
        let partners: Set<Int> = withCord
            ? Set(state.friendEntryIDs.compactMap { friendEntry(forKey: $0)?.finalID })
            : Set(entry.tradePartnerID.map { [$0] } ?? [])
        let next = node?.tradeEvolution(heldItem: held, partners: partners)
        if withCord, next == nil, node?.evolvesByTrade == true { return .notReady }
        let fromID = entry.finalID
        if let next {
            if !entry.chainOrder.contains(next.speciesID) { entry.chainOrder.append(next.speciesID) }
            entry.finalID = next.speciesID
        }
        var usedItem = false
        if let next, case .holding? = EvolutionRules.rule(for: next.speciesID)?.trade { usedItem = true }
        if let unusedArrival = entry.tradeHeldItem.flatMap(ItemKind.init(rawValue:)), !usedItem {
            state.inventory[unusedArrival.rawValue, default: 0] += 1
        }
        if withCord, usedItem { state.heldItems[entryID] = nil }
        entry.tradeEvolutionPending = nil
        entry.tradeHeldItem = nil
        entry.tradePartnerID = nil
        Self.mergeNames(of: line, into: &entry)
        state.dex[index] = entry
        guard let next else {
            save()
            return .noEvolution
        }
        if withCord { state.inventory[ItemKind.linkingCord.rawValue] = max(0, itemCount(.linkingCord) - 1) }
        state.reconcileRepresentativeSelection()
        announceTradeEvolution(of: entry, from: fromID, to: next.speciesID, line: line)
        save()
        await loadPokemonDetails(speciesID: next.speciesID)
        return .evolved
    }

    private func announceTradeEvolution(of entry: DexEntry, from fromID: Int, to toID: Int, line: EvoLine) {
        func name(_ id: Int) -> String {
            formDisplayName(line.localizedName(id, state.language), speciesID: id, form: entry.form)
        }
        if var arrival = tradeArrival, arrival.entryID == entry.id {
            arrival.receivedName = name(fromID)
            arrival.evolvedID = toID
            arrival.evolvedName = name(toID)
            tradeArrival = arrival
        } else {
            tradeArrivalSeq += 1
            tradeArrival = TradeArrival(id: tradeArrivalSeq, entryID: entry.id, fromName: nil, receivedID: fromID,
                                        receivedName: name(fromID), evolvedID: toID, evolvedName: name(toID),
                                        isShiny: entry.isShiny)
        }
        notifyCompanionEvent(l.notifTradeEvolveTitle, l.notifTradeEvolveBody(name(fromID), name(toID)))
    }

    // MARK: 영속
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }   // 파일 없음 = 신규 설치
        guard let s = try? JSONDecoder().decode(CompanionState.self, from: data) else {
            // 디코드 실패(전면 손상/미래 스키마) → 원본을 .corrupt 로 백업 후 유효한 스냅샷으로 복구 시도.
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            do {
                try FileManager.default.moveItem(at: fileURL, to: backup)
                AppLog.write("companion state decode failed — original backed up to \(backup.lastPathComponent)")
            } catch {
                AppLog.write("failed to move corrupt state file to \(backup.lastPathComponent): \(error)")
            }

            if let recovered = SaveSnapshotManager.loadLatestValidSnapshot(for: fileURL) {
                state = SaveTransfer.sanitized(recovered)
                AppLog.write("automatically recovered companion state from snapshot")
                save()
            } else {
                state = CompanionState()
                AppLog.write("no snapshot available, starting fresh")
            }
            return
        }
        // 불러오기 경계와 같은 정규화를 디스크에서 읽을 때도 건다. 불러오기만 막으면 **이미 저장된**
        // 극단값은 그대로 남아, 앱이 매 기동마다 같은 값을 읽어 산술 트랩으로 죽는 상태를 못 벗어난다
        // (디코드는 *성공*하므로 위의 .corrupt 복구도 발동하지 않는다). 여기서 걸면 자가 복구된다.
        state = SaveTransfer.sanitized(s)
    }
    func save() {
        state.reconcileRaised()
        state.reconcileFriends()
        state.returnOrphanedHeldItems()
        state.returnOrphanedExpShares()
        state.dropOrphanedKeepWaiting()
        state.dropOrphanedGraduateEvolution()
        refreshRepresentativeSubject()
        refreshFriendSubjects()
        checkDexCompletions()   // 보유 성장분이 영속되는 매 지점에서 세대 완성 알림을 한 번만 띄운다
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)   // 부분 쓰기 손상 방지(펫 상태)
    }

    /// Records a first gym clear: the badge, its TM if any is left, a save and a notification.
    func applyGymReward(_ reward: GymReward, trainer: String, region: String) {
        state.gymBadges = reward.badges
        if let moveID = reward.tmMoveID { grantTM(moveID: moveID) }
        let prizeLines = reward.prize.map(grantPrize)
        save()
        let tm = reward.tmMoveID.flatMap { id in MachineCatalog.moves.first { $0.id == id }?.name(language) }
        var body = l.gymRewardBody(reward.kind, trainer: trainer, region: region, tm: tm)
        if let prizeLines { body += " " + l.gymRewardPrize(prizeLines) }
        notifyCompanionEvent(l.gymRewardTitle(reward.kind), body)
    }

    /// Adds the prize to the bag and returns what it paid as display lines. A single-copy item already owned
    /// is skipped. Mutates state only; the caller saves.
    private func grantPrize(_ prize: HiddenBossPrize) -> [String] {
        state.inventory[prize.eggKey, default: 0] += 1
        state.inventory[ItemKind.rareCandy.rawValue, default: 0] += HiddenBossPrize.candyCount
        let granted = prize.itemKeys.filter { key in
            if let kind = ItemKind(rawValue: key), kind.isSingleCopy, itemOwnedTotal(kind) > 0 { return false }
            state.inventory[key, default: 0] += 1
            return true
        }
        return l.hiddenBossPrizeLines(eggSpeciesID: prize.eggSpeciesID, itemKeys: granted)
    }
}
