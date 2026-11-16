import Foundation

/// Effect text of the held items beyond the first seven, and the type names they mention.
extension L {
    func battleTypeName(_ type: String) -> String {
        switch type {
        case "normal": t("노말", "Normal", "ノーマル", "Normal", "Normal", "Normal", "Normal", "Нормальный")
        case "fire": t("불꽃", "Fire", "ほのお", "Fuego", "Feu", "Fogo", "Feuer", "Огонь")
        case "water": t("물", "Water", "みず", "Agua", "Eau", "Água", "Wasser", "Вода")
        case "electric": t("전기", "Electric", "でんき", "Eléctrico", "Électrik", "Elétrico", "Elektro", "Электричество")
        case "grass": t("풀", "Grass", "くさ", "Planta", "Plante", "Planta", "Pflanze", "Трава")
        case "ice": t("얼음", "Ice", "こおり", "Hielo", "Glace", "Gelo", "Eis", "Лёд")
        case "fighting": t("격투", "Fighting", "かくとう", "Lucha", "Combat", "Lutador", "Kampf", "Боевой")
        case "poison": t("독", "Poison", "どく", "Veneno", "Poison", "Veneno", "Gift", "Яд")
        case "ground": t("땅", "Ground", "じめん", "Tierra", "Sol", "Terrestre", "Boden", "Земля")
        case "flying": t("비행", "Flying", "ひこう", "Volador", "Vol", "Voador", "Flug", "Летающий")
        case "psychic": t("에스퍼", "Psychic", "エスパー", "Psíquico", "Psy", "Psíquico", "Psycho", "Психический")
        case "bug": t("벌레", "Bug", "むし", "Bicho", "Insecte", "Inseto", "Käfer", "Жук")
        case "rock": t("바위", "Rock", "いわ", "Roca", "Roche", "Pedra", "Gestein", "Камень")
        case "ghost": t("고스트", "Ghost", "ゴースト", "Fantasma", "Spectre", "Fantasma", "Geist", "Призрак")
        case "dragon": t("드래곤", "Dragon", "ドラゴン", "Dragón", "Dragon", "Dragão", "Drache", "Дракон")
        case "dark": t("악", "Dark", "あく", "Siniestro", "Ténèbres", "Sombrio", "Unlicht", "Тёмный")
        case "steel": t("강철", "Steel", "はがね", "Acero", "Acier", "Aço", "Stahl", "Сталь")
        default: t("페어리", "Fairy", "フェアリー", "Hada", "Fée", "Fada", "Fee", "Фея")
        }
    }

    func typeBoostEffect(_ type: String) -> String {
        let name = battleTypeName(type)
        return t("\(name)타입 기술의 데미지가 1.2배.", "\(name)-type moves deal ×1.2 damage.",
                 "\(name)タイプの技のダメージが1.2倍。", "Los movimientos de tipo \(name) hacen ×1,2 de daño.",
                 "Les attaques de type \(name) font ×1,2 de dégâts.", "Golpes do tipo \(name) causam ×1,2 de dano.",
                 "\(name)-Attacken richten ×1,2 Schaden an.", "Атаки типа \(name) наносят ×1,2 урона.")
    }

    func moreHeldItemEffect(_ kind: ItemKind) -> String {
        if let type = kind.boostedType { return typeBoostEffect(type) }
        if kind.maskEntryStat != nil { return maskEffect(kind) }
        switch kind {
        case .stellarCrystal:
            return stellarCrystalEffect
        case .everstone:
            let name = itemName(.everstone)
            return t("\(name): 진화하지 않아요", "\(name): won't evolve", "\(name): 進化しません",
                     "\(name): no evoluciona", "\(name) : n'évolue pas", "\(name): não evolui",
                     "\(name): entwickelt sich nicht", "\(name): не эволюционирует")
        case .choiceSpecs:
            return t("특공이 1.5배. 처음 쓴 기술만 쓸 수 있어요.", "Sp. Atk ×1.5, but locks into the first move used.",
                     "特攻が1.5倍。最初に使った技しか出せません。", "Ataq. Esp. ×1,5, pero se queda con el primer movimiento.",
                     "Atq. Spé. ×1,5, mais bloqué sur la première attaque.", "Atq. Esp. ×1,5, mas fica preso ao primeiro golpe.",
                     "Spezial-Angriff ×1,5, aber nur die erste Attacke ist erlaubt.",
                     "Спец. атака ×1,5, но доступна только первая применённая атака.")
        case .assaultVest:
            return t("특방이 1.5배. 날씨를 바꾸는 기술은 쓸 수 없어요.", "Sp. Def ×1.5, but weather-setting moves can't be used.",
                     "特防が1.5倍。天気を変える技は出せません。", "Def. Esp. ×1,5, pero no puede usar movimientos que cambian el clima.",
                     "Déf. Spé. ×1,5, mais ne peut pas utiliser d'attaques météo.",
                     "Def. Esp. ×1,5, mas não pode usar golpes que mudam o clima.",
                     "Spezial-Verteidigung ×1,5, aber Wetterattacken sind gesperrt.",
                     "Спец. защита ×1,5, но погодные атаки использовать нельзя.")
        case .eviolite:
            return t("아직 진화할 수 있는 포켓몬은 방어와 특방이 1.5배.", "If the holder can still evolve, Def and Sp. Def ×1.5.",
                     "まだ進化できるポケモンは、防御と特防が1.5倍。", "Si aún puede evolucionar, Defensa y Def. Esp. ×1,5.",
                     "Si le porteur peut encore évoluer, Défense et Déf. Spé. ×1,5.",
                     "Se ainda puder evoluir, Defesa e Def. Esp. ×1,5.",
                     "Kann der Träger sich noch entwickeln, Verteidigung und Spez.-Vert. ×1,5.",
                     "Если носитель ещё может эволюционировать, Защита и Спец. защита ×1,5.")
        case .rockyHelmet:
            return t("물리 공격을 받으면 공격한 상대의 최대 HP의 1/6을 깎아요.",
                     "Deals 1/6 of the attacker's max HP when hit by a physical move.",
                     "物理技を受けると、相手の最大HPの1/6のダメージを与えます。",
                     "Si recibe un golpe físico, quita 1/6 de los PS máx. del atacante.",
                     "Si touché par une attaque physique, inflige 1/6 des PV max de l'attaquant.",
                     "Ao receber um golpe físico, tira 1/6 do HP máx. do atacante.",
                     "Bei einer physischen Attacke verliert der Angreifer 1/6 seiner max. KP.",
                     "При физической атаке отнимает у атакующего 1/6 макс. HP.")
        case .sitrusBerry:
            return t("HP가 절반 이하가 되면 한 번 최대 HP의 1/4을 회복해요.",
                     "Once, restores 1/4 of max HP when HP falls to half or less.",
                     "HPが半分以下になると、一度だけ最大HPの1/4を回復します。",
                     "Una vez, recupera 1/4 de los PS máx. cuando los PS bajan a la mitad o menos.",
                     "Une fois, restaure 1/4 des PV max quand les PV tombent à la moitié ou moins.",
                     "Uma vez, restaura 1/4 do HP máx. quando o HP cai para metade ou menos.",
                     "Heilt einmalig 1/4 der max. KP, wenn die KP auf die Hälfte oder weniger sinken.",
                     "Один раз восстанавливает 1/4 макс. HP, когда HP падает до половины или ниже.")
        case .lumBerry:
            return t("상태이상이나 혼란에 걸리면 한 번 회복해요.", "Once, cures a status condition or confusion.",
                     "状態異常やこんらんになると、一度だけ治します。", "Una vez, cura un problema de estado o la confusión.",
                     "Une fois, soigne un statut ou la confusion.", "Uma vez, cura uma condição de status ou confusão.",
                     "Heilt einmalig eine Zustandsveränderung oder Verwirrung.",
                     "Один раз лечит негативный статус или смятение.")
        case .whiteHerb:
            return t("깎인 능력치가 있으면 한 번 원래대로 되돌려요.", "Once, resets any lowered stats.",
                     "能力が下がると、一度だけ元に戻します。", "Una vez, restablece las estadísticas reducidas.",
                     "Une fois, rétablit les stats baissées.", "Uma vez, restaura os atributos reduzidos.",
                     "Setzt gesenkte Werte einmalig zurück.", "Один раз сбрасывает сниженные характеристики.")
        case .blackSludge:
            return t("독타입은 매 턴 끝에 최대 HP의 1/16을 회복하고, 다른 타입은 1/8을 잃어요.",
                     "Poison types restore 1/16 of max HP each turn; other types lose 1/8.",
                     "どくタイプは毎ターン最大HPの1/16を回復。ほかのタイプは1/8を失います。",
                     "El tipo Veneno recupera 1/16 de los PS máx. cada turno; los demás pierden 1/8.",
                     "Les types Poison restaurent 1/16 des PV max par tour ; les autres perdent 1/8.",
                     "Tipo Veneno restaura 1/16 do HP máx. por turno; os outros perdem 1/8.",
                     "Gift-Pokémon heilen jede Runde 1/16 der max. KP, andere verlieren 1/8.",
                     "Покемоны типа Яд восстанавливают 1/16 макс. HP за ход, остальные теряют 1/8.")
        case .shellBell:
            return t("준 데미지의 1/8만큼 HP를 회복해요.", "Restores HP equal to 1/8 of the damage dealt.",
                     "与えたダメージの1/8だけHPを回復します。", "Recupera PS equivalentes a 1/8 del daño infligido.",
                     "Restaure des PV égaux à 1/8 des dégâts infligés.", "Restaura HP igual a 1/8 do dano causado.",
                     "Heilt KP in Höhe von 1/8 des verursachten Schadens.",
                     "Восстанавливает HP в размере 1/8 нанесённого урона.")
        case .bigRoot:
            return t("흡수 기술로 회복하는 양이 1.3배.", "HP restored by draining moves ×1.3.",
                     "HPを吸い取る技で回復する量が1.3倍。", "Los PS recuperados con movimientos de drenaje ×1,3.",
                     "Les PV récupérés par les attaques de drain ×1,3.", "O HP recuperado por golpes de drenagem ×1,3.",
                     "Durch Absorb-Attacken geheilte KP ×1,3.", "Восстановление HP от поглощающих атак ×1,3.")
        case .muscleBand:
            return t("물리 기술의 데미지가 1.1배.", "Physical moves deal ×1.1 damage.",
                     "物理技のダメージが1.1倍。", "Los movimientos físicos hacen ×1,1 de daño.",
                     "Les attaques physiques font ×1,1 de dégâts.", "Golpes físicos causam ×1,1 de dano.",
                     "Physische Attacken richten ×1,1 Schaden an.", "Физические атаки наносят ×1,1 урона.")
        case .wiseGlasses:
            return t("특수 기술의 데미지가 1.1배.", "Special moves deal ×1.1 damage.",
                     "特殊技のダメージが1.1倍。", "Los movimientos especiales hacen ×1,1 de daño.",
                     "Les attaques spéciales font ×1,1 de dégâts.", "Golpes especiais causam ×1,1 de dano.",
                     "Spezielle Attacken richten ×1,1 Schaden an.", "Специальные атаки наносят ×1,1 урона.")
        case .scopeLens, .razorClaw:
            return t("급소율이 1단계 올라요.", "Raises the critical-hit stage by 1.",
                     "急所率が1段階上がります。", "Sube 1 nivel la probabilidad de golpe crítico.",
                     "Augmente d'un cran le taux de coup critique.", "Aumenta em 1 nível a chance de acerto crítico.",
                     "Erhöht die Volltreffer-Rate um 1 Stufe.", "Повышает шанс критического удара на 1 ступень.")
        case .quickClaw:
            return t("20% 확률로 먼저 움직여요.", "20% chance to move first.",
                     "20%の確率で先に行動できます。", "20 % de probabilidad de moverse primero.",
                     "20 % de chances d'attaquer en premier.", "20% de chance de agir primeiro.",
                     "20 % Chance, zuerst zu agieren.", "20% шанс ходить первым.")
        case .brightPowder:
            return t("상대 기술의 명중률이 0.9배.", "Accuracy of moves aimed at the holder ×0.9.",
                     "相手の技の命中率が0.9倍になります。", "La precisión de los movimientos rivales ×0,9.",
                     "La précision des attaques adverses ×0,9.", "A precisão dos golpes inimigos ×0,9.",
                     "Die Genauigkeit gegnerischer Attacken ×0,9.", "Точность атак соперника ×0,9.")
        case .wideLens:
            return t("내 기술의 명중률이 1.1배.", "Accuracy of the holder's moves ×1.1.",
                     "自分の技の命中率が1.1倍。", "La precisión de sus movimientos ×1,1.",
                     "La précision de ses attaques ×1,1.", "A precisão dos próprios golpes ×1,1.",
                     "Genauigkeit der eigenen Attacken ×1,1.", "Точность своих атак ×1,1.")
        case .weaknessPolicy:
            return t("효과가 굉장한 공격을 받고 버티면 한 번 공격과 특공이 2단계 올라요.",
                     "Once, after surviving a super-effective hit, Atk and Sp. Atk rise by 2 stages.",
                     "効果ばつぐんの技を耐えると、一度だけ攻撃と特攻が2段階上がります。",
                     "Una vez, tras resistir un golpe supereficaz, Ataque y Ataq. Esp. suben 2 niveles.",
                     "Une fois, après une attaque super efficace encaissée, Attaque et Atq. Spé. montent de 2 crans.",
                     "Uma vez, ao sobreviver a um golpe super efetivo, Ataque e Atq. Esp. sobem 2 níveis.",
                     "Einmalig: Nach einem überlebten sehr effektiven Treffer steigen Angriff und Spezial-Angriff um 2 Stufen.",
                     "Один раз, пережив сверхэффективный удар, Атака и Спец. атака растут на 2 ступени.")
        case .focusBand:
            return t("쓰러질 공격을 10% 확률로 HP 1로 버텨요.", "10% chance to survive a knockout hit with 1 HP.",
                     "ひんし級の攻撃を10%の確率でHP1で耐えます。", "10 % de probabilidad de resistir un golpe mortal con 1 PS.",
                     "10 % de chances de survivre à un coup fatal avec 1 PV.",
                     "10% de chance de sobreviver a um golpe fatal com 1 HP.",
                     "10 % Chance, einen K.o.-Treffer mit 1 KP zu überstehen.",
                     "10% шанс пережить смертельный удар с 1 HP.")
        case .flameOrb:
            return t("턴이 끝나면 지닌 포켓몬이 화상을 입어요.", "Burns the holder at the end of the turn.",
                     "ターン終了時、持たせたポケモンがやけどになります。", "Quema al portador al final del turno.",
                     "Brûle le porteur à la fin du tour.", "Queima o portador no fim do turno.",
                     "Verbrennt den Träger am Ende der Runde.", "В конце хода поджигает носителя.")
        case .toxicOrb:
            return t("턴이 끝나면 지닌 포켓몬이 맹독에 걸려요.", "Badly poisons the holder at the end of the turn.",
                     "ターン終了時、持たせたポケモンがもうどくになります。", "Envenena gravemente al portador al final del turno.",
                     "Empoisonne gravement le porteur à la fin du tour.", "Envenena gravemente o portador no fim do turno.",
                     "Vergiftet den Träger am Ende der Runde schwer.", "В конце хода сильно отравляет носителя.")
        case .heatRock:
            return t("쾌청이 8턴 이어져요.", "Sunny weather it sets lasts 8 turns.",
                     "ひざしが強い状態が8ターン続きます。", "El sol que provoca dura 8 turnos.",
                     "Le soleil qu'il lance dure 8 tours.", "O sol que provoca dura 8 turnos.",
                     "Von ihm ausgelöstes Sonnenlicht hält 8 Runden an.", "Вызванная им солнечная погода длится 8 ходов.")
        case .dampRock:
            return t("비가 8턴 이어져요.", "Rain it sets lasts 8 turns.",
                     "あめが8ターン続きます。", "La lluvia que provoca dura 8 turnos.",
                     "La pluie qu'il lance dure 8 tours.", "A chuva que provoca dura 8 turnos.",
                     "Von ihm ausgelöster Regen hält 8 Runden an.", "Вызванный им дождь длится 8 ходов.")
        case .smoothRock:
            return t("모래바람이 8턴 이어져요.", "Sandstorm it sets lasts 8 turns.",
                     "すなあらしが8ターン続きます。", "La tormenta de arena que provoca dura 8 turnos.",
                     "La tempête de sable qu'il lance dure 8 tours.", "A tempestade de areia que provoca dura 8 turnos.",
                     "Von ihm ausgelöster Sandsturm hält 8 Runden an.", "Вызванная им песчаная буря длится 8 ходов.")
        case .icyRock:
            return t("싸라기눈과 설경이 8턴 이어져요.", "Hail or snow it sets lasts 8 turns.",
                     "あられ・ゆきが8ターン続きます。", "El granizo o la nieve que provoca dura 8 turnos.",
                     "La grêle ou la neige qu'il lance dure 8 tours.", "O granizo ou a neve que provoca dura 8 turnos.",
                     "Von ihm ausgelöster Hagel oder Schnee hält 8 Runden an.", "Вызванные им град или снег длятся 8 ходов.")
        default:
            return ""
        }
    }
}
