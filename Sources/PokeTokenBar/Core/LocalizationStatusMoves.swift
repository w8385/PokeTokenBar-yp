import Foundation

extension L {
    func moreStatusMoveEffect(_ moveID: Int) -> String? {
        switch moveID {
        case 96, 159, 336: stageEffect([("attack", 1)])
        case 97, 397, 475: stageEffect([("speed", 2)])
        case 104: stageEffect([("evasion", 1)])
        case 107: stageEffect([("evasion", 2)])
        case 106, 110, 111: stageEffect([("defense", 1)])
        case 112, 151, 334, 842: stageEffect([("defense", 2)])
        case 538: stageEffect([("defense", 3)])
        case 133: stageEffect([("special_defense", 2)])
        case 294: stageEffect([("special_attack", 3)])
        case 417: stageEffect([("special_attack", 2)])
        case 322, 455: stageEffect([("defense", 1), ("special_defense", 1)])
        case 339: stageEffect([("attack", 1), ("defense", 1)])
        case 347: stageEffect([("special_attack", 1), ("special_defense", 1)])
        case 349: stageEffect([("attack", 1), ("speed", 1)])
        case 468: stageEffect([("attack", 1), ("accuracy", 1)])
        case 483: stageEffect([("special_attack", 1), ("special_defense", 1), ("speed", 1)])
        case 489: stageEffect([("attack", 1), ("defense", 1), ("accuracy", 1)])
        case 504: stageEffect([("attack", 2), ("special_attack", 2), ("speed", 2), ("defense", -1), ("special_defense", -1)])
        case 508: stageEffect([("attack", 1), ("speed", 2)])
        case 526: stageEffect([("attack", 1), ("special_attack", 1)])
        case 601: stageEffect([("special_attack", 2), ("special_defense", 2), ("speed", 2)])
        case 837: stageEffect([("attack", 1), ("defense", 1), ("speed", 1)])
        case 187:
            t("HP 절반을 써서 공격 최대 상승", "Pays half its HP to max out Attack", "HPを半分使い こうげきを最大まで上げる",
              "Usa la mitad de sus PS para maximizar el Ataque", "Sacrifie la moitié de ses PV pour maximiser l'Attaque",
              "Gasta metade dos PS para maximizar o Ataque", "Opfert die Hälfte der KP für maximalen Angriff",
              "Тратит половину ОЗ, чтобы поднять атаку до максимума")
        case 868: stageEffect([("attack", 2), ("special_attack", 2), ("speed", 2)], note: hpCost(2))
        case 775: stageEffect(allFive(1), note: hpCost(3))
        case 74:
            stageEffect([("attack", 1), ("special_attack", 1)],
                        note: t("쾌청이면 2배", "doubled in sun", "ひざしが強いと2倍", "doble con sol", "doublé au soleil",
                                "dobro com sol", "doppelt bei Sonne", "вдвое при солнце"))
        case 254:
            stageEffect([("defense", 1), ("special_defense", 1)],
                        note: t("3번까지", "up to 3 times", "3回まで", "hasta 3 veces", "jusqu'à 3 fois", "até 3 vezes",
                                "bis zu 3-mal", "до 3 раз"))
        case 268:
            stageEffect([("special_defense", 1)],
                        note: t("다음 턴까지 전기 기술 2배", "Electric moves doubled through next turn",
                                "次のターンまで でんきわざ2倍", "movimientos Eléctricos x2 hasta el siguiente turno",
                                "capacités Électrik x2 jusqu'au tour suivant", "golpes Elétricos x2 até o próximo turno",
                                "Elektro-Attacken x2 bis zur nächsten Runde", "электроприёмы x2 до следующего хода"))
        case 748:
            stageEffect(allFive(1), note: t("한 번만", "once", "1回だけ", "una vez", "une fois", "uma vez", "einmal", "один раз"))
        case 850:
            stageEffect([("special_attack", 1), ("special_defense", 1)],
                        note: t("상태이상 회복", "cures its status", "状態異常を治す", "cura su estado", "soigne son statut",
                                "cura seu status", "heilt Statusprobleme", "лечит статус"))
        case 602, 674:
            stageEffect(moveID == 602 ? [("defense", 1), ("special_defense", 1)] : [("attack", 1), ("special_attack", 1)],
                        note: t("특성 플러스·마이너스만", "only with Plus or Minus", "とくせい プラス・マイナスのみ",
                                "solo con Más o Menos", "seulement avec Plus ou Minus", "só com Mais ou Menos",
                                "nur mit Plus oder Minus", "только со способностью Плюс или Минус"))
        case 579, 563:
            stageEffect(moveID == 579 ? [("defense", 1)] : [("attack", 1), ("special_attack", 1)],
                        note: t("필드의 풀 타입 모두", "every Grass type on the field", "場の くさタイプ全員",
                                "todos los tipo Planta en el campo", "tous les Pokémon Plante du terrain",
                                "todos os tipo Planta em campo", "alle Pflanzen-Pokémon im Feld",
                                "все травяные покемоны на поле"))
        case 599:
            stageEffect([("attack", -1), ("special_attack", -1), ("speed", -1)], foe: true,
                        note: t("독 상태일 때만", "only if poisoned", "どく状態のときだけ", "solo si está envenenado",
                                "seulement s'il est empoisonné", "só se estiver envenenado", "nur wenn vergiftet",
                                "только если отравлена"))
        case 367:
            t("무작위 능력 하나 2랭크 상승", "A random stat +2 stages", "ランダムな能力1つが2段階アップ",
              "Una característica al azar +2 niveles", "Une stat au hasard +2 niveaux", "Um atributo aleatório +2 estágios",
              "Ein zufälliger Wert +2 Stufen", "Случайная характеристика +2 ступени")
        case 28, 108, 134, 148: stageEffect([("accuracy", -1)], foe: true)
        case 39, 43: stageEffect([("defense", -1)], foe: true)
        case 45, 589, 608: stageEffect([("attack", -1)], foe: true)
        case 81, 178, 184: stageEffect([("speed", -2)], foe: true)
        case 103: stageEffect([("defense", -2)], foe: true)
        case 204, 297: stageEffect([("attack", -2)], foe: true)
        case 230: stageEffect([("evasion", -2)], foe: true)
        case 313, 319: stageEffect([("special_defense", -2)], foe: true)
        case 321: stageEffect([("attack", -1), ("defense", -1)], foe: true)
        case 568, 715: stageEffect([("attack", -1), ("special_attack", -1)], foe: true)
        case 590: stageEffect([("special_attack", -1)], foe: true)
        case 598: stageEffect([("special_attack", -2)], foe: true)
        case 858: stageEffect([("attack", 2), ("defense", -2)], foe: true)
        case 777: stageEffect([("attack", 2), ("special_attack", 2)], foe: true)
        case 244:
            t("상대의 능력 변화를 복사", "Copies the target's stat changes", "相手の能力変化をコピー",
              "Copia los cambios de características del objetivo", "Copie les changements de stats de la cible",
              "Copia as mudanças de atributos do alvo", "Kopiert die Wertänderungen des Ziels",
              "Копирует изменения характеристик цели")
        case 576:
            t("상대의 능력 변화를 뒤집음", "Inverts the target's stat changes", "相手の能力変化を逆にする",
              "Invierte los cambios de características del objetivo", "Inverse les changements de stats de la cible",
              "Inverte as mudanças de atributos do alvo", "Kehrt die Wertänderungen des Ziels um",
              "Обращает изменения характеристик цели")
        case 384:
            t("상대와 공격·특공 랭크 교환", "Swaps Attack and Sp. Atk changes with the target",
              "相手と こうげき・とくこうの変化を入れ替える", "Intercambia los cambios de Ataque y At. Esp. con el objetivo",
              "Échange les changements d'Attaque et d'Atq. Spé. avec la cible",
              "Troca as mudanças de Ataque e Atq. Esp. com o alvo",
              "Tauscht Angriffs- und Sp.-Ang.-Änderungen mit dem Ziel",
              "Меняется с целью изменениями атаки и сп. атаки")
        case 385:
            t("상대와 방어·특방 랭크 교환", "Swaps Defense and Sp. Def changes with the target",
              "相手と ぼうぎょ・とくぼうの変化を入れ替える", "Intercambia los cambios de Defensa y Def. Esp. con el objetivo",
              "Échange les changements de Défense et de Déf. Spé. avec la cible",
              "Troca as mudanças de Defesa e Def. Esp. com o alvo",
              "Tauscht Verteidigungs- und Sp.-Vert.-Änderungen mit dem Ziel",
              "Меняется с целью изменениями защиты и сп. защиты")
        case 391:
            t("상대와 모든 능력 변화 교환", "Swaps every stat change with the target", "相手と すべての能力変化を入れ替える",
              "Intercambia todos los cambios de características con el objetivo",
              "Échange tous les changements de stats avec la cible", "Troca todas as mudanças de atributos com o alvo",
              "Tauscht alle Wertänderungen mit dem Ziel", "Меняется с целью всеми изменениями характеристик")
        case 683:
            t("상대와 스피드 실수치 교환", "Swaps Speed stats with the target", "相手と すばやさの実数値を入れ替える",
              "Intercambia la Velocidad con el objetivo", "Échange la Vitesse avec la cible", "Troca a Velocidade com o alvo",
              "Tauscht den Initiative-Wert mit dem Ziel", "Меняется с целью скоростью")
        case 471:
            t("상대와 공격·특공 실수치를 평균", "Averages Attack and Sp. Atk with the target",
              "相手と こうげき・とくこうの実数値を平均する", "Promedia Ataque y At. Esp. con el objetivo",
              "Fait la moyenne de l'Attaque et de l'Atq. Spé. avec la cible", "Tira a média de Ataque e Atq. Esp. com o alvo",
              "Mittelt Angriff und Sp.-Ang. mit dem Ziel", "Усредняет с целью атаку и сп. атаку")
        case 470:
            t("상대와 방어·특방 실수치를 평균", "Averages Defense and Sp. Def with the target",
              "相手と ぼうぎょ・とくぼうの実数値を平均する", "Promedia Defensa y Def. Esp. con el objetivo",
              "Fait la moyenne de la Défense et de la Déf. Spé. avec la cible", "Tira a média de Defesa e Def. Esp. com o alvo",
              "Mittelt Verteidigung und Sp.-Vert. mit dem Ziel", "Усредняет с целью защиту и сп. защиту")
        case 379, 829:
            t("자신의 공격과 방어 실수치를 바꿈", "Swaps its own Attack and Defense", "自分の こうげきと ぼうぎょを入れ替える",
              "Intercambia su Ataque y su Defensa", "Échange son Attaque et sa Défense", "Troca seu Ataque e sua Defesa",
              "Tauscht eigenen Angriff und Verteidigung", "Меняет местами свою атаку и защиту")
        case 105, 135, 208, 303, 456: healShare(2)
        case 791: healShare(4)
        case 816, 849:
            healShare(4) + t(", 상태이상 회복", ", cures its status", "、状態異常を治す", ", cura su estado", ", soigne son statut",
                             ", cura seu status", ", heilt Statusprobleme", ", лечит статус")
        case 234, 235, 236:
            t("HP 1/2 회복 (쾌청 2/3, 다른 날씨 1/4)", "Heals 1/2 HP (2/3 in sun, 1/4 in other weather)",
              "HPを1/2回復(晴れ2/3、ほかの天気1/4)", "Cura 1/2 de PS (2/3 con sol, 1/4 con otro clima)",
              "Soigne 1/2 des PV (2/3 au soleil, 1/4 sous un autre climat)",
              "Cura 1/2 dos PS (2/3 com sol, 1/4 em outro clima)", "Heilt 1/2 KP (2/3 bei Sonne, 1/4 bei anderem Wetter)",
              "Восстанавливает 1/2 ОЗ (2/3 при солнце, 1/4 при другой погоде)")
        case 659:
            t("HP 1/2 회복 (모래바람 2/3)", "Heals 1/2 HP (2/3 in a sandstorm)", "HPを1/2回復(すなあらし2/3)",
              "Cura 1/2 de PS (2/3 en tormenta de arena)", "Soigne 1/2 des PV (2/3 dans une tempête de sable)",
              "Cura 1/2 dos PS (2/3 em tempestade de areia)", "Heilt 1/2 KP (2/3 im Sandsturm)",
              "Восстанавливает 1/2 ОЗ (2/3 в песчаную бурю)")
        case 355:
            healShare(2) + t(", 그 턴 비행 타입을 잃음", ", loses its Flying type that turn", "、そのターン ひこうタイプを失う",
                             ", pierde el tipo Volador ese turno", ", perd le type Vol ce tour-ci",
                             ", perde o tipo Voador nesse turno", ", verliert in der Runde den Typ Flug",
                             ", теряет летающий тип на этот ход")
        case 256:
            t("비축한 만큼 HP 회복 후 비축 해제", "Heals HP by its Stockpile count, then spends it",
              "たくわえた分だけHPを回復し たくわえを解く", "Cura PS según lo Reservado y lo gasta",
              "Soigne des PV selon la Stockage et la dépense", "Cura PS conforme o Estocado e o gasta",
              "Heilt KP je nach Horter-Zahl und verbraucht sie", "Лечит ОЗ по числу запасов и тратит их")
        case 273:
            t("다음 턴 끝에 HP 1/2 회복", "Heals 1/2 HP at the end of next turn", "次のターンの終わりにHPを1/2回復",
              "Cura 1/2 de PS al final del siguiente turno", "Soigne 1/2 des PV à la fin du tour suivant",
              "Cura 1/2 dos PS no fim do próximo turno", "Heilt 1/2 KP am Ende der nächsten Runde",
              "Восстанавливает 1/2 ОЗ в конце следующего хода")
        case 505, 666:
            t("상대의 HP를 1/2 회복", "Heals the target by 1/2 of its HP", "相手のHPを1/2回復", "Cura 1/2 de PS al objetivo",
              "Soigne la cible de 1/2 de ses PV", "Cura 1/2 dos PS do alvo", "Heilt das Ziel um 1/2 seiner KP",
              "Восстанавливает цели 1/2 ОЗ")
        case 685:
            t("상대의 상태이상을 고치고 HP 1/2 회복", "Cures the target's status and heals 1/2 HP",
              "相手の状態異常を治し HPを1/2回復", "Cura el estado del objetivo y recupera 1/2 de PS",
              "Soigne le statut de la cible et récupère 1/2 des PV", "Cura o status do alvo e recupera 1/2 dos PS",
              "Heilt den Status des Ziels und 1/2 eigene KP", "Лечит статус цели и восстанавливает 1/2 ОЗ")
        case 668:
            t("상대 공격만큼 HP 회복, 상대 공격 1랭크 하락", "Heals by the target's Attack; Target: Attack −1 stage",
              "相手のこうげき分HPを回復、相手のこうげき1段階ダウン", "Cura según el Ataque del objetivo; Objetivo: Ataque −1 nivel",
              "Soigne selon l'Attaque de la cible ; Cible : Attaque −1 niveau",
              "Cura conforme o Ataque do alvo; Alvo: Ataque −1 estágio",
              "Heilt um den Angriff des Ziels; Ziel: Angriff −1 Stufe", "Лечит на атаку цели; Цель: атака −1 ступень")
        case 220:
            t("상대와 HP를 똑같이 나눔", "Shares HP evenly with the target", "相手とHPを等しく分け合う",
              "Reparte los PS a partes iguales con el objetivo", "Partage équitablement les PV avec la cible",
              "Divide os PS igualmente com o alvo", "Teilt die KP gleichmäßig mit dem Ziel", "Делит ОЗ поровну с целью")
        case 156:
            t("HP 전부 회복 후 2턴 잠듦", "Fully heals, then sleeps 2 turns", "HPを全回復し 2ターン眠る",
              "Se cura por completo y duerme 2 turnos", "Récupère tous ses PV et dort 2 tours",
              "Cura tudo e dorme 2 turnos", "Heilt alle KP und schläft 2 Runden", "Полностью лечится и спит 2 хода")
        case 392, 275:
            t("매 턴 HP 1/16 회복", "Heals 1/16 HP every turn", "毎ターンHPを1/16回復", "Cura 1/16 de PS cada turno",
              "Soigne 1/16 des PV à chaque tour", "Cura 1/16 dos PS a cada turno", "Heilt jede Runde 1/16 KP",
              "Восстанавливает 1/16 ОЗ каждый ход")
              + (moveID == 275
                 ? t(", 땅에 뿌리박음", ", roots it to the ground", "、地面に根を張る", ", echa raíces en el suelo",
                     ", s'enracine au sol", ", cria raízes no chão", ", schlägt Wurzeln", ", пускает корни")
                 : "")
        case 215, 312:
            t("우리 편 전원의 상태이상 회복", "Cures the status of the whole team", "味方全員の状態異常を治す",
              "Cura el estado de todo el equipo", "Soigne le statut de toute l'équipe", "Cura o status de toda a equipe",
              "Heilt den Status des ganzen Teams", "Лечит статус всей команды")
        case 287:
            t("화상·독·마비 회복", "Cures a burn, poison or paralysis", "やけど・どく・まひを治す",
              "Cura quemadura, veneno o parálisis", "Soigne brûlure, poison ou paralysie",
              "Cura queimadura, veneno ou paralisia", "Heilt Verbrennung, Gift oder Paralyse",
              "Лечит ожог, отравление или паралич")
        case 361, 461:
            t("기절하고 다음 포켓몬의 HP·상태이상 회복", "Faints to fully heal the next Pokémon",
              "ひんしになり 次のポケモンを全回復", "Se debilita para curar del todo al siguiente Pokémon",
              "Tombe K.O. pour soigner entièrement le Pokémon suivant",
              "Desmaia para curar totalmente o próximo Pokémon", "Wird besiegt und heilt das nächste Pokémon voll",
              "Падает, полностью исцеляя следующего покемона")
        case 863:
            t("기절한 동료 하나를 HP 1/2로 부활", "Revives a fainted teammate at 1/2 HP", "ひんしの仲間をHP1/2で復活",
              "Revive a un compañero debilitado con 1/2 de PS", "Ranime un allié K.O. avec 1/2 des PV",
              "Revive um aliado desmaiado com 1/2 dos PS", "Belebt ein besiegtes Teammitglied mit 1/2 KP wieder",
              "Оживляет павшего союзника с 1/2 ОЗ")
        case 262:
            stageEffect([("attack", -2), ("special_attack", -2)], foe: true,
                        note: t("자신은 기절", "the user faints", "自分は ひんし", "el usuario se debilita",
                                "le lanceur tombe K.O.", "o usuário desmaia", "der Anwender wird besiegt",
                                "пользователь падает"))
        default: nil
        }
    }

    func stageEffect(_ changes: [(String, Int)], foe: Bool = false, note: String? = nil) -> String {
        var groups: [(stats: [String], delta: Int)] = []
        for (stat, delta) in changes {
            if let index = groups.firstIndex(where: { $0.delta == delta }) {
                groups[index].stats.append(stat)
            } else {
                groups.append(([stat], delta))
            }
        }
        let body = groups.map { stageGroup($0.stats, $0.delta) }
            .joined(separator: t(", ", "; ", "、", "; ", " ; ", "; ", "; ", "; "))
        let aimed = foe
            ? t("상대 \(body)", "Target: \(body)", "相手の\(body)", "Objetivo: \(body)", "Cible : \(body)",
                "Alvo: \(body)", "Ziel: \(body)", "Цель: \(body)")
            : body
        guard let note else { return aimed }
        return aimed + t(", ", ", ", "、", ", ", ", ", ", ", ", ", ", ") + note
    }

    private func stageGroup(_ stats: [String], _ delta: Int) -> String {
        let names = stats.map(stageName).joined(separator: t("·", ", ", "・", ", ", ", ", ", ", ", ", ", "))
        let count = abs(delta)
        let signed = "\(delta > 0 ? "+" : "−")\(count)"
        return t("\(names) \(count)랭크 \(delta > 0 ? "상승" : "하락")",
                 "\(names) \(signed) \(count == 1 ? "stage" : "stages")",
                 "\(names)\(count)段階\(delta > 0 ? "アップ" : "ダウン")",
                 "\(names) \(signed) \(count == 1 ? "nivel" : "niveles")",
                 "\(names) \(signed) \(count == 1 ? "niveau" : "niveaux")",
                 "\(names) \(signed) \(count == 1 ? "estágio" : "estágios")",
                 "\(names) \(signed) \(count == 1 ? "Stufe" : "Stufen")",
                 "\(names) \(signed) \(count == 1 ? "ступень" : count < 5 ? "ступени" : "ступеней")")
    }

    private func stageName(_ stat: String) -> String {
        switch stat {
        case "accuracy": t("명중률", "Accuracy", "めいちゅう", "Precisión", "Précision", "Precisão", "Genauigkeit", "Точность")
        case "evasion": t("회피율", "Evasion", "かいひ", "Evasión", "Esquive", "Evasão", "Ausweichen", "Уклонение")
        default: statLabel(stat.replacingOccurrences(of: "_", with: "-"))
        }
    }

    private func hpCost(_ share: Int) -> String {
        t("HP 1/\(share) 소모", "costs 1/\(share) of its HP", "HPを1/\(share)消費", "cuesta 1/\(share) de sus PS",
          "coûte 1/\(share) de ses PV", "custa 1/\(share) dos PS", "kostet 1/\(share) der KP", "стоит 1/\(share) ОЗ")
    }

    private func healShare(_ share: Int) -> String {
        t("HP 1/\(share) 회복", "Heals 1/\(share) of its HP", "HPを1/\(share)回復", "Cura 1/\(share) de sus PS",
          "Soigne 1/\(share) de ses PV", "Cura 1/\(share) dos PS", "Heilt 1/\(share) der KP", "Восстанавливает 1/\(share) ОЗ")
    }

    private func allFive(_ delta: Int) -> [(String, Int)] {
        ["attack", "defense", "special_attack", "special_defense", "speed"].map { ($0, delta) }
    }
}
