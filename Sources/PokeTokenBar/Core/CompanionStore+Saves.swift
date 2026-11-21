import Foundation

extension CompanionStore {
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
        migrateEconomyIfNeeded()
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
}
