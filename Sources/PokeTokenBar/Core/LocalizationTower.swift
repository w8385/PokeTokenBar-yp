import Foundation

/// Strings for the Battle tab's tower sub-tab.
extension L {
    var battleSubTabTower: String {
        t("타워", "Tower", "タワー", "Torre", "Tour", "Torre", "Turm", "Башня")
    }

    var towerTitle: String {
        t("배틀 타워", "Battle Tower", "バトルタワー", "Torre de Combate", "Tour de Combat", "Torre de Batalha", "Kampfturm", "Боевая башня")
    }

    var towerBoast: String {
        t("처음 타워 주인을 이기거나 최고 기록을 세우면 대결 채널에 알리기",
          "Post my first owner win and new bests to the battle channel",
          "初めてタワーの主に勝ったときと最高記録をバトルチャンネルに投稿",
          "Publicar en el canal de combates mi primera victoria ante el dueño y mis nuevos récords",
          "Publier ma première victoire contre le maître et mes records dans le canal des combats",
          "Publicar no canal de batalhas minha primeira vitória contra o dono e novos recordes",
          "Ersten Sieg gegen den Turmherrn und neue Rekorde im Kampfkanal posten",
          "Сообщать в канал боёв о первой победе над хозяином и новых рекордах")
    }

    var towerRankingTitle: String {
        t("배틀 타워 순위", "Battle Tower ranking", "バトルタワーランキング", "Clasificación de la Torre", "Classement de la Tour",
          "Ranking da Torre", "Turm-Rangliste", "Рейтинг башни")
    }

    func towerBestStreak(_ wins: Int) -> String {
        t("\(wins)연승", "\(wins) wins", "\(wins)連勝", "\(wins) victorias", "\(wins) victoires", "\(wins) vitórias",
          "\(wins) Siege", "\(wins) побед")
    }

    var towerLoading: String {
        t("타워 기록을 불러오는 중…", "Loading the tower…", "タワーの記録を読み込み中…", "Cargando la torre…",
          "Chargement de la tour…", "Carregando a torre…", "Turm wird geladen…", "Загрузка башни…")
    }

    func towerModeName(_ mode: TowerMode) -> String {
        switch mode {
        case .entry: t("내 엔트리", "My team", "マイチーム", "Mi equipo", "Mon équipe", "Minha equipe", "Mein Team", "Моя команда")
        case .rental: t("대여", "Rental", "レンタル", "Alquiler", "Location", "Aluguel", "Leihgabe", "Аренда")
        }
    }

    func towerBP(_ points: Int) -> String { "\(points) BP" }

    func towerStreak(_ streak: Int, best: Int) -> String {
        t("연승 \(streak) · 최고 \(best)", "Streak \(streak) · Best \(best)", "連勝 \(streak) · 最高 \(best)",
          "Racha \(streak) · Mejor \(best)", "Série \(streak) · Record \(best)", "Sequência \(streak) · Melhor \(best)",
          "Serie \(streak) · Bestwert \(best)", "Серия \(streak) · Рекорд \(best)")
    }

    func towerNext(_ next: TowerRun.Next) -> String {
        if next.owner {
            return t("다음: \(next.battle)번째 배틀 · 타워 주인", "Next: battle \(next.battle) · the Tower Keeper",
                     "次: \(next.battle)戦目 · タワーキーパー", "Siguiente: combate \(next.battle) · el Guardián",
                     "Suivant : combat \(next.battle) · le Gardien", "Próxima: batalha \(next.battle) · o Guardião",
                     "Nächster: Kampf \(next.battle) · der Turmhüter", "Далее: бой \(next.battle) · Хранитель башни")
        }
        return t("다음: \(next.set)세트 \(next.battle)번째 배틀", "Next: set \(next.set), battle \(next.battle)",
                 "次: 第\(next.set)セット \(next.battle)戦目", "Siguiente: serie \(next.set), combate \(next.battle)",
                 "Suivant : série \(next.set), combat \(next.battle)", "Próxima: série \(next.set), batalha \(next.battle)",
                 "Nächster: Runde \(next.set), Kampf \(next.battle)", "Далее: сет \(next.set), бой \(next.battle)")
    }

    func towerTrophyName(_ trophy: String) -> String {
        trophy == "gold"
            ? t("금 트로피", "Gold trophy", "金のトロフィー", "Trofeo de oro", "Trophée d'or", "Troféu de ouro", "Goldtrophäe", "Золотой трофей")
            : t("은 트로피", "Silver trophy", "銀のトロフィー", "Trofeo de plata", "Trophée d'argent", "Troféu de prata", "Silbertrophäe", "Серебряный трофей")
    }

    func towerChallenge(_ battle: Int) -> String {
        t("\(battle)번째 배틀 도전", "Fight battle \(battle)", "\(battle)戦目に挑戦", "Luchar el combate \(battle)",
          "Livrer le combat \(battle)", "Lutar a batalha \(battle)", "Kampf \(battle) bestreiten", "Начать бой \(battle)")
    }

    var towerNextBattle: String {
        t("다음 배틀", "Next battle", "次のバトル", "Siguiente combate", "Combat suivant", "Próxima batalha", "Nächster Kampf", "Следующий бой")
    }

    var towerQuit: String {
        t("도전 그만두기", "End the run", "挑戦をやめる", "Terminar la racha", "Arrêter la série", "Encerrar a sequência",
          "Serie beenden", "Закончить серию")
    }

    var towerEmptySlot: String {
        t("고르기", "Pick", "選ぶ", "Elegir", "Choisir", "Escolher", "Wählen", "Выбрать")
    }

    var towerEntryNote: String {
        t("서로 다른 포켓몬 3마리가 Lv50으로 나가요. 배틀마다 체력이 다 회복되고, 한 번 지면 연승이 0으로 돌아가요.",
          "Three different Pokémon fight at Lv50. Each battle starts at full health; one loss sets the streak back to 0.",
          "違うポケモン3匹がLv50で出場します。バトルごとに全回復し、1回負けると連勝は0に戻ります。",
          "Tres Pokémon distintos luchan a Nv50. Cada combate empieza con la salud completa; una derrota pone la racha a 0.",
          "Trois Pokémon différents combattent au N50. Chaque combat commence en pleine forme ; une défaite remet la série à 0.",
          "Três Pokémon diferentes lutam no Nv50. Cada batalha começa com a vida cheia; uma derrota zera a sequência.",
          "Drei verschiedene Pokémon kämpfen mit Lv50. Jeder Kampf beginnt mit voller KP; eine Niederlage setzt die Serie auf 0.",
          "Три разных покемона сражаются на Ур50. Каждый бой с полным здоровьем; одно поражение обнуляет серию.")
    }

    var towerEntryLocked: String {
        t("도전 중에는 엔트리를 바꿀 수 없어요.", "The team is locked until the run ends.", "挑戦中はチームを変えられません。",
          "El equipo queda fijo hasta que acabe la racha.", "L'équipe est figée jusqu'à la fin de la série.",
          "A equipe fica fixa até a sequência acabar.", "Das Team bleibt bis zum Ende der Serie fest.",
          "Команду нельзя менять, пока идёт серия.")
    }

    var towerNeedsThree: String {
        t("서로 다른 포켓몬 3마리를 골라 주세요.", "Pick three different Pokémon.", "違うポケモンを3匹選んでください。",
          "Elige tres Pokémon distintos.", "Choisis trois Pokémon différents.", "Escolha três Pokémon diferentes.",
          "Wähle drei verschiedene Pokémon.", "Выберите трёх разных покемонов.")
    }

    func towerEarned(_ points: Int) -> String {
        t("+\(points) BP 획득", "+\(points) BP", "+\(points) BP 獲得", "+\(points) BP", "+\(points) BP", "+\(points) BP",
          "+\(points) BP", "+\(points) BP")
    }

    func towerTrophyEarned(_ trophy: String) -> String {
        let name = towerTrophyName(trophy)
        return t("\(name)를 받았어요!", "You won the \(name.lowercased())!", "\(name)を手に入れた！", "¡Ganaste el \(name.lowercased())!",
                 "Tu as gagné le \(name.lowercased()) !", "Você ganhou o \(name.lowercased())!", "Du hast die \(name) gewonnen!",
                 "Получен: \(name.lowercased())!")
    }

    func towerStreakEnded(_ streak: Int) -> String {
        t("\(streak)연승에서 끝났어요.", "The run ended at \(streak) wins.", "\(streak)連勝で終わりました。",
          "La racha terminó en \(streak) victorias.", "La série s'arrête à \(streak) victoires.",
          "A sequência terminou em \(streak) vitórias.", "Die Serie endete bei \(streak) Siegen.",
          "Серия закончилась на \(streak) победах.")
    }

    // MARK: Rental

    var towerRentalGet: String {
        t("대여 포켓몬 받기", "Get rentals", "レンタルを受け取る", "Recibir alquileres", "Recevoir les locations",
          "Receber aluguéis", "Leihgaben holen", "Получить аренду")
    }

    var towerRentalNote: String {
        t("6마리 중 3마리를 골라요. 이기면 방금 이긴 상대의 포켓몬 1마리와 바꿀 수 있어요.",
          "Pick three of six. After a win you may swap one for a Pokémon of the trainer you just beat.",
          "6匹から3匹を選びます。勝つと、倒した相手のポケモン1匹と入れ替えられます。",
          "Elige tres de seis. Tras ganar puedes cambiar uno por un Pokémon del entrenador vencido.",
          "Choisis trois sur six. Après une victoire, tu peux en échanger un contre un Pokémon du Dresseur battu.",
          "Escolha três de seis. Depois de vencer, pode trocar um por um Pokémon do treinador derrotado.",
          "Wähle drei von sechs. Nach einem Sieg darfst du eins gegen ein Pokémon des besiegten Trainers tauschen.",
          "Выберите трёх из шести. После победы можно обменять одного на покемона побеждённого тренера.")
    }

    func towerRentalStart(_ picked: Int) -> String {
        t("이 3마리로 시작 (\(picked)/3)", "Start with these (\(picked)/3)", "この3匹で始める (\(picked)/3)",
          "Empezar con estos (\(picked)/3)", "Commencer avec eux (\(picked)/3)", "Começar com estes (\(picked)/3)",
          "Mit diesen starten (\(picked)/3)", "Начать с ними (\(picked)/3)")
    }

    var towerSwapNote: String {
        t("내 포켓몬 1마리와 방금 이긴 상대의 포켓몬 1마리를 골라 바꿀 수 있어요.",
          "Pick one of yours and one of the trainer you just beat to swap them.",
          "自分のポケモン1匹と、倒した相手のポケモン1匹を選んで入れ替えられます。",
          "Elige uno tuyo y uno del entrenador vencido para cambiarlos.",
          "Choisis un des tiens et un du Dresseur battu pour les échanger.",
          "Escolha um seu e um do treinador derrotado para trocá-los.",
          "Wähle eins von dir und eins des besiegten Trainers, um sie zu tauschen.",
          "Выберите своего покемона и покемона побеждённого тренера, чтобы обменять их.")
    }

    var towerSwapTheirs: String {
        t("방금 이긴 상대", "Just beaten", "倒した相手", "Recién vencido", "Tout juste battu", "Recém-derrotado",
          "Gerade besiegt", "Только что побеждён")
    }

    var towerSwap: String {
        t("교체", "Swap", "入れ替え", "Cambiar", "Échanger", "Trocar", "Tauschen", "Обменять")
    }

    // MARK: Exchange

    var towerExchange: String {
        t("BP 교환소", "BP Exchange", "BP交換所", "Canje de BP", "Échange de BP", "Troca de BP", "BP-Tausch", "Обмен BP")
    }

    var towerExchangeAction: String {
        t("교환", "Exchange", "交換", "Canjear", "Échanger", "Trocar", "Tauschen", "Обменять")
    }

    var towerExchangeNote: String {
        t("배틀 타워에서 모은 BP로 바꿔요. 전설 스카우트 티켓은 여기서만 받을 수 있어요.",
          "Spend the BP you won in the tower. The Legendary Scout Ticket is only found here.",
          "バトルタワーで集めたBPと交換します。伝説スカウトチケットはここでしか手に入りません。",
          "Canjea los BP ganados en la torre. El boleto de exploración legendario solo está aquí.",
          "Dépense les BP gagnés dans la tour. Le ticket de recrutement légendaire ne se trouve qu'ici.",
          "Troque os BP ganhos na torre. O bilhete de recrutamento lendário só existe aqui.",
          "Tausche die im Turm gewonnenen BP. Das legendäre Scouting-Ticket gibt es nur hier.",
          "Обменивайте BP, заработанные в башне. Легендарный билет разведки есть только здесь.")
    }

    func towerFailure(_ failure: GymService.Failure) -> String {
        guard case .refused(let code) = failure else { return gymFailure(failure) }
        switch code {
        case "team_locked":
            return t("다른 엔트리로 도전 중이에요. 그만두거나 그 엔트리로 이어 가세요.",
                     "A run with another team is live. End it or carry on with that team.",
                     "別のチームで挑戦中です。やめるか、そのチームで続けてください。",
                     "Hay una racha en curso con otro equipo. Termínala o sigue con ese equipo.",
                     "Une série avec une autre équipe est en cours. Arrête-la ou continue avec cette équipe.",
                     "Há uma sequência em andamento com outra equipe. Encerre ou continue com ela.",
                     "Eine Serie mit einem anderen Team läuft. Beende sie oder mach mit diesem Team weiter.",
                     "Идёт серия с другой командой. Закончите её или продолжайте той командой.")
        default:
            return gymFailure(failure)
        }
    }
}
