import Foundation

/// Effect text of the Primal orbs, Origin items, Punching Glove, resist berries and plates.
extension L {
    func championItemEffect(_ kind: ItemKind) -> String? {
        if let type = kind.plateType { return plateEffect(type) }
        if kind == .chilanBerry { return chilanBerryEffect }
        if let type = kind.resistedType { return resistBerryEffect(type) }
        switch kind {
        case .punchingGlove:
            return t("펀치 기술의 데미지가 1.1배.", "Punching moves deal ×1.1 damage.",
                     "パンチ技のダメージが1.1倍。", "Los movimientos de puño hacen ×1,1 de daño.",
                     "Les attaques de poing font ×1,1 de dégâts.", "Golpes de soco causam ×1,1 de dano.",
                     "Schlag-Attacken richten ×1,1 Schaden an.", "Ударные атаки кулаком наносят ×1,1 урона.")
        case .redOrb: return primalOrbEffect(groudonName)
        case .blueOrb: return primalOrbEffect(kyogreName)
        case .adamantCrystal: return originItemEffect(dialgaName, second: "steel")
        case .lustrousGlobe: return originItemEffect(palkiaName, second: "water")
        case .griseousCore: return originItemEffect(giratinaName, second: "ghost")
        default: return nil
        }
    }

    private func resistBerryEffect(_ type: String) -> String {
        let name = battleTypeName(type)
        return t("효과가 굉장한 \(name)타입 공격을 처음 한 번 절반으로 줄이고 없어져요.",
                 "Halves the first super-effective \(name)-type hit, then is used up.",
                 "効果ばつぐんの\(name)タイプの技を最初の1回だけ半減し、なくなります。",
                 "Reduce a la mitad el primer golpe supereficaz de tipo \(name) y se consume.",
                 "Divise par deux la première attaque super efficace de type \(name), puis est consommée.",
                 "Reduz pela metade o primeiro golpe super efetivo do tipo \(name) e é consumida.",
                 "Halbiert den ersten sehr effektiven \(name)-Treffer und wird dann verbraucht.",
                 "Вдвое ослабляет первый сверхэффективный удар типа \(name) и расходуется.")
    }

    private var chilanBerryEffect: String {
        let name = battleTypeName("normal")
        return t("\(name)타입 공격을 처음 한 번 절반으로 줄이고 없어져요.",
                 "Halves the first \(name)-type hit, then is used up.",
                 "\(name)タイプの技を最初の1回だけ半減し、なくなります。",
                 "Reduce a la mitad el primer golpe de tipo \(name) y se consume.",
                 "Divise par deux la première attaque de type \(name), puis est consommée.",
                 "Reduz pela metade o primeiro golpe do tipo \(name) e é consumida.",
                 "Halbiert den ersten \(name)-Treffer und wird dann verbraucht.",
                 "Вдвое ослабляет первый удар типа \(name) и расходуется.")
    }

    private func plateEffect(_ type: String) -> String {
        let name = battleTypeName(type)
        return t("\(name)타입 기술의 데미지가 1.2배. 아르세우스가 지니면 \(name)타입이 되고 심판의뭉치도 \(name)타입이 돼요.",
                 "\(name)-type moves deal ×1.2 damage. Held by Arceus, it becomes \(name) type, and so does Judgment.",
                 "\(name)タイプの技のダメージが1.2倍。アルセウスが持つと\(name)タイプになり、さばきのつぶても\(name)タイプになります。",
                 "Los movimientos de tipo \(name) hacen ×1,2 de daño. Si la lleva Arceus, pasa a tipo \(name), igual que Sentencia.",
                 "Les attaques de type \(name) font ×1,2 de dégâts. Tenue par Arceus, il devient de type \(name), tout comme Jugement.",
                 "Golpes do tipo \(name) causam ×1,2 de dano. Com Arceus, ele vira tipo \(name), assim como Julgamento.",
                 "\(name)-Attacken richten ×1,2 Schaden an. Trägt Arceus sie, wird es zum \(name)-Typ, ebenso Richtspruch.",
                 "Атаки типа \(name) наносят ×1,2 урона. У Арсеуса меняет его тип на \(name), как и тип атаки «Правосудие».")
    }

    private func primalOrbEffect(_ species: String) -> String {
        t("\(species)만 쓸 수 있어요. 배틀을 시작하면 원시회귀해요. 메가진화와 합쳐 한 배틀에 한 마리만 변하고, 앞선 포켓몬이 먼저 해요.",
          "Only \(species) can use it. It undergoes Primal Reversion when a battle starts. It shares the one-per-battle limit with Mega Evolution, and an earlier Pokémon goes first.",
          "使えるのは\(species)だけ。バトル開始時にゲンシカイキします。メガシンカと合わせて1バトルに1匹だけで、先に出たポケモンが優先です。",
          "Solo \(species) puede usarlo. Experimenta la Regresión Primigenia al empezar el combate. Comparte con la megaevolución el límite de uno por combate, y va primero el de delante.",
          "Seul \(species) peut l'utiliser. Il subit la Primo-Résurgence au début du combat. Il partage avec la méga-évolution la limite d'un seul par combat, et le premier en ligne passe devant.",
          "Só \(species) pode usá-lo. Ele passa pela Regressão Primitiva no início da batalha. Divide com a Mega Evolução o limite de um por batalha, e o da frente vai primeiro.",
          "Nur \(species) kann ihn nutzen. Es durchläuft zu Kampfbeginn die Proto-Rückentwicklung. Mit der Mega-Entwicklung teilt er sich das Limit von einem pro Kampf, das vordere Pokémon zuerst.",
          "Только \(species) может его использовать. В начале боя происходит первобытный возврат. Делит с мега-эволюцией лимит «один за бой», сначала тот, кто впереди.")
    }

    private func originItemEffect(_ species: String, second: String) -> String {
        let types = [battleTypeName("dragon"), battleTypeName(second)].joined(separator: "/")
        return t("\(species)만 쓸 수 있어요. 오리진폼으로 싸우고 \(types)타입 기술의 데미지가 1.2배예요.",
                 "Only \(species) can use it. It fights in its Origin Forme, and its \(types)-type moves deal ×1.2 damage.",
                 "使えるのは\(species)だけ。オリジンフォルムで戦い、\(types)タイプの技のダメージが1.2倍。",
                 "Solo \(species) puede usarlo. Lucha en su Forma Origen y sus movimientos de tipo \(types) hacen ×1,2 de daño.",
                 "Seul \(species) peut l'utiliser. Il combat sous sa Forme Originelle et ses attaques de type \(types) font ×1,2 de dégâts.",
                 "Só \(species) pode usá-lo. Luta na Forma Origem e seus golpes do tipo \(types) causam ×1,2 de dano.",
                 "Nur \(species) kann ihn nutzen. Es kämpft in seiner Urform und seine \(types)-Attacken richten ×1,2 Schaden an.",
                 "Только \(species) может его использовать. Сражается в Изначальной форме, атаки типов \(types) наносят ×1,2 урона.")
    }

    private var groudonName: String { t("그란돈", "Groudon", "グラードン", "Groudon", "Groudon", "Groudon", "Groudon", "Граудон") }
    private var kyogreName: String { t("가이오가", "Kyogre", "カイオーガ", "Kyogre", "Kyogre", "Kyogre", "Kyogre", "Кайогр") }
    private var dialgaName: String { t("디아루가", "Dialga", "ディアルガ", "Dialga", "Dialga", "Dialga", "Dialga", "Диалга") }
    private var palkiaName: String { t("펄기아", "Palkia", "パルキア", "Palkia", "Palkia", "Palkia", "Palkia", "Палкия") }
    private var giratinaName: String { t("기라티나", "Giratina", "ギラティナ", "Giratina", "Giratina", "Giratina", "Giratina", "Гиратина") }
}
