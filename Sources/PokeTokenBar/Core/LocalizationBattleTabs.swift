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

    var battleSpeciesClause: String {
        t("같은 포켓몬이 이미 엔트리에 있어요",
          "The same Pokémon is already in the lineup",
          "同じポケモンがすでにエントリーにいます",
          "Ese Pokémon ya está en el equipo",
          "Ce Pokémon est déjà dans l'équipe",
          "Esse Pokémon já está na equipe",
          "Dieses Pokémon ist schon in der Aufstellung",
          "Такой покемон уже в составе")
    }

    var battleSpeciesDuplicateWarning: String {
        t("같은 포켓몬은 한 마리만 나갈 수 있어요. 대결에는 앞 순서만 나가요.",
          "Only one of each Pokémon can battle. Only the earlier one goes out.",
          "同じポケモンは1匹しか出られません。対戦には先の順番だけが出ます。",
          "Solo puede combatir uno de cada Pokémon. Sale solo el primero.",
          "Un seul exemplaire de chaque Pokémon peut combattre. Seul le premier sort.",
          "Só um de cada Pokémon pode batalhar. Só o primeiro entra.",
          "Von jedem Pokémon kann nur eines kämpfen. Nur das frühere tritt an.",
          "Каждый покемон может сражаться только в одном экземпляре. Выходит только первый.")
    }
}
