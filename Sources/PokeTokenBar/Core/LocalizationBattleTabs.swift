import Foundation

extension L {
    func title(of tab: BattleSubTab) -> String {
        switch tab {
        case .entry: battleSubTabEntry
        case .battle: battleSubTabBattle
        case .history: battleSubTabHistory
        }
    }

    var battleSubTabEntry: String {
        t("엔트리", "Entry", "エントリー", "Equipo", "Équipe", "Equipe", "Team", "Состав")
    }

    var battleSubTabBattle: String {
        t("배틀", "Battle", "バトル", "Combate", "Combat", "Batalha", "Kampf", "Бой")
    }

    var battleSubTabHistory: String {
        t("기록", "History", "履歴", "Historial", "Historique", "Histórico", "Verlauf", "История")
    }
}
