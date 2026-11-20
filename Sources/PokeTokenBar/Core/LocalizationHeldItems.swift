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
        if let effect = championItemEffect(kind) { return effect }
        if let effect = battleItemEffect(kind) { return effect }
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

/// Effect text of `ItemKind.moreBattleItems` and of the evolution items that also act in battle.
extension L {
    func battleItemEffect(_ kind: ItemKind) -> String? {
        if let type = kind.gemType { return gemEffect(type) }
        if let type = kind.incenseType { return typeBoostEffect(type) }
        if let type = kind.memoryType { return memoryEffect(type) }
        if let type = kind.driveType { return driveEffect(type) }
        if ItemKind.flavorBerries.contains(kind) { return flavorBerryEffect }
        if ItemKind.powerItems.contains(kind) { return speedHalvedEffect }
        if let effect = berryEffect(kind) ?? speciesItemEffect(kind) ?? reactiveItemEffect(kind) { return effect }
        return fieldItemEffect(kind)
    }

    private func gemEffect(_ type: String) -> String {
        let n = battleTypeName(type)
        return t("\(n)타입 기술을 처음 쓸 때 위력이 1.3배가 되고 없어져요.", "Boosts the first \(n)-type move ×1.3, then is used up.",
                 "\(n)タイプの技を最初に使うとき威力が1.3倍になり、なくなります。",
                 "Potencia ×1,3 el primer movimiento de tipo \(n) y se consume.",
                 "Augmente de ×1,3 la première attaque de type \(n), puis est consommé.",
                 "Aumenta ×1,3 o primeiro golpe do tipo \(n) e é consumida.",
                 "Verstärkt die erste \(n)-Attacke ×1,3 und wird dann verbraucht.",
                 "Усиливает первую атаку типа \(n) в 1,3 раза и расходуется.")
    }

    private func memoryEffect(_ type: String) -> String {
        let n = battleTypeName(type)
        return t("실버디가 지니면 \(n)타입이 되고 멀티어택도 \(n)타입이 돼요.",
                 "Held by Silvally, it becomes \(n) type, and so does Multi-Attack.",
                 "シルヴァディが持つと\(n)タイプになり、マルチアタックも\(n)タイプになります。",
                 "Si la lleva Silvally, pasa a tipo \(n), igual que Multiataque.",
                 "Tenu par Silvallié, il devient de type \(n), tout comme Coup Varia-Type.",
                 "Com Silvally, ele vira tipo \(n), assim como Multiataque.",
                 "Trägt Amigento sie, wird es zum \(n)-Typ, ebenso Multi-Angriff.",
                 "У Сильвалли меняет его тип на \(n), как и тип атаки «Мультиатака».")
    }

    private func driveEffect(_ type: String) -> String {
        let n = battleTypeName(type)
        return t("게노세크트가 지니면 모습이 바뀌고 테크노버스터가 \(n)타입이 돼요.",
                 "Held by Genesect, it changes form and Techno Blast becomes \(n) type.",
                 "ゲノセクトが持つとすがたが変わり、テクノバスターが\(n)タイプになります。",
                 "Si la lleva Genesect, cambia de forma y Tecno Shock pasa a tipo \(n).",
                 "Tenu par Genesect, il change de forme et Techno-Buster devient de type \(n).",
                 "Com Genesect, ele muda de forma e Tecno Choque vira tipo \(n).",
                 "Trägt Genesect es, ändert es seine Form und Techblaster wird zum \(n)-Typ.",
                 "У Генесекта меняет облик, а атака «Техновзрыв» становится типа \(n).")
    }

    private var flavorBerryEffect: String {
        t("HP가 1/4 이하가 되면 최대 HP의 1/3을 회복해요. 이 맛을 싫어하는 성격이면 혼란에 빠져요.",
          "At 1/4 HP or less, restores 1/3 of max HP. A holder whose nature dislikes the flavor becomes confused.",
          "HPが1/4以下になると最大HPの1/3を回復します。この味が嫌いな性格だとこんらんします。",
          "Con 1/4 de los PS o menos, recupera 1/3 de los PS máx. Si su naturaleza detesta el sabor, se confunde.",
          "À 1/4 des PV ou moins, restaure 1/3 des PV max. Si sa nature n'aime pas ce goût, il devient confus.",
          "Com 1/4 do HP ou menos, restaura 1/3 do HP máx. Se a natureza não gosta do sabor, fica confuso.",
          "Bei 1/4 KP oder weniger heilt sie 1/3 der max. KP. Mag sein Wesen den Geschmack nicht, wird es verwirrt.",
          "При HP 1/4 и ниже восстанавливает 1/3 макс. HP. Если характеру не нравится вкус, носитель впадает в замешательство.")
    }

    private var speedHalvedEffect: String {
        t("스피드가 절반이 돼요.", "Halves the holder's Speed.", "素早さが半分になります。", "Reduce a la mitad su Velocidad.",
          "Divise par deux sa Vitesse.", "Reduz pela metade a Velocidade.", "Halbiert die Initiative des Trägers.",
          "Вдвое снижает Скорость носителя.")
    }

    private func berryEffect(_ kind: ItemKind) -> String? {
        switch kind {
        case .cheriBerry: return cureEffect(t("마비", "paralysis", "まひ", "parálisis", "paralysie", "paralisia", "Paralyse", "паралич"))
        case .chestoBerry: return cureEffect(t("잠듦", "sleep", "ねむり", "sueño", "sommeil", "sono", "Schlaf", "сон"))
        case .pechaBerry: return cureEffect(t("독", "poison", "どく", "envenenamiento", "empoisonnement", "envenenamento", "Vergiftung", "отравление"))
        case .rawstBerry: return cureEffect(t("화상", "burn", "やけど", "quemadura", "brûlure", "queimadura", "Verbrennung", "ожог"))
        case .aspearBerry: return cureEffect(t("얼음", "freeze", "こおり", "congelación", "gel", "congelamento", "Einfrieren", "заморозка"))
        case .persimBerry:
            return cureEffect(t("혼란", "confusion", "こんらん", "confusión", "confusion", "confusão", "Verwirrung", "замешательство"))
        case .liechiBerry: return pinchStatEffect("attack")
        case .ganlonBerry: return pinchStatEffect("defense")
        case .salacBerry: return pinchStatEffect("speed")
        case .petayaBerry: return pinchStatEffect("special_attack")
        case .apicotBerry: return pinchStatEffect("special_defense")
        case .keeBerry: return guardBerryEffect(physical: true)
        case .marangaBerry: return guardBerryEffect(physical: false)
        case .jabocaBerry: return recoilBerryEffect(physical: true)
        case .rowapBerry: return recoilBerryEffect(physical: false)
        case .lansatBerry:
            return t("HP가 1/4 이하가 되면 급소율이 2단계 올라요.", "At 1/4 HP or less, raises the critical-hit stage by 2.",
                     "HPが1/4以下になると急所率が2段階上がります。", "Con 1/4 de los PS o menos, sube 2 niveles la probabilidad de crítico.",
                     "À 1/4 des PV ou moins, augmente de deux crans le taux de critique.",
                     "Com 1/4 do HP ou menos, aumenta em 2 níveis a chance de crítico.",
                     "Bei 1/4 KP oder weniger steigt die Volltreffer-Rate um 2 Stufen.",
                     "При HP 1/4 и ниже повышает шанс крита на 2 ступени.")
        case .starfBerry:
            return t("HP가 1/4 이하가 되면 무작위 능력 하나가 2단계 올라요.", "At 1/4 HP or less, sharply raises a random stat by 2 stages.",
                     "HPが1/4以下になるとランダムな能力ひとつが2段階上がります。",
                     "Con 1/4 de los PS o menos, sube 2 niveles una característica al azar.",
                     "À 1/4 des PV ou moins, augmente de deux crans une stat au hasard.",
                     "Com 1/4 do HP ou menos, aumenta em 2 níveis um atributo aleatório.",
                     "Bei 1/4 KP oder weniger steigt ein zufälliger Wert um 2 Stufen.",
                     "При HP 1/4 и ниже повышает случайную характеристику на 2 ступени.")
        case .micleBerry:
            return t("HP가 1/4 이하가 되면 다음 기술의 명중률이 1.2배.", "At 1/4 HP or less, the next move's accuracy ×1.2.",
                     "HPが1/4以下になると次の技の命中率が1.2倍。", "Con 1/4 de los PS o menos, la precisión del siguiente movimiento ×1,2.",
                     "À 1/4 des PV ou moins, la précision de l'attaque suivante ×1,2.",
                     "Com 1/4 do HP ou menos, a precisão do próximo golpe ×1,2.",
                     "Bei 1/4 KP oder weniger hat die nächste Attacke ×1,2 Genauigkeit.",
                     "При HP 1/4 и ниже точность следующей атаки ×1,2.")
        case .custapBerry:
            return t("HP가 1/4 이하가 되면 다음 턴에 먼저 움직여요.", "At 1/4 HP or less, moves first on the next turn.",
                     "HPが1/4以下になると次のターンに先に行動します。", "Con 1/4 de los PS o menos, se mueve primero el siguiente turno.",
                     "À 1/4 des PV ou moins, agit en premier au tour suivant.",
                     "Com 1/4 do HP ou menos, age primeiro no próximo turno.",
                     "Bei 1/4 KP oder weniger handelt es in der nächsten Runde zuerst.",
                     "При HP 1/4 и ниже в следующем ходу ходит первым.")
        case .oranBerry:
            return t("HP가 절반 이하가 되면 HP를 10 회복해요.", "At half HP or less, restores 10 HP.",
                     "HPが半分以下になるとHPを10回復します。", "Con la mitad de los PS o menos, recupera 10 PS.",
                     "À la moitié des PV ou moins, restaure 10 PV.", "Com metade do HP ou menos, restaura 10 HP.",
                     "Bei halben KP oder weniger heilt sie 10 KP.", "При HP вдвое ниже восстанавливает 10 HP.")
        case .enigmaBerry:
            return t("효과가 굉장한 공격을 맞으면 최대 HP의 1/4을 회복해요.", "When hit super effectively, restores 1/4 of max HP.",
                     "効果ばつぐんの技を受けると最大HPの1/4を回復します。",
                     "Si recibe un golpe supereficaz, recupera 1/4 de los PS máx.",
                     "S'il subit une attaque super efficace, restaure 1/4 des PV max.",
                     "Ao receber um golpe super efetivo, restaura 1/4 do HP máx.",
                     "Bei einem sehr effektiven Treffer heilt sie 1/4 der max. KP.",
                     "При сверхэффективном ударе восстанавливает 1/4 макс. HP.")
        case .leppaBerry:
            return t("기술의 PP가 0이 되면 PP를 10 채워요.", "Restores 10 PP to a move that runs out.",
                     "技のPPが0になるとPPを10回復します。", "Restaura 10 PP al movimiento que se queda sin PP.",
                     "Restaure 10 PP à une capacité qui n'en a plus.", "Restaura 10 PP do golpe que ficar sem PP.",
                     "Füllt 10 AP einer Attacke auf, deren AP leer sind.", "Восстанавливает 10 PP атаке, у которой они кончились.")
        default: return nil
        }
    }

    private func cureEffect(_ status: String) -> String {
        t("\(status) 상태를 한 번 고치고 없어져요.", "Cures \(status) once, then is used up.", "\(status)を一度だけ治し、なくなります。",
          "Cura una vez: \(status). Luego se consume.", "Soigne une fois : \(status). Puis est consommée.",
          "Cura uma vez: \(status). Depois é consumida.", "Heilt einmal: \(status). Wird dann verbraucht.",
          "Один раз снимает: \(status). Затем расходуется.")
    }

    private func pinchStatEffect(_ stat: String) -> String {
        let s = statName(stat)
        return t("HP가 1/4 이하가 되면 \(s) 랭크가 1단계 올라요.", "At 1/4 HP or less, raises \(s) by 1 stage.",
                 "HPが1/4以下になると\(s)が1段階上がります。", "Con 1/4 de los PS o menos, sube 1 nivel: \(s).",
                 "À 1/4 des PV ou moins, augmente d'un cran : \(s).", "Com 1/4 do HP ou menos, aumenta 1 nível: \(s).",
                 "Bei 1/4 KP oder weniger steigt \(s) um 1 Stufe.", "При HP 1/4 и ниже повышает \(s) на 1 ступень.")
    }

    private func guardBerryEffect(physical: Bool) -> String {
        let s = statName(physical ? "defense" : "special_defense")
        return physical
            ? t("물리 공격을 맞으면 \(s) 랭크가 1단계 오르고 없어져요.", "When hit by a physical move, raises \(s) by 1 stage, then is used up.",
                "物理技を受けると\(s)が1段階上がり、なくなります。", "Si recibe un golpe físico, sube 1 nivel: \(s). Luego se consume.",
                "Si touché par une attaque physique, augmente d'un cran : \(s). Puis est consommée.",
                "Ao receber um golpe físico, aumenta 1 nível: \(s). Depois é consumida.",
                "Bei einer physischen Attacke steigt \(s) um 1 Stufe, dann wird sie verbraucht.",
                "При физической атаке повышает \(s) на 1 ступень и расходуется.")
            : t("특수 공격을 맞으면 \(s) 랭크가 1단계 오르고 없어져요.", "When hit by a special move, raises \(s) by 1 stage, then is used up.",
                "特殊技を受けると\(s)が1段階上がり、なくなります。", "Si recibe un golpe especial, sube 1 nivel: \(s). Luego se consume.",
                "Si touché par une attaque spéciale, augmente d'un cran : \(s). Puis est consommée.",
                "Ao receber um golpe especial, aumenta 1 nível: \(s). Depois é consumida.",
                "Bei einer speziellen Attacke steigt \(s) um 1 Stufe, dann wird sie verbraucht.",
                "При специальной атаке повышает \(s) на 1 ступень и расходуется.")
    }

    private func recoilBerryEffect(physical: Bool) -> String {
        physical
            ? t("물리 공격을 맞으면 공격한 상대가 최대 HP의 1/8을 잃어요.", "When hit by a physical move, the attacker loses 1/8 of its max HP.",
                "物理技を受けると、相手が最大HPの1/8を失います。", "Si recibe un golpe físico, el atacante pierde 1/8 de sus PS máx.",
                "Si touché par une attaque physique, l'attaquant perd 1/8 de ses PV max.",
                "Ao receber um golpe físico, o atacante perde 1/8 do HP máx.",
                "Bei einer physischen Attacke verliert der Angreifer 1/8 seiner max. KP.",
                "При физической атаке атакующий теряет 1/8 макс. HP.")
            : t("특수 공격을 맞으면 공격한 상대가 최대 HP의 1/8을 잃어요.", "When hit by a special move, the attacker loses 1/8 of its max HP.",
                "特殊技を受けると、相手が最大HPの1/8を失います。", "Si recibe un golpe especial, el atacante pierde 1/8 de sus PS máx.",
                "Si touché par une attaque spéciale, l'attaquant perd 1/8 de ses PV max.",
                "Ao receber um golpe especial, o atacante perde 1/8 do HP máx.",
                "Bei einer speziellen Attacke verliert der Angreifer 1/8 seiner max. KP.",
                "При специальной атаке атакующий теряет 1/8 макс. HP.")
    }

    private func speciesItemEffect(_ kind: ItemKind) -> String? {
        switch kind {
        case .lightBall:
            return speciesDoubleEffect(t("피카츄", "Pikachu", "ピカチュウ", "Pikachu", "Pikachu", "Pikachu", "Pikachu", "Пикачу"),
                                       ["attack", "special_attack"])
        case .thickClub:
            return speciesDoubleEffect(t("탕구리·텅구리", "Cubone or Marowak", "カラカラ・ガラガラ", "Cubone o Marowak", "Osselait ou Ossatueur",
                                         "Cubone ou Marowak", "Tragosso oder Knogga", "Кьюбон или Маровак"), ["attack"])
        case .metalPowder: return speciesDoubleEffect(dittoName, ["defense"])
        case .quickPowder: return speciesDoubleEffect(dittoName, ["speed"])
        case .deepSeaTooth: return speciesDoubleEffect(clamperlName, ["special_attack"])
        case .deepSeaScale: return speciesDoubleEffect(clamperlName, ["special_defense"])
        case .luckyPunch:
            return speciesCritEffect(t("럭키", "Chansey", "ラッキー", "Chansey", "Leveinard", "Chansey", "Chaneira", "Ченси"))
        case .stick:
            return speciesCritEffect(t("파오리·창파나이트", "Farfetch’d or Sirfetch’d", "カモネギ・ネギガナイト", "Farfetch’d o Sirfetch’d",
                                       "Canarticho ou Palarticho", "Farfetch’d ou Sirfetch’d", "Porenta oder Lauchzelot",
                                       "Фарфетчд или Сирфетчд"))
        case .adamantOrb:
            return speciesBoostEffect(t("디아루가", "Dialga", "ディアルガ", "Dialga", "Dialga", "Dialga", "Dialga", "Диалга"), "steel")
        case .lustrousOrb:
            return speciesBoostEffect(t("펄기아", "Palkia", "パルキア", "Palkia", "Palkia", "Palkia", "Palkia", "Палкия"), "water")
        case .griseousOrb:
            return speciesBoostEffect(t("기라티나", "Giratina", "ギラティナ", "Giratina", "Giratina", "Giratina", "Giratina", "Гиратина"), "ghost")
        case .soulDew:
            return speciesBoostEffect(t("라티아스·라티오스", "Latias or Latios", "ラティアス・ラティオス", "Latias o Latios", "Latias ou Latios",
                                        "Latias ou Latios", "Latias oder Latios", "Латиас или Латиос"), "psychic")
        default: return nil
        }
    }

    private var dittoName: String { t("메타몽", "Ditto", "メタモン", "Ditto", "Métamorph", "Ditto", "Ditto", "Дитто") }
    private var clamperlName: String { t("진주몽", "Clamperl", "パールル", "Clamperl", "Coquiperl", "Clamperl", "Perlu", "Кламперл") }

    private func speciesDoubleEffect(_ species: String, _ stats: [String]) -> String {
        let s = stats.map(statName).joined(separator: "·")
        return t("\(species)에게 지니게 하면 \(s) ×2.", "Held by \(species): \(s) ×2.", "\(species)に持たせると\(s)が2倍。",
                 "Si lo lleva \(species): \(s) ×2.", "Tenu par \(species) : \(s) ×2.", "Com \(species): \(s) ×2.",
                 "Trägt \(species) es: \(s) ×2.", "У \(species): \(s) ×2.")
    }

    private func speciesCritEffect(_ species: String) -> String {
        t("\(species)에게 지니게 하면 급소율이 2단계 올라요.", "Held by \(species), raises the critical-hit stage by 2.",
          "\(species)に持たせると急所率が2段階上がります。", "Si lo lleva \(species), sube 2 niveles la probabilidad de crítico.",
          "Tenu par \(species), augmente de deux crans le taux de critique.",
          "Com \(species), aumenta em 2 níveis a chance de crítico.",
          "Trägt \(species) es, steigt die Volltreffer-Rate um 2 Stufen.",
          "У \(species) повышает шанс крита на 2 ступени.")
    }

    private func speciesBoostEffect(_ species: String, _ second: String) -> String {
        let types = [battleTypeName("dragon"), battleTypeName(second)].joined(separator: "/")
        return t("\(species)에게 지니게 하면 \(types)타입 기술의 데미지가 1.2배.",
                 "Held by \(species), its \(types)-type moves deal ×1.2 damage.",
                 "\(species)に持たせると\(types)タイプの技のダメージが1.2倍。",
                 "Si lo lleva \(species), sus movimientos de tipo \(types) hacen ×1,2 de daño.",
                 "Tenu par \(species), ses attaques de type \(types) font ×1,2 de dégâts.",
                 "Com \(species), seus golpes do tipo \(types) causam ×1,2 de dano.",
                 "Trägt \(species) es, richten seine \(types)-Attacken ×1,2 Schaden an.",
                 "У \(species) атаки типов \(types) наносят ×1,2 урона.")
    }

    private func reactiveItemEffect(_ kind: ItemKind) -> String? {
        switch kind {
        case .absorbBulb: return hitStatEffect("water", "special_attack")
        case .cellBattery: return hitStatEffect("electric", "attack")
        case .luminousMoss: return hitStatEffect("water", "special_defense")
        case .snowball: return hitStatEffect("ice", "attack")
        case .loadedDice:
            return t("2~5회 연속 기술이 4~5회 맞아요.", "Moves that hit 2–5 times hit 4 or 5 times.", "2〜5回当たる技が4〜5回当たります。",
                     "Los movimientos de 2 a 5 golpes aciertan 4 o 5 veces.", "Les attaques de 2 à 5 coups frappent 4 ou 5 fois.",
                     "Golpes de 2 a 5 acertos acertam 4 ou 5 vezes.", "Attacken mit 2–5 Treffern treffen 4- oder 5-mal.",
                     "Атаки на 2–5 ударов бьют 4 или 5 раз.")
        case .metronome:
            return t("같은 기술을 연달아 성공하면 위력이 0.2배씩, 최대 2배까지 올라요.",
                     "Each success with the same move in a row adds ×0.2 power, up to ×2.",
                     "同じ技を続けて成功させると威力が0.2倍ずつ、最大2倍まで上がります。",
                     "Cada acierto seguido con el mismo movimiento suma ×0,2 de potencia, hasta ×2.",
                     "Chaque réussite d'affilée avec la même attaque ajoute ×0,2 de puissance, jusqu'à ×2.",
                     "Cada acerto seguido com o mesmo golpe soma ×0,2 de poder, até ×2.",
                     "Jeder Erfolg mit derselben Attacke in Folge gibt ×0,2 Stärke, bis ×2.",
                     "Каждый успех той же атакой подряд даёт ×0,2 силы, до ×2.")
        case .zoomLens:
            return t("상대보다 늦게 움직이면 명중률이 1.2배.", "Accuracy ×1.2 when moving after the target.",
                     "相手より後に行動すると命中率が1.2倍。", "Precisión ×1,2 si se mueve después del objetivo.",
                     "Précision ×1,2 s'il agit après la cible.", "Precisão ×1,2 se agir depois do alvo.",
                     "Genauigkeit ×1,2, wenn es nach dem Ziel handelt.", "Точность ×1,2, если ходит после цели.")
        case .kingsRock, .razorFang:
            return t("공격이 맞으면 10% 확률로 상대가 풀죽어요.", "Hits have a 10% chance to make the target flinch.",
                     "攻撃が当たると10%の確率で相手がひるみます。", "Sus golpes tienen un 10 % de probabilidad de hacer retroceder.",
                     "Ses coups ont 10 % de chances d'apeurer la cible.", "Seus golpes têm 10% de chance de fazer o alvo recuar.",
                     "Treffer lassen das Ziel mit 10 % Chance zurückschrecken.", "Удары с шансом 10% вызывают испуг цели.")
        case .gripClaw:
            return t("조이기 같은 묶는 기술이 7턴 이어져요.", "Binding moves like Wrap last 7 turns.",
                     "まきつくなどのしめつける技が7ターン続きます。", "Los movimientos que atrapan, como Constricción, duran 7 turnos.",
                     "Les attaques qui ligotent, comme Ligotage, durent 7 tours.",
                     "Golpes que prendem, como Embrulho, duram 7 turnos.",
                     "Klammer-Attacken wie Wickel halten 7 Runden an.", "Связывающие атаки вроде «Обвивания» длятся 7 ходов.")
        case .bindingBand:
            return t("묶는 기술이 턴마다 최대 HP의 1/6을 깎아요.", "Binding moves take 1/6 of max HP each turn.",
                     "しめつける技が毎ターン最大HPの1/6を削ります。", "Los movimientos que atrapan quitan 1/6 de los PS máx. por turno.",
                     "Les attaques qui ligotent retirent 1/6 des PV max par tour.",
                     "Golpes que prendem tiram 1/6 do HP máx. por turno.",
                     "Klammer-Attacken nehmen pro Runde 1/6 der max. KP.", "Связывающие атаки отнимают 1/6 макс. HP за ход.")
        case .powerHerb:
            return t("모으는 기술을 한 번 바로 쓰고 없어져요.", "Lets a charging move skip its charge once, then is used up.",
                     "ためる技を一度だけすぐに出し、なくなります。", "Un movimiento de carga se usa al instante una vez y se consume.",
                     "Une attaque à charger part tout de suite une fois, puis est consommée.",
                     "Um golpe de carga sai na hora uma vez e é consumida.",
                     "Eine Auflade-Attacke wird einmal sofort eingesetzt, dann wird es verbraucht.",
                     "Один раз атака с зарядкой срабатывает сразу, затем расходуется.")
        case .throatSpray:
            return t("소리 기술을 쓰면 특공이 1단계 오르고 없어져요.", "After a sound move, raises SpA by 1 stage, then is used up.",
                     "音の技を出すと特攻が1段階上がり、なくなります。", "Tras un movimiento de sonido, sube 1 nivel el Ataq. Esp. y se consume.",
                     "Après une attaque sonore, augmente d'un cran l'Atq. Spé., puis est consommé.",
                     "Após um golpe sonoro, aumenta 1 nível o Atq. Esp. e é consumido.",
                     "Nach einer Schall-Attacke steigt der Spezial-Angriff um 1 Stufe, dann wird es verbraucht.",
                     "После звуковой атаки повышает Спец. атаку на 1 ступень и расходуется.")
        case .boosterEnergy:
            return t("고대활성·쿼크차지가 날씨나 필드 없이도 발동하고 없어져요.",
                     "Activates Protosynthesis or Quark Drive without sun or terrain, then is used up.",
                     "こだいかっせい・クォークチャージが天気やフィールドなしで発動し、なくなります。",
                     "Activa Paleosíntesis o Carga Cuark sin sol ni campo y se consume.",
                     "Active Paléosynthèse ou Charge Quantique sans soleil ni champ, puis est consommée.",
                     "Ativa Paleossíntese ou Carga Quark sem sol nem campo e é consumida.",
                     "Aktiviert Paläosynthese oder Quantenantrieb ohne Sonne oder Feld, dann wird sie verbraucht.",
                     "Включает «Протосинтез» или «Кварковый привод» без солнца и поля, затем расходуется.")
        case .airBalloon:
            return t("땅타입 기술을 맞지 않아요. 공격을 맞으면 터져요.", "Ground moves miss the holder. It pops when the holder is hit.",
                     "じめんタイプの技が当たりません。攻撃を受けると割れます。",
                     "Los movimientos de tipo Tierra no le afectan. Explota al recibir un golpe.",
                     "Les attaques de type Sol ne le touchent pas. Il éclate au premier coup reçu.",
                     "Golpes do tipo Terrestre não o atingem. Estoura ao receber um golpe.",
                     "Boden-Attacken treffen nicht. Er platzt, wenn der Träger getroffen wird.",
                     "Земляные атаки его не задевают. Лопается от удара.")
        case .blunderPolicy:
            return t("기술이 빗나가면 스피드가 2단계 오르고 없어져요.", "When a move misses, raises Speed by 2 stages, then is used up.",
                     "技が外れると素早さが2段階上がり、なくなります。", "Si falla un movimiento, sube 2 niveles la Velocidad y se consume.",
                     "Si une attaque rate, augmente de deux crans la Vitesse, puis est consommée.",
                     "Se um golpe errar, aumenta 2 níveis a Velocidade e é consumida.",
                     "Verfehlt eine Attacke, steigt die Initiative um 2 Stufen, dann wird sie verbraucht.",
                     "При промахе повышает Скорость на 2 ступени и расходуется.")
        case .adrenalineOrb:
            return t("위협을 받으면 스피드가 1단계 오르고 없어져요.", "When Intimidated, raises Speed by 1 stage, then is used up.",
                     "いかくを受けると素早さが1段階上がり、なくなります。", "Si sufre Intimidación, sube 1 nivel la Velocidad y se consume.",
                     "S'il subit Intimidation, augmente d'un cran la Vitesse, puis est consommé.",
                     "Ao sofrer Intimidação, aumenta 1 nível a Velocidade e é consumido.",
                     "Bei Bedroher steigt die Initiative um 1 Stufe, dann wird sie verbraucht.",
                     "При «Запугивании» повышает Скорость на 1 ступень и расходуется.")
        case .laxIncense: return heldItemEffect(.brightPowder)
        case .fullIncense, .laggingTail:
            return t("같은 우선도에서는 항상 나중에 움직여요.", "Always moves last within its priority bracket.",
                     "同じ優先度では必ず後に行動します。", "Siempre se mueve el último dentro de su prioridad.",
                     "Agit toujours en dernier à priorité égale.", "Sempre age por último dentro da sua prioridade.",
                     "Handelt bei gleicher Priorität immer zuletzt.", "При равном приоритете всегда ходит последним.")
        case .ironBall:
            return t("스피드가 절반이 되고 땅에 붙어 땅타입 기술을 맞아요.", "Halves Speed and grounds the holder, so Ground moves hit it.",
                     "素早さが半分になり、地面に落ちてじめんタイプの技が当たります。",
                     "Reduce a la mitad su Velocidad y lo deja en el suelo, así que le afectan los movimientos de tipo Tierra.",
                     "Divise par deux sa Vitesse et le cloue au sol : les attaques de type Sol le touchent.",
                     "Reduz pela metade a Velocidade e o prende ao chão, então golpes do tipo Terrestre o atingem.",
                     "Halbiert die Initiative und holt den Träger auf den Boden, sodass Boden-Attacken treffen.",
                     "Вдвое снижает Скорость и прижимает к земле, так что Земляные атаки попадают.")
        case .roomService:
            return t("트릭룸이 펼쳐지면 스피드가 1단계 내려가고 없어져요.", "When Trick Room is up, lowers Speed by 1 stage, then is used up.",
                     "トリックルームになると素早さが1段階下がり、なくなります。",
                     "Con Espacio Raro activo, baja 1 nivel la Velocidad y se consume.",
                     "Sous Distorsion, baisse d'un cran la Vitesse, puis est consommé.",
                     "Com Sala Truque ativa, reduz 1 nível a Velocidade e é consumido.",
                     "Bei Bizarroraum sinkt die Initiative um 1 Stufe, dann wird er verbraucht.",
                     "При «Комнате трюков» понижает Скорость на 1 ступень и расходуется.")
        case .mentalHerb:
            return t("도발·앵콜·사슬묶기 같은 행동 제한을 한 번 풀고 없어져요.", "Ends Taunt, Encore, Disable and the like once, then is used up.",
                     "ちょうはつ・アンコール・かなしばりなどを一度だけ解き、なくなります。",
                     "Anula una vez Mofa, Otra Vez, Anulación y similares, y se consume.",
                     "Annule une fois Provoc, Encore, Entrave et autres, puis est consommée.",
                     "Desfaz uma vez Provocação, Bis, Desabilitar e afins, e é consumida.",
                     "Hebt einmal Verhöhner, Zugabe, Aussetzer und Ähnliches auf, dann wird es verbraucht.",
                     "Один раз снимает «Насмешку», «Бис», «Блокировку» и подобное, затем расходуется.")
        case .clearAmulet:
            return t("상대 때문에 능력이 떨어지지 않아요.", "Foes can't lower the holder's stats.",
                     "相手に能力を下げられません。", "Los rivales no pueden bajar sus características.",
                     "Les adversaires ne peuvent pas baisser ses stats.", "Os inimigos não podem reduzir seus atributos.",
                     "Gegner können seine Werte nicht senken.", "Соперники не могут понизить его характеристики.")
        case .covertCloak:
            return t("상대 기술의 추가 효과를 받지 않아요.", "Blocks the added effects of foes' moves.",
                     "相手の技の追加効果を受けません。", "Bloquea los efectos secundarios de los movimientos rivales.",
                     "Bloque les effets secondaires des attaques adverses.", "Bloqueia os efeitos secundários dos golpes inimigos.",
                     "Blockt Zusatzeffekte gegnerischer Attacken.", "Блокирует дополнительные эффекты атак соперника.")
        case .abilityShield:
            return t("특성이 바뀌거나 지워지지 않아요.", "The holder's ability can't be changed or suppressed.",
                     "特性を変えられたり消されたりしません。", "Su habilidad no se puede cambiar ni anular.",
                     "Son talent ne peut être ni changé ni annulé.", "Sua habilidade não pode ser trocada nem anulada.",
                     "Seine Fähigkeit kann weder getauscht noch unterdrückt werden.", "Способность нельзя сменить или подавить.")
        case .protectivePads:
            return t("접촉 기술을 써도 상대의 접촉 효과를 받지 않아요.", "Contact moves don't trigger the target's contact effects.",
                     "接触技を出しても相手の接触効果を受けません。",
                     "Sus movimientos de contacto no activan los efectos de contacto del objetivo.",
                     "Ses attaques de contact ne déclenchent pas les effets de contact de la cible.",
                     "Seus golpes de contato não ativam os efeitos de contato do alvo.",
                     "Kontakt-Attacken lösen keine Kontakt-Effekte des Ziels aus.",
                     "Контактные атаки не вызывают контактных эффектов цели.")
        case .safetyGoggles:
            return t("모래바람 데미지와 가루 기술을 받지 않아요.", "Blocks sandstorm damage and powder moves.",
                     "すなあらしのダメージと粉の技を受けません。", "Bloquea el daño de la tormenta de arena y los movimientos de polvo.",
                     "Bloque les dégâts de la tempête de sable et les attaques de poudre.",
                     "Bloqueia o dano da tempestade de areia e os golpes de pó.",
                     "Blockt Sandsturm-Schaden und Puder-Attacken.", "Защищает от урона песчаной бури и атак-порошков.")
        case .heavyDutyBoots:
            return t("나올 때 스텔스록·압정뿌리기 같은 함정을 밟지 않아요.", "Ignores entry hazards like Stealth Rock and Spikes.",
                     "出てくるとき、ステルスロック・まきびしなどのわなを受けません。",
                     "Ignora trampas de entrada como Trampa Rocas y Púas.",
                     "Ignore les pièges comme Piège de Roc et Picots.", "Ignora armadilhas como Armadilha de Pedra e Espinhos.",
                     "Ignoriert Fallen wie Tarnsteine und Stachler.", "Не попадает в ловушки вроде «Скрытых камней» и «Шипов».")
        default: return nil
        }
    }

    private func hitStatEffect(_ type: String, _ stat: String) -> String {
        let n = battleTypeName(type), s = statName(stat)
        return t("\(n)타입 공격을 맞으면 \(s) 랭크가 1단계 오르고 없어져요.",
                 "When hit by a \(n)-type move, raises \(s) by 1 stage, then is used up.",
                 "\(n)タイプの技を受けると\(s)が1段階上がり、なくなります。",
                 "Si recibe un golpe de tipo \(n), sube 1 nivel: \(s). Luego se consume.",
                 "Si touché par une attaque de type \(n), augmente d'un cran : \(s). Puis est consommé.",
                 "Ao receber um golpe do tipo \(n), aumenta 1 nível: \(s). Depois é consumido.",
                 "Bei einem \(n)-Treffer steigt \(s) um 1 Stufe, dann wird es verbraucht.",
                 "При ударе типа \(n) повышает \(s) на 1 ступень и расходуется.")
    }

    private func fieldItemEffect(_ kind: ItemKind) -> String? {
        switch kind {
        case .electricSeed: return seedEffect(terrainName("electric"), "defense")
        case .grassySeed: return seedEffect(terrainName("grassy"), "defense")
        case .mistySeed: return seedEffect(terrainName("misty"), "special_defense")
        case .psychicSeed: return seedEffect(terrainName("psychic"), "special_defense")
        case .utilityUmbrella:
            return t("쾌청과 비의 효과를 받지 않아요.", "Ignores the effects of sun and rain.", "はれとあめの効果を受けません。",
                     "Ignora los efectos del sol y la lluvia.", "Ignore les effets du soleil et de la pluie.",
                     "Ignora os efeitos do sol e da chuva.", "Ignoriert die Wirkung von Sonne und Regen.",
                     "Не подвержен эффектам солнца и дождя.")
        case .lightClay:
            return t("리플렉터·빛의장막·오로라베일이 8턴 이어져요.", "Reflect, Light Screen and Aurora Veil last 8 turns.",
                     "リフレクター・ひかりのかべ・オーロラベールが8ターン続きます。",
                     "Reflejo, Pantalla de Luz y Velo Aurora duran 8 turnos.",
                     "Protection, Mur Lumière et Voile Aurore durent 8 tours.",
                     "Refletir, Tela de Luz e Véu Aurora duram 8 turnos.",
                     "Reflektor, Lichtschild und Auroraschleier halten 8 Runden an.",
                     "«Отражение», «Световой экран» и «Завеса авроры» длятся 8 ходов.")
        case .terrainExtender:
            return t("펼친 필드가 8턴 이어져요.", "Terrain it sets lasts 8 turns.", "はったフィールドが8ターン続きます。",
                     "El campo que crea dura 8 turnos.", "Le champ qu'il crée dure 8 tours.",
                     "O campo que cria dura 8 turnos.", "Von ihm erzeugte Felder halten 8 Runden an.",
                     "Созданное им поле длится 8 ходов.")
        case .floatStone:
            return t("몸무게가 절반이 돼요.", "Halves the holder's weight.", "体重が半分になります。", "Reduce a la mitad su peso.",
                     "Divise par deux son poids.", "Reduz pela metade o peso.", "Halbiert das Gewicht des Trägers.",
                     "Вдвое уменьшает вес носителя.")
        case .stickyBarb:
            return t("매 턴 최대 HP의 1/8을 잃어요. 접촉한 빈손 상대에게 옮겨 붙어요.",
                     "Loses 1/8 of max HP each turn. It sticks to an empty-handed attacker that makes contact.",
                     "毎ターン最大HPの1/8を失います。接触した持ち物のない相手にくっつきます。",
                     "Pierde 1/8 de los PS máx. cada turno. Se pega a un atacante sin objeto que haga contacto.",
                     "Perd 1/8 des PV max à chaque tour. Il s'accroche à un attaquant sans objet qui le touche.",
                     "Perde 1/8 do HP máx. a cada turno. Gruda num atacante sem item que faça contato.",
                     "Verliert jede Runde 1/8 der max. KP. Haftet an einem Angreifer ohne Item, der Kontakt macht.",
                     "Каждый ход отнимает 1/8 макс. HP. Цепляется к атакующему без предмета при контакте.")
        case .ringTarget:
            return t("타입 때문에 받지 않던 기술도 맞아요.", "Moves its types are immune to now hit it.",
                     "タイプで無効だった技も当たります。", "Le afectan los movimientos a los que su tipo es inmune.",
                     "Les attaques auxquelles son type est immunisé le touchent.",
                     "Golpes aos quais seu tipo é imune passam a atingi-lo.",
                     "Attacken, gegen die sein Typ immun ist, treffen ihn.",
                     "Атаки, к которым его тип невосприимчив, по нему попадают.")
        default: return nil
        }
    }

    private func terrainName(_ terrain: String) -> String {
        switch terrain {
        case "electric": t("일렉트릭필드", "Electric Terrain", "エレキフィールド", "Campo Eléctrico", "Champ Électrifié", "Campo Elétrico",
                           "Elektrofeld", "Электрическое поле")
        case "grassy": t("그래스필드", "Grassy Terrain", "グラスフィールド", "Campo de Hierba", "Champ Herbu", "Campo de Grama",
                         "Grasfeld", "Травяное поле")
        case "misty": t("미스트필드", "Misty Terrain", "ミストフィールド", "Campo de Niebla", "Champ Brumeux", "Campo Nebuloso",
                        "Nebelfeld", "Туманное поле")
        default: t("사이코필드", "Psychic Terrain", "サイコフィールド", "Campo Psíquico", "Champ Psychique", "Campo Psíquico",
                   "Psychofeld", "Психическое поле")
        }
    }

    private func seedEffect(_ terrain: String, _ stat: String) -> String {
        let s = statName(stat)
        return t("\(terrain)가 깔리면 \(s) 랭크가 1단계 오르고 없어져요.", "On \(terrain), raises \(s) by 1 stage, then is used up.",
                 "\(terrain)になると\(s)が1段階上がり、なくなります。", "Con \(terrain), sube 1 nivel: \(s). Luego se consume.",
                 "Sur \(terrain), augmente d'un cran : \(s). Puis est consommée.",
                 "Com \(terrain), aumenta 1 nível: \(s). Depois é consumida.",
                 "Bei \(terrain) steigt \(s) um 1 Stufe, dann wird es verbraucht.",
                 "На поле «\(terrain)» повышает \(s) на 1 ступень и расходуется.")
    }
}
