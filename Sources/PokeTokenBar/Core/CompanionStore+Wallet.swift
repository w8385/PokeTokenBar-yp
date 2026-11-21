import Foundation

extension CompanionStore {
    /// 상점에서 쓸 수 있는 토큰(재화) = 실사용 누적 − 상점 지출 누적. 성장 미터(usedSinceInstall)는
    /// 여기선 읽기만 — 구매는 spentTokens 만 올려 잔액을 깎는다(진화 진행·오늘/주/월 통계 무영향).
    /// Time-mode credit is wallet income too; it never enters `usedSinceInstall`.
    var availableTokens: Int { max(0, state.usedSinceInstall + state.timeCredit - state.spentTokens) }

    /// Takes `cost` out of the wallet. False, with nothing taken, when the wallet holds less. The caller saves.
    func spend(_ cost: Int) -> Bool {
        guard availableTokens >= cost else { return false }
        state.spentTokens += cost
        return true
    }

    /// Puts back what an undone purchase cost. The caller saves.
    func refund(_ cost: Int) {
        state.spentTokens = max(0, state.spentTokens - cost)
    }
}
