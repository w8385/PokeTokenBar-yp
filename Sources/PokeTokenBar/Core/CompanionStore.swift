import Foundation
import Observation
import UserNotifications

/// 게임 상태의 출처. 설치 이후 토큰 사용량으로 포켓몬을 진화시키고, 최종체 + 추가 임계 도달 시
/// 도감(라인 전체)에 보존 + 새 알. 진화 트리/희귀도/이름은 PokeProviding 으로 런타임 주입.
@MainActor
@Observable
final class CompanionStore {
    var state = CompanionState()
    var displayState: CompanionStateKind = .egg
    /// Time since the last token usage while `displayState == .sulk`, else 0.
    var sulkIdle: TimeInterval = 0
    /// Mirror of `UsageStore.alwaysFacesBack` (set by `AppDelegate.updateCompanion`): a display preference.
    var alwaysFacesBack = false
    /// The companion shows its back sprite on every surface: while sulking, or always when asked to.
    /// An egg has no back to show.
    var facesBack: Bool { hasRaisedPokemon && (alwaysFacesBack || displayState == .sulk) }
    var currentLine: EvoLine?
    private(set) var representativeSubject = RepresentativeSubject(speciesID: nil, isShiny: false)
    /// Graduated Pokémon shown beside the active one. Display only: no growth, stats or save effect beyond the pick.
    var friendSubjects: [FriendSubject] = []
    /// The latest stone put on or taken off a matching Pokémon. Surfaces play the Mega Evolution effect from it.
    var megaEvolveEvent: MegaEvolveEvent?
    @ObservationIgnored var megaEvolveCounter = 0
    /// Bumped when the active Pokémon hatches, evolves, graduates or reveals as Ditto; friends cheer on a change.
    var cheerSeq = 0
    var isHatching = false
    var isRevealingDitto = false   // 메타몽 리빌 비동기 중복 방지(isHatching 자매)
    var justEvolvedTo: String?     // 이름(연출/문구)
    var justGraduated: String?
    /// Shown under `justGraduated`: the XP past graduation and how many Exp. Share holders took it.
    var graduationLeftoverShared: (xp: Int, holders: Int)?
    var eventUntil: Date?

    /// 부화/진화 연출 트리거 — seq 증가로 UI 가 감지, 팝오버가 닫혀 있었어도 다음 오픈에 1회 재생.
    enum Celebration: Equatable { case hatch(shiny: Bool), evolve, dittoReveal(shiny: Bool) }
    var celebration: Celebration?
    private(set) var celebrationSeq = 0
    func fireCelebration(_ c: Celebration) { celebration = c; celebrationSeq += 1; cheerSeq += 1 }
    /// 연출 재생 후 UI 가 호출(1회성 보장).
    func consumeCelebration() { celebration = nil }

    /// 사탕 사용 시 "+XP" 순간 표시 — 진화 없이 부분 진행일 때도 피드백. seq 증가로 CompanionHeader 감지.
    var candyFeedbackSeq = 0
    var candyFeedbackAmount = 0
    /// "+XP" 표시 1회성 보장 — CompanionHeader 가 재생 후 호출한다. 소비하지 않으면 다른 탭에 갔다
    /// 홈으로 재진입할 때(CompanionHeader 재마운트) @State 가 초기화돼 같은 값이 다시 떠오른다(회귀).
    func consumeCandyFeedback() { candyFeedbackAmount = 0 }

    /// 민트 사용 시 "성격이 X로" 순간 표시 — 사탕 피드백과 동일 1회성 패턴(seq + consume).
    var mintFeedbackSeq = 0
    var mintFeedbackNature: PokemonNature?
    func consumeMintFeedback() { mintFeedbackNature = nil }

    let provider: any PokeProviding
    var dexNameRequests: [Int: Task<EvoLine, Error>] = [:]
    let detailProvider: (any PokemonDetailProviding)?
    let speciesIndexProvider: (any SpeciesIndexProviding)?
    let clock: () -> Date
    let fileURL: URL
    var rng: any RandomNumberGenerator
    let dittoDisguiseRollingEnabled: Bool
    var speciesIndex: SpeciesIndex?
    var speciesIndexStatus = SpeciesIndexStatus.idle
    var pokemonDetailsByID: [Int: PokemonDetails] = [:]
    var loadingPokemonDetailIDs: Set<Int> = []
    var failedPokemonDetailIDs: Set<Int> = []
    let defaults: UserDefaults
    /// 세션 내 활성 개체 교체 감지용. await 뒤 이전 개체의 결과가 새 개체를 덮지 않게 한다.
    var activeGeneration = 0
    var lastAutoSnapshotDate: Date?
    var nextEvolutionGateCheck = Date.distantPast
    var availableSnapshots: [SaveSnapshot] = []
    var timeMeter = ActiveTimeMeter()
    var timeActiveNow = false
    var rebaseUsageOnNextUpdate = false
    var tokenModeSinceUnsaved = false
    var deferTimeSaves = false
    var timeSavePending = false
    var lastTimeSaveUptime: TimeInterval?
    /// Called after each write of the save file.
    var didWriteSave: (() -> Void)?
    /// Moves a stuck raised Pokémon or an idle Exp. Share holder on by itself (`CompanionStore+MoveOn`).
    var autoMoveOn: Bool {
        didSet { defaults.set(autoMoveOn, forKey: Self.autoMoveOnKey) }
    }
    /// The popover is open, so the player can see a stuck Pokémon.
    var isAttended = false

    /// 알이 부화 준비(100%)가 되었으나 PokéAPI 요청/후보 선택 실패로 다음 갱신을 기다리는 상태.
    var isHatchRetryDelayed = false

    /// The raised graduate's line, loaded by `checkRaisedGraduateEvolution`. In memory only.
    var raisedGraduateLine: EvoLine?
    var isLoadingGraduateLine = false

    /// Lines of graduated Exp. Share holders, by base species. In memory only.
    var expShareLines: [Int: EvoLine] = [:]
    var loadingExpShareLines: Set<Int> = []
    var nextExpShareCheck = Date.distantPast

    /// Purchases that can still be taken back, by inventory key (one per shop row). A row shows its entry for
    /// `PurchaseReceipt.window` seconds; the view calls `dismissReceipt` when that ends.
    var purchaseReceipts: [String: PurchaseReceipt] = [:]

    /// companion 이벤트 시스템 알림(.app + 토글 ON 일 때만). 한도 알림과 독립.
    var notifSeq = 0
    /// The newest hatch / evolution / graduation / Ditto line; the floating pet pops it once. Recorded before the
    /// bundled-app guard below so a dev build (no system notifications) shows it too.
    /// `seq` tells a new event from one already shown, even when two share a clock instant.
    struct CompanionEvent: Equatable { let seq: Int; let text: String; let at: Date }
    var latestEvent: CompanionEvent?
    var eventSeq = 0

    var prefetchInFlight = false
    var prefetchedLineID: Int?   // 라인·스프라이트 예열 완료한 종(세션 메모리)

    /// Today's total at the previous refresh, and when a rise in it was last seen. The enrichment scan's
    /// `lastUsage` lags a refresh behind, so without this the companion would keep its back turned for a
    /// while after usage resumed. Not persisted: after a launch there is nothing to compare with.
    var lastSeenToday: (date: String, total: Int)?
    var lastObservedUsage: Date?

    var tradeArrival: TradeArrival?
    @ObservationIgnored var tradeArrivalSeq = 0
    @ObservationIgnored var isResolvingTradeEvolutions = false

    /// Individuals in an open trade, each locked until the time shown. Their item slot stays as it was when the
    /// offer was made, because that item travels with the Pokémon.
    var tradeLocks: [String: Date] = [:]

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
        load()
        if state.tokenModeSince == nil {
            state.tokenModeSince = clock()
            tokenModeSinceUnsaved = true
        }
        migrateEconomyIfNeeded()
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

    // MARK: Economy migration

    /// Moves a save to the current tables. Every banked stage keeps the fraction it had: the old threshold was
    /// the old table × the growth slider the player had (`LegacyGrowthDifficulty`). Profile growth is measured
    /// against the bare tables, so it shrinks by the table factor alone. Wallet and usage never change.
    func migrateEconomyIfNeeded() {
        let version = state.economyVersion
        guard version < PokemonBalance.economyVersion else { return }
        if state.usedSinceInstall > 0 || state.active != nil || !state.dex.isEmpty,
           FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("companion-state.pre-economy-v\(PokemonBalance.economyVersion).json")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
        }
        let factor = LegacyGrowthDifficulty.tableFactor(fromEconomyVersion: version)
        rescaleBankedStages(oldScale: LegacyGrowthDifficulty(defaults).scale(fromEconomyVersion: version))
        if var active = state.active {
            active.profile?.growthTokens /= factor
            state.active = active
        }
        for id in state.storedLines.keys {
            state.storedLines[id]?.mon.profile?.growthTokens /= factor
        }
        for index in state.dex.indices {
            state.dex[index].profile?.growthTokens /= factor
        }
        state.economyVersion = PokemonBalance.economyVersion
        save()
        AppLog.write("economy migration complete — v\(version) to v\(PokemonBalance.economyVersion)")
    }

    /// Credits written against thresholds `oldScale` times the current ones, moved to the current thresholds.
    private func rescaleBankedStages(oldScale: Double) {
        func rescaled(_ credits: Int, base: Int) -> Int {
            let oldThreshold = max(1, Int((Double(base) * oldScale).rounded()))
            let newThreshold = max(1, base)
            guard oldThreshold != newThreshold else { return credits }
            let value = Double(credits) / Double(oldThreshold) * Double(newThreshold)
            let rounded = Int(min(Double(SaveTransfer.maxTokenValue), max(0, value.rounded(.down))))
            // Rounding must never turn an incomplete stage into a completed one.
            return credits < oldThreshold ? min(newThreshold - 1, rounded) : rounded
        }
        if var active = state.active {
            active.usedAtStage = rescaled(active.usedAtStage, base: active.phaseThreshold)
            state.active = active
        }
        state.eggUsage = rescaled(state.eggUsage, base: PokemonBalance.eggHatchThreshold)
        for id in state.storedLines.keys {
            guard let mon = state.storedLines[id]?.mon else { continue }
            state.storedLines[id]?.mon.usedAtStage = rescaled(mon.usedAtStage, base: mon.phaseThreshold)
        }
        for id in state.graduateEvolution.keys {
            guard let xp = state.graduateEvolution[id]?.graduateXP else { continue }
            state.graduateEvolution[id]?.graduateXP = Int((Double(xp) / oldScale).rounded(.down))
        }
    }

    var eggHatchThreshold: Int { PokemonBalance.eggHatchThreshold }

    func stageThreshold(for mon: MonState) -> Int { mon.phaseThreshold }

    /// The shop price, or nil when the item is not sold.
    func price(of kind: ItemKind) -> Int? {
        kind == .expShare ? ExpShare.price(owned: itemOwnedTotal(kind)) : kind.shopPrice
    }

    func price(of entry: ShopEntry) -> Int { entry.price }
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
        state.returnLeftoverEvolutionItems()
        state.repairUrshifuStyles()
        state.revertUnearnedTradeSteps()
    }
    func save() {
        if deferTimeSaves {
            timeSavePending = true
            return
        }
        timeSavePending = false
        state.reconcileRaised()
        state.reconcileFriends()
        state.returnOrphanedHeldItems()
        state.returnOrphanedExpShares()
        state.dropOrphanedKeepWaiting()
        state.dropOrphanedExpShareTakenOff()
        state.dropOrphanedGraduateEvolution()
        refreshRepresentativeSubject()
        refreshFriendSubjects()
        checkDexCompletions()   // 보유 성장분이 영속되는 매 지점에서 세대 완성 알림을 한 번만 띄운다
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)   // 부분 쓰기 손상 방지(펫 상태)
        didWriteSave?()
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

    /// Records the first win against a coworker's ghost; false when the trophy was already there.
    func claimCoworkerTrophy(_ coworkerID: String) -> Bool {
        guard state.coworkerTrophies.insert(coworkerID).inserted else { return false }
        save()
        return true
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
