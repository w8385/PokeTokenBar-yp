import Foundation

extension L {
    func stateMoveEffect(_ moveID: Int) -> String? {
        switch moveID {
        case 116:
            t("급소 확률 2랭크 상승", "Raises its critical-hit ratio by 2 stages", "きゅうしょ率2段階アップ",
              "Sube 2 niveles su índice de golpe crítico", "Augmente de 2 niveaux son taux de critique",
              "Aumenta em 2 estágios a chance de crítico", "Erhöht die Volltrefferquote um 2 Stufen",
              "Повышает шанс крита на 2 ступени")
        case 673:
            t("다음 턴까지 공격이 반드시 급소", "Its attacks land critical hits through the next turn",
              "次のターンまで攻撃が必ず きゅうしょ", "Sus ataques son críticos hasta el siguiente turno",
              "Ses attaques sont critiques jusqu'au tour suivant", "Seus ataques são críticos até o próximo turno",
              "Seine Attacken sind bis zur nächsten Runde Volltreffer", "Его атаки критические до следующего хода")
        case 73:
            t("매 턴 상대 HP 1/8을 빼앗음", "Drains 1/8 of the target's HP each turn", "毎ターン 相手のHPを1/8吸い取る",
              "Absorbe 1/8 de los PS del objetivo cada turno", "Draine 1/8 des PV de la cible à chaque tour",
              "Drena 1/8 dos PS do alvo a cada turno", "Entzieht dem Ziel jede Runde 1/8 seiner KP",
              "Каждый ход вытягивает 1/8 ОЗ цели") + listSeparator + grassNote
        case 171:
            t("잠든 상대 HP 매 턴 1/4 감소", "A sleeping target loses 1/4 of its HP each turn",
              "ねむっている相手のHPを毎ターン1/4減らす", "El objetivo dormido pierde 1/4 de sus PS cada turno",
              "Une cible endormie perd 1/4 de ses PV à chaque tour", "O alvo adormecido perde 1/4 dos PS a cada turno",
              "Ein schlafendes Ziel verliert jede Runde 1/4 seiner KP", "Спящая цель теряет 1/4 ОЗ каждый ход")
        case 174:
            stageEffect([("attack", 1), ("defense", 1), ("speed", -1)],
                        note: t("고스트 타입이면 HP 절반을 써서 상대 HP 매 턴 1/4 감소",
                                "a Ghost type instead pays half its HP so the target loses 1/4 each turn",
                                "ゴーストタイプはHPを半分使い 相手のHPを毎ターン1/4減らす",
                                "un tipo Fantasma paga la mitad de sus PS y el objetivo pierde 1/4 cada turno",
                                "un type Spectre paie la moitié de ses PV et la cible perd 1/4 à chaque tour",
                                "um tipo Fantasma paga metade dos PS e o alvo perde 1/4 a cada turno",
                                "ein Geist-Pokémon zahlt die Hälfte seiner KP, das Ziel verliert jede Runde 1/4",
                                "призрачный тип платит половину ОЗ, и цель теряет 1/4 каждый ход"))
        case 194:
            t("다음 행동 전에 쓰러지면 쓰러뜨린 상대도 기절", "If it faints before its next move, the attacker faints too",
              "次の行動の前に倒されると 相手も ひんし", "Si se debilita antes de su siguiente movimiento, el atacante también",
              "S'il est K.O. avant sa prochaine action, l'attaquant l'est aussi",
              "Se desmaiar antes do próximo golpe, o atacante também desmaia",
              "Wird es vor seiner nächsten Attacke besiegt, wird der Angreifer auch besiegt",
              "Если падёт до своего следующего хода, атакующий тоже падёт")
        case 288:
            t("다음 행동 전에 쓰러지면 그 기술 PP가 0", "If it faints before its next move, the move that did it loses all PP",
              "次の行動の前に倒されると その技のPPが0", "Si se debilita antes de su siguiente movimiento, ese movimiento pierde todos sus PP",
              "S'il est K.O. avant sa prochaine action, la capacité responsable perd tous ses PP",
              "Se desmaiar antes do próximo golpe, esse golpe perde todos os PP",
              "Wird es vor seiner nächsten Attacke besiegt, verliert die Attacke alle AP",
              "Если падёт до своего следующего хода, приём противника теряет все ПП")
        case 195:
            t("3턴 뒤 끝에 나와 있는 양쪽 모두 기절", "Both Pokémon out faint at the end of the third turn after",
              "3ターン後の終わりに 場の両方が ひんし", "Ambos Pokémon en combate se debilitan al final del tercer turno",
              "Les deux Pokémon au combat sont K.O. à la fin du troisième tour",
              "Os dois Pokémon em campo desmaiam ao fim do terceiro turno",
              "Beide Pokémon im Kampf werden am Ende der dritten Runde besiegt",
              "Оба покемона в бою падают в конце третьего хода")
        case 269:
            t("상대는 3턴 동안 변화 기술을 못 씀", "The target can't use status moves for 3 turns",
              "相手は3ターン 変化技を使えない", "El objetivo no puede usar movimientos de estado durante 3 turnos",
              "La cible ne peut pas utiliser de capacités de statut pendant 3 tours",
              "O alvo não pode usar golpes de status por 3 turnos", "Das Ziel kann 3 Runden lang keine Status-Attacken nutzen",
              "Цель 3 хода не может использовать приёмы статуса")
        case 227:
            t("상대는 3턴 동안 마지막에 쓴 기술만 씀", "The target repeats its last move for 3 turns",
              "相手は3ターン 最後に使った技しか使えない", "El objetivo repite su último movimiento durante 3 turnos",
              "La cible répète sa dernière capacité pendant 3 tours", "O alvo repete o último golpe por 3 turnos",
              "Das Ziel wiederholt 3 Runden lang seine letzte Attacke", "Цель 3 хода повторяет свой последний приём")
        case 50:
            t("상대가 마지막에 쓴 기술을 4턴 동안 봉인", "Disables the target's last move for 4 turns",
              "相手が最後に使った技を4ターン封じる", "Anula el último movimiento del objetivo durante 4 turnos",
              "Bloque la dernière capacité de la cible pendant 4 tours", "Bloqueia o último golpe do alvo por 4 turnos",
              "Blockiert die letzte Attacke des Ziels 4 Runden lang", "Блокирует последний приём цели на 4 хода")
        case 259:
            t("상대는 같은 기술을 연달아 못 씀", "The target can't use the same move twice in a row",
              "相手は同じ技を続けて使えない", "El objetivo no puede usar el mismo movimiento dos veces seguidas",
              "La cible ne peut pas utiliser deux fois de suite la même capacité",
              "O alvo não pode usar o mesmo golpe duas vezes seguidas",
              "Das Ziel kann nicht zweimal hintereinander dieselbe Attacke nutzen",
              "Цель не может использовать один приём дважды подряд")
        case 180:
            t("상대가 마지막에 쓴 기술 PP 4 감소", "The target's last move loses 4 PP", "相手が最後に使った技のPPを4減らす",
              "El último movimiento del objetivo pierde 4 PP", "La dernière capacité de la cible perd 4 PP",
              "O último golpe do alvo perde 4 PP", "Die letzte Attacke des Ziels verliert 4 AP",
              "Последний приём цели теряет 4 ПП")
        case 377:
            t("상대는 5턴 동안 회복 기술을 못 씀", "The target can't use healing moves for 5 turns",
              "相手は5ターン 回復技を使えない", "El objetivo no puede usar movimientos curativos durante 5 turnos",
              "La cible ne peut pas utiliser de capacités de soin pendant 5 tours",
              "O alvo não pode usar golpes de cura por 5 turnos", "Das Ziel kann 5 Runden lang keine Heilattacken nutzen",
              "Цель 5 ходов не может использовать лечащие приёмы")
        case 373:
            t("상대는 5턴 동안 지닌 도구를 못 씀", "The target can't use its held item for 5 turns",
              "相手は5ターン 持ち物を使えない", "El objetivo no puede usar su objeto durante 5 turnos",
              "La cible ne peut pas utiliser son objet pendant 5 tours", "O alvo não pode usar o item por 5 turnos",
              "Das Ziel kann 5 Runden lang sein Item nicht nutzen", "Цель 5 ходов не может использовать предмет")
        case 193, 316:
            t("상대 회피율 상승을 무시, 노말·격투 기술이 고스트 타입에 맞음",
              "Ignores the target's evasion; Normal and Fighting moves hit it if it is a Ghost type",
              "相手の かいひ上昇を無視、ノーマル・かくとう技がゴーストタイプに当たる",
              "Ignora la evasión del objetivo; los movimientos Normal y Lucha alcanzan a un tipo Fantasma",
              "Ignore l'esquive de la cible ; les capacités Normal et Combat touchent un type Spectre",
              "Ignora a evasão do alvo; golpes Normal e Lutador acertam um tipo Fantasma",
              "Ignoriert den Ausweichwert des Ziels; Normal- und Kampf-Attacken treffen ein Geist-Pokémon",
              "Игнорирует уклонение цели; обычные и боевые приёмы попадают по призрачному типу")
        case 357:
            t("상대 회피율 상승을 무시, 에스퍼 기술이 악 타입에 맞음",
              "Ignores the target's evasion; Psychic moves hit it if it is a Dark type",
              "相手の かいひ上昇を無視、エスパー技があくタイプに当たる",
              "Ignora la evasión del objetivo; los movimientos Psíquico alcanzan a un tipo Siniestro",
              "Ignore l'esquive de la cible ; les capacités Psy touchent un type Ténèbres",
              "Ignora a evasão do alvo; golpes Psíquico acertam um tipo Sombrio",
              "Ignoriert den Ausweichwert des Ziels; Psycho-Attacken treffen ein Unlicht-Pokémon",
              "Игнорирует уклонение цели; психические приёмы попадают по тёмному типу")
        case 199, 170:
            t("다음 턴까지 공격이 반드시 명중", "Its attacks never miss through the next turn",
              "次のターンまで攻撃が必ず命中", "Sus ataques no fallan hasta el siguiente turno",
              "Ses attaques ne ratent pas jusqu'au tour suivant", "Seus ataques não erram até o próximo turno",
              "Seine Attacken treffen bis zur nächsten Runde immer", "Его атаки не промахиваются до следующего хода")
        case 477:
            t("상대를 3턴 동안 띄움, 땅 기술은 무효이고 다른 공격은 반드시 명중",
              "Lifts the target for 3 turns: Ground moves miss it, other attacks never do",
              "相手を3ターン浮かせる、じめん技は無効でほかの攻撃は必ず命中",
              "Eleva al objetivo 3 turnos: los movimientos Tierra fallan y los demás aciertan",
              "Soulève la cible 3 tours : les capacités Sol échouent, les autres touchent toujours",
              "Ergue o alvo por 3 turnos: golpes Terra falham e os outros sempre acertam",
              "Hebt das Ziel 3 Runden an: Boden-Attacken verfehlen, andere treffen immer",
              "Поднимает цель на 3 хода: земляные приёмы мимо, остальные всегда попадают")
        case 393:
            t("5턴 동안 떠서 땅 기술 무효", "Floats for 5 turns, so Ground moves miss it",
              "5ターン浮いて じめん技を受けない", "Levita 5 turnos y los movimientos Tierra no le afectan",
              "Lévite 5 tours et esquive les capacités Sol", "Levita por 5 turnos e golpes Terra não o afetam",
              "Schwebt 5 Runden lang, Boden-Attacken verfehlen", "Парит 5 ходов, земляные приёмы не действуют")
        case 286:
            t("자신이 아는 기술을 상대가 못 씀", "The target can't use moves the user also knows",
              "自分が覚えている技を相手は使えない", "El objetivo no puede usar movimientos que el usuario conoce",
              "La cible ne peut pas utiliser les capacités que le lanceur connaît",
              "O alvo não pode usar golpes que o usuário conhece", "Das Ziel kann keine Attacken nutzen, die der Anwender kennt",
              "Цель не может использовать приёмы, которые знает пользователь")
        case 582:
            t("그 턴 상대 기술을 전기 타입으로, 상대보다 먼저 써야 함",
              "Turns the target's move Electric that turn; must go first",
              "そのターン 相手の技を でんきタイプにする、先に動く必要あり",
              "Vuelve Eléctrico el movimiento del objetivo ese turno; debe actuar primero",
              "Rend Électrik la capacité de la cible ce tour-ci ; doit agir en premier",
              "Torna Elétrico o golpe do alvo nesse turno; precisa agir primeiro",
              "Macht die Attacke des Ziels in der Runde zum Typ Elektro; muss zuerst handeln",
              "Делает приём цели электрическим на этот ход; нужно ходить первым")
        case 569:
            t("그 턴 노말 기술이 전기 타입이 됨", "Normal moves become Electric that turn",
              "そのターン ノーマル技が でんきタイプになる", "Los movimientos Normal se vuelven Eléctrico ese turno",
              "Les capacités Normal deviennent Électrik ce tour-ci", "Golpes Normal viram Elétrico nesse turno",
              "Normal-Attacken werden in der Runde zum Typ Elektro", "Обычные приёмы становятся электрическими на этот ход")
        case 600:
            t("그 턴 상대가 불꽃 기술을 쓰면 터져 HP 1/4 감소",
              "If the target uses a Fire move that turn, it explodes for 1/4 of its HP",
              "そのターン 相手が ほのお技を使うと爆発しHPを1/4減らす",
              "Si el objetivo usa un movimiento Fuego ese turno, explota y pierde 1/4 de sus PS",
              "Si la cible utilise une capacité Feu ce tour-ci, elle explose et perd 1/4 de ses PV",
              "Se o alvo usar um golpe Fogo nesse turno, explode e perde 1/4 dos PS",
              "Nutzt das Ziel in der Runde eine Feuer-Attacke, explodiert sie und kostet 1/4 KP",
              "Если цель применит огненный приём на этом ходу, он взорвётся и отнимет 1/4 ОЗ")
                + listSeparator + grassNote
        case 277:
            t("그 턴 받은 변화 기술을 되돌려 보냄", "Bounces status moves aimed at it back that turn",
              "そのターン 受けた変化技を はね返す", "Devuelve los movimientos de estado de ese turno",
              "Renvoie les capacités de statut reçues ce tour-ci", "Reflete os golpes de status recebidos nesse turno",
              "Wirft Status-Attacken in der Runde zurück", "Отражает приёмы статуса на этом ходу")
        case 289:
            t("그 턴 상대가 자신에게 쓰는 변화 기술을 가로챔", "Steals the target's self-targeting status move that turn",
              "そのターン 相手が自分に使う変化技を横取りする",
              "Roba el movimiento de estado que el objetivo use sobre sí ese turno",
              "Vole la capacité de statut que la cible utilise sur elle-même ce tour-ci",
              "Rouba o golpe de status que o alvo usa em si nesse turno",
              "Stiehlt in der Runde die Status-Attacke, die das Ziel auf sich selbst nutzt",
              "Перехватывает приём статуса, который цель применяет на себя, на этом ходу")
        case 753:
            t("매 턴 상대 방어·특수방어 1랭크 하락", "The target loses 1 Defense and Sp. Def stage each turn",
              "毎ターン 相手の ぼうぎょ・とくぼう1段階ダウン",
              "El objetivo pierde 1 nivel de Defensa y Def. Esp. cada turno",
              "La cible perd 1 niveau de Défense et Déf. Spé. à chaque tour",
              "O alvo perde 1 estágio de Defesa e Def. Esp. a cada turno",
              "Das Ziel verliert jede Runde 1 Stufe Verteidigung und Sp.-Vert.",
              "Цель каждый ход теряет 1 ступень защиты и спецзащиты")
        case 749:
            stageEffect([("speed", -1)], foe: true,
                        note: t("불꽃 기술 피해 2배", "Fire moves deal double damage to it", "ほのお技のダメージ2倍",
                                "los movimientos Fuego le hacen el doble", "les capacités Feu lui infligent le double",
                                "golpes Fogo causam o dobro", "Feuer-Attacken richten doppelten Schaden an",
                                "огненные приёмы наносят двойной урон"))
        case 300:
            t("5턴 동안 전기 기술 위력 1/3", "Electric moves have 1/3 power for 5 turns", "5ターン でんき技の威力1/3",
              "Los movimientos Eléctrico tienen 1/3 de potencia durante 5 turnos",
              "Les capacités Électrik ont 1/3 de puissance pendant 5 tours",
              "Golpes Elétrico têm 1/3 do poder por 5 turnos", "Elektro-Attacken haben 5 Runden lang 1/3 Stärke",
              "Электрические приёмы 5 ходов имеют 1/3 силы")
        case 346:
            t("5턴 동안 불꽃 기술 위력 1/3", "Fire moves have 1/3 power for 5 turns", "5ターン ほのお技の威力1/3",
              "Los movimientos Fuego tienen 1/3 de potencia durante 5 turnos",
              "Les capacités Feu ont 1/3 de puissance pendant 5 tours",
              "Golpes Fogo têm 1/3 do poder por 5 turnos", "Feuer-Attacken haben 5 Runden lang 1/3 Stärke",
              "Огненные приёмы 5 ходов имеют 1/3 силы")
        default: nil
        }
    }

    private var listSeparator: String {
        t(", ", ", ", "、", ", ", ", ", ", ", ", ", ", ")
    }
}
