import Foundation

/// Strings for the Battle tab's gym section: gyms, the Elite Four run, villain hideouts, badges and rewards.
extension L {
    // MARK: Section

    var gymSectionTitle: String { t("체육관", "Gyms", "ジム", "Gimnasios", "Arènes", "Ginásios", "Arenen", "Залы") }
    var gymRegionLabel: String { t("지역", "Region", "地方", "Región", "Région", "Região", "Region", "Регион") }
    var gymLeaderLabel: String { t("관장", "Gym Leader", "ジムリーダー", "Líder", "Champion d'arène", "Líder", "Arenaleiter", "Лидер") }
    var gymChallenge: String { t("도전", "Challenge", "挑戦", "Retar", "Défier", "Desafiar", "Herausfordern", "Бросить вызов") }
    var gymRematch: String { t("다시 도전", "Rematch", "再挑戦", "Revancha", "Revanche", "Revanche", "Rematch", "Реванш") }
    var gymRetry: String { t("다시 시도", "Retry", "再試行", "Reintentar", "Réessayer", "Tentar de novo", "Erneut versuchen", "Повторить") }
    var gymFighting: String { t("대결 중…", "Fighting…", "対戦中…", "Combatiendo…", "Combat en cours…", "Lutando…", "Kampf läuft…", "Бой…") }
    var gymLoading: String { t("체육관 정보를 불러오는 중…", "Loading gyms…", "ジム情報を読み込み中…", "Cargando gimnasios…", "Chargement des arènes…", "Carregando ginásios…", "Arenen werden geladen…", "Загрузка залов…") }
    func gymTeamLine(_ count: Int, level: Int) -> String {
        t("\(count)마리 · Lv\(level)", "\(count) Pokémon · Lv\(level)", "\(count)匹 · Lv\(level)", "\(count) Pokémon · Nv\(level)",
          "\(count) Pokémon · N\(level)", "\(count) Pokémon · Nv\(level)", "\(count) Pokémon · Lv\(level)", "\(count) покемонов · Ур\(level)")
    }
    func gymBadgeProgress(_ have: Int, of total: Int) -> String {
        t("배지 \(have)/\(total)", "Badges \(have)/\(total)", "バッジ \(have)/\(total)", "Medallas \(have)/\(total)",
          "Badges \(have)/\(total)", "Insígnias \(have)/\(total)", "Orden \(have)/\(total)", "Значки \(have)/\(total)")
    }
    var gymBadgeCaseTitle: String { t("배지 케이스", "Badge case", "バッジケース", "Caja de medallas", "Boîte à badges", "Estojo de insígnias", "Orden-Box", "Футляр для значков") }
    var gymBadgeEarned: String { t("획득", "Earned", "獲得", "Obtenida", "Obtenu", "Obtida", "Erhalten", "Получен") }
    var gymBadgeLocked: String { t("미획득", "Not yet", "未獲得", "Pendiente", "Pas encore", "Pendente", "Noch nicht", "Нет") }
    var gymTeamNote: String {
        t("엔트리 전원(최대 6마리)이 Lv50 이하로 출전해요. 슬랙에는 아무것도 올라가지 않아요.",
          "Your whole entry (up to six) fights at Lv50 or below. Nothing is posted to Slack.",
          "エントリー全員(最大6匹)がLv50以下で出場します。Slackには何も投稿されません。",
          "Todo tu equipo (hasta seis) combate a Nv50 o menos. No se publica nada en Slack.",
          "Toute ton équipe (jusqu'à six) combat à N50 max. Rien n'est publié sur Slack.",
          "Toda a sua equipe (até seis) luta no Nv50 ou menos. Nada é publicado no Slack.",
          "Dein ganzes Team (bis zu sechs) kämpft mit höchstens Lv50. Nichts wird in Slack gepostet.",
          "Вся команда (до шести) сражается на Ур50 или ниже. В Slack ничего не публикуется.")
    }

    // MARK: Elite Four

    var gymEliteTitle: String { t("사천왕", "Elite Four", "四天王", "Alto Mando", "Conseil des 4", "Elite dos Quatro", "Top Vier", "Элитная четвёрка") }
    var gymChampionLabel: String { t("챔피언", "Champion", "チャンピオン", "Campeón", "Maître", "Campeão", "Champion", "Чемпион") }
    var gymHallOfFame: String { t("명예의 전당", "Hall of Fame", "殿堂入り", "Salón de la Fama", "Panthéon", "Hall da Fama", "Ruhmeshalle", "Зал славы") }
    func gymEliteLocked(have: Int, needed: Int) -> String {
        t("배지 \(needed)개가 필요해요 (\(have)/\(needed))", "Needs \(needed) badges (\(have)/\(needed))",
          "バッジが\(needed)個必要です (\(have)/\(needed))", "Necesita \(needed) medallas (\(have)/\(needed))",
          "Il faut \(needed) badges (\(have)/\(needed))", "Precisa de \(needed) insígnias (\(have)/\(needed))",
          "Braucht \(needed) Orden (\(have)/\(needed))", "Нужно значков: \(needed) (\(have)/\(needed))")
    }
    func gymRunStepLine(_ step: Int, of steps: Int) -> String {
        t("\(step)/\(steps)번째 전투", "Battle \(step) of \(steps)", "\(step)/\(steps)戦目", "Combate \(step) de \(steps)",
          "Combat \(step) sur \(steps)", "Batalha \(step) de \(steps)", "Kampf \(step) von \(steps)", "Бой \(step) из \(steps)")
    }
    var gymRunStart: String { t("도전 시작", "Start the run", "挑戦開始", "Empezar", "Commencer", "Começar", "Starten", "Начать") }
    func gymRunContinue(_ step: Int) -> String {
        t("이어서 \(step)번째 전투", "Continue: battle \(step)", "続けて\(step)戦目", "Seguir: combate \(step)", "Continuer : combat \(step)",
          "Continuar: batalha \(step)", "Weiter: Kampf \(step)", "Дальше: бой \(step)")
    }
    var gymRunRule: String {
        t("연속 대결이에요. 전투마다 완전히 회복하고, 지면 처음부터 다시 시작해요.",
          "Battles in a row. Your team is fully healed before each one, and a loss starts the run again.",
          "連戦です。毎戦の前に全回復し、負けると最初からやり直しです。",
          "Combates seguidos. Tu equipo se cura del todo antes de cada uno y una derrota reinicia la serie.",
          "Combats à la suite. Ton équipe est soignée avant chacun ; une défaite fait recommencer.",
          "Batalhas seguidas. A equipe é curada antes de cada uma, e uma derrota recomeça a série.",
          "Kämpfe am Stück. Dein Team wird vor jedem Kampf voll geheilt, eine Niederlage startet von vorn.",
          "Бои подряд. Перед каждым боем команда полностью лечится, поражение начинает всё заново.")
    }

    // MARK: Hideout

    var gymHideoutTitle: String { t("아지트", "Hideout", "アジト", "Guarida", "Planque", "Esconderijo", "Versteck", "Логово") }

    // MARK: Unavailable and failures

    func gymUnavailable(_ reason: GymService.Unavailable) -> String {
        switch reason {
        case .notLinked:
            t("YPoke 봇을 연결하면 체육관에 도전할 수 있어요.", "Link the YPoke bot to challenge gyms.", "YPokeボットを連携するとジムに挑戦できます。",
              "Vincula el bot YPoke para retar gimnasios.", "Lie le bot YPoke pour défier les arènes.", "Vincule o bot YPoke para desafiar ginásios.",
              "Verbinde den YPoke-Bot, um Arenen herauszufordern.", "Подключите бота YPoke, чтобы бросать вызов залам.")
        case .rejected:
            t("봇이 연결 토큰을 거절했어요. 설정에서 다시 연결해 주세요.", "The bot rejected the link token. Link it again in Settings.", "ボットが連携トークンを拒否しました。設定で再連携してください。",
              "El bot rechazó el token. Vuelve a vincular en Ajustes.", "Le bot a refusé le jeton. Relie-le à nouveau dans les réglages.", "O bot recusou o token. Vincule de novo nos Ajustes.",
              "Der Bot hat den Token abgelehnt. Verbinde ihn in den Einstellungen neu.", "Бот отклонил токен. Подключите заново в настройках.")
        case .unreachable:
            t("봇에 연결할 수 없어요. 사내망에 있는지 확인해 주세요.", "Can't reach the bot. Check that you are on the office network.", "ボットに接続できません。社内ネットワークか確認してください。",
              "No se puede conectar con el bot. Comprueba que estás en la red de la oficina.", "Impossible de joindre le bot. Vérifie que tu es sur le réseau du bureau.", "Não foi possível alcançar o bot. Confira se está na rede do escritório.",
              "Der Bot ist nicht erreichbar. Prüfe, ob du im Firmennetz bist.", "Бот недоступен. Проверьте, что вы в офисной сети.")
        case .botTooOld:
            t("봇이 아직 체육관을 지원하지 않아요.", "The bot doesn't support gyms yet.", "ボットはまだジムに対応していません。",
              "El bot aún no admite gimnasios.", "Le bot ne gère pas encore les arènes.", "O bot ainda não oferece ginásios.",
              "Der Bot unterstützt noch keine Arenen.", "Бот пока не поддерживает залы.")
        }
    }

    func gymFailure(_ failure: GymService.Failure) -> String {
        switch failure {
        case .rateLimited(let seconds):
            let wait = Int(min(max(seconds, 0), 3600).rounded(.up))
            return t("너무 빨라요. \(wait)초 뒤에 다시 눌러 주세요.", "Too fast. Try again in \(wait) s.", "早すぎます。\(wait)秒後にもう一度。",
                     "Demasiado rápido. Inténtalo en \(wait) s.", "Trop rapide. Réessaie dans \(wait) s.", "Rápido demais. Tente em \(wait) s.",
                     "Zu schnell. Versuche es in \(wait) s erneut.", "Слишком быстро. Повторите через \(wait) с.")
        case .refused(let reason):
            let suffix = reason.isEmpty ? "" : " (\(reason))"
            return t("봇이 이 대결을 받지 않았어요\(suffix).", "The bot refused this battle\(suffix).", "ボットがこの対戦を受け付けませんでした\(suffix)。",
                     "El bot rechazó este combate\(suffix).", "Le bot a refusé ce combat\(suffix).", "O bot recusou esta batalha\(suffix).",
                     "Der Bot hat diesen Kampf abgelehnt\(suffix).", "Бот отклонил этот бой\(suffix).")
        case .unreachable:
            return gymUnavailable(.unreachable)
        case .botTooOld:
            return gymUnavailable(.botTooOld)
        case .failed:
            return t("대결을 끝내지 못했어요. 잠시 뒤 다시 해 주세요.", "The battle didn't finish. Try again in a moment.", "対戦を完了できませんでした。しばらくしてからやり直してください。",
                     "El combate no terminó. Inténtalo de nuevo en un momento.", "Le combat n'a pas abouti. Réessaie dans un instant.", "A batalha não terminou. Tente de novo em instantes.",
                     "Der Kampf wurde nicht beendet. Versuche es gleich noch einmal.", "Бой не завершился. Повторите чуть позже.")
        }
    }

    // MARK: Result

    var gymWon: String { t("승리!", "Victory!", "勝利!", "¡Victoria!", "Victoire !", "Vitória!", "Sieg!", "Победа!") }
    var gymLost: String { t("패배", "Defeat", "敗北", "Derrota", "Défaite", "Derrota", "Niederlage", "Поражение") }
    func gymTurnCount(_ turns: Int) -> String {
        t("\(turns)턴", "\(turns) turns", "\(turns)ターン", "\(turns) turnos", "\(turns) tours", "\(turns) turnos", "\(turns) Runden", "\(turns) ходов")
    }
    var gymYourTeam: String { t("내 팀", "Your team", "自分のチーム", "Tu equipo", "Ton équipe", "Sua equipe", "Dein Team", "Ваша команда") }
    var gymTheirTeam: String { t("상대 팀", "Their team", "相手のチーム", "Su equipo", "Son équipe", "Equipe rival", "Gegnerteam", "Команда соперника") }
    var gymNeverSentOut: String { t("나오지 못함", "Not sent out", "出番なし", "No salió", "Pas sorti", "Não entrou", "Nicht eingesetzt", "Не выходил") }
    var gymFainted: String { t("기절", "Fainted", "ひんし", "Debilitado", "K.O.", "Desmaiou", "Besiegt", "Побеждён") }
    var gymShowLog: String { t("턴 기록 보기", "Show turn log", "ターンの記録を見る", "Ver registro", "Voir le journal", "Ver registro", "Rundenlog zeigen", "Показать журнал") }
    var gymHideLog: String { t("턴 기록 접기", "Hide turn log", "ターンの記録を閉じる", "Ocultar registro", "Masquer le journal", "Ocultar registro", "Rundenlog ausblenden", "Скрыть журнал") }
    func gymTurnHeading(_ turn: Int) -> String {
        t("\(turn)턴", "Turn \(turn)", "\(turn)ターン", "Turno \(turn)", "Tour \(turn)", "Turno \(turn)", "Runde \(turn)", "Ход \(turn)")
    }
    var gymNextBattle: String { t("다음 전투", "Next battle", "次の対戦", "Siguiente combate", "Combat suivant", "Próxima batalha", "Nächster Kampf", "Следующий бой") }
    var gymRestartRun: String { t("처음부터 다시", "Start over", "最初から", "Empezar de nuevo", "Recommencer", "Recomeçar", "Von vorn", "Заново") }
    var gymClose: String { t("닫기", "Close", "閉じる", "Cerrar", "Fermer", "Fechar", "Schließen", "Закрыть") }
    var gymRunCleared: String { t("연속 대결을 모두 이겼어요!", "You cleared the whole run!", "連戦を勝ち抜きました!", "¡Superaste toda la serie!", "Tu as terminé toute la série !", "Você venceu a série toda!", "Du hast die ganze Serie geschafft!", "Вы прошли всю серию!") }
    var gymRunLostHint: String { t("연속 대결에서 지면 처음부터 다시 시작해요.", "A loss in a run starts it again from the first battle.", "連戦で負けると最初からやり直しです。", "Una derrota reinicia la serie desde el primer combate.", "Une défaite relance la série au premier combat.", "Uma derrota recomeça a série do primeiro combate.", "Eine Niederlage startet die Serie wieder beim ersten Kampf.", "Поражение начинает серию с первого боя.") }

    // MARK: Rewards

    func gymRewardLine(_ kind: GymReward.Kind) -> String {
        switch kind {
        case .gymBadge:
            t("배지를 얻었어요!", "Badge earned!", "バッジを獲得!", "¡Medalla obtenida!", "Badge obtenu !", "Insígnia obtida!", "Orden erhalten!", "Значок получен!")
        case .hallOfFame:
            t("명예의 전당에 올랐어요!", "Entered the Hall of Fame!", "殿堂入り!", "¡Entraste en el Salón de la Fama!", "Entré au Panthéon !", "Entrou no Hall da Fama!", "In der Ruhmeshalle verewigt!", "Вы в Зале славы!")
        case .orgBadge:
            t("아지트를 무너뜨렸어요!", "Hideout cleared!", "アジトを壊滅させた!", "¡Guarida despejada!", "Planque nettoyée !", "Esconderijo limpo!", "Versteck ausgehoben!", "Логово зачищено!")
        }
    }
    func gymRewardTM(_ name: String) -> String {
        t("기술머신 \(name)", "TM \(name)", "わざマシン \(name)", "MT \(name)", "CT \(name)", "TM \(name)", "TM \(name)", "ТМ \(name)")
    }

    func gymRewardTitle(_ kind: GymReward.Kind) -> String {
        switch kind {
        case .gymBadge: t("🏅 배지 획득!", "🏅 Badge earned!", "🏅 バッジ獲得!", "🏅 ¡Medalla!", "🏅 Badge obtenu !", "🏅 Insígnia!", "🏅 Orden erhalten!", "🏅 Значок!")
        case .hallOfFame: t("🏆 명예의 전당!", "🏆 Hall of Fame!", "🏆 殿堂入り!", "🏆 ¡Salón de la Fama!", "🏆 Panthéon !", "🏆 Hall da Fama!", "🏆 Ruhmeshalle!", "🏆 Зал славы!")
        case .orgBadge: t("🕶️ 아지트 소탕!", "🕶️ Hideout cleared!", "🕶️ アジト壊滅!", "🕶️ ¡Guarida despejada!", "🕶️ Planque nettoyée !", "🕶️ Esconderijo limpo!", "🕶️ Versteck ausgehoben!", "🕶️ Логово зачищено!")
        }
    }

    func gymRewardBody(_ kind: GymReward.Kind, trainer: String, region: String, tm: String?) -> String {
        let extra = tm.map { " " + gymRewardTM($0) } ?? ""
        switch kind {
        case .gymBadge:
            return t("\(region) 관장 \(trainer)에게 이겼어요.\(extra)", "Beat \(trainer) of \(region).\(extra)", "\(region)の\(trainer)に勝ちました。\(extra)",
                     "Venciste a \(trainer) de \(region).\(extra)", "Tu as battu \(trainer) de \(region).\(extra)", "Você venceu \(trainer) de \(region).\(extra)",
                     "\(trainer) aus \(region) besiegt.\(extra)", "Вы победили: \(trainer), \(region).\(extra)")
        case .hallOfFame:
            return t("\(region) 챔피언 \(trainer)에게 이겼어요.\(extra)", "Beat \(trainer), champion of \(region).\(extra)", "\(region)のチャンピオン\(trainer)に勝ちました。\(extra)",
                     "Venciste a \(trainer), campeón de \(region).\(extra)", "Tu as battu \(trainer), maître de \(region).\(extra)", "Você venceu \(trainer), campeão de \(region).\(extra)",
                     "\(trainer), Champion von \(region), besiegt.\(extra)", "Вы победили чемпиона \(region): \(trainer).\(extra)")
        case .orgBadge:
            return t("\(region) 아지트의 두목 \(trainer)에게 이겼어요.\(extra)", "Beat \(trainer), boss of the \(region) hideout.\(extra)", "\(region)のアジトのボス\(trainer)に勝ちました。\(extra)",
                     "Venciste a \(trainer), jefe de la guarida de \(region).\(extra)", "Tu as battu \(trainer), chef de la planque de \(region).\(extra)", "Você venceu \(trainer), chefe do esconderijo de \(region).\(extra)",
                     "\(trainer), Boss des Verstecks in \(region), besiegt.\(extra)", "Вы победили босса логова \(region): \(trainer).\(extra)")
        }
    }
}
