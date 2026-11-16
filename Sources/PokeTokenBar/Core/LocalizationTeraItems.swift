import Foundation

/// Effect text of Ogerpon's masks and Terapagos' Stellar Crystal.
extension L {
    func maskEffect(_ kind: ItemKind) -> String {
        let types = (kind.formSprite?.types ?? ["grass"]).map(battleTypeName).joined(separator: "/")
        let stat = statName(kind.maskEntryStat ?? "speed")
        return t("오거폰만 쓸 수 있어요. \(types) 타입이 되고, 모든 기술의 데미지가 1.2배예요. 배틀에 나가면 \(stat)이(가) 1단계 올라요.",
                 "Only Ogerpon can use it. It becomes \(types) type and all its moves deal ×1.2 damage. On entering battle, \(stat) rises by 1 stage.",
                 "使えるのはオーガポンだけ。\(types)タイプになり、すべての技のダメージが1.2倍。バトルに出ると\(stat)が1段階上がります。",
                 "Solo Ogerpon puede usarla. Pasa a tipo \(types) y todos sus movimientos hacen ×1,2 de daño. Al entrar en combate, \(stat) sube 1 nivel.",
                 "Seul Ogerpon peut l'utiliser. Il devient de type \(types) et toutes ses attaques font ×1,2 de dégâts. À l'entrée au combat, \(stat) monte d'un niveau.",
                 "Só Ogerpon pode usá-la. Ele passa ao tipo \(types) e todos os seus golpes causam ×1,2 de dano. Ao entrar em batalha, \(stat) sobe 1 estágio.",
                 "Nur Ogerpon kann sie nutzen. Es wird zum \(types)-Typ und alle Attacken richten ×1,2 Schaden an. Beim Betreten des Kampfs steigt \(stat) um 1 Stufe.",
                 "Только Огерпон может её использовать. Он получает тип \(types), и все его атаки наносят ×1,2 урона. При выходе в бой \(stat) растёт на 1 ступень.")
    }

    var stellarCrystalEffect: String {
        t("테라파고스만 쓸 수 있어요. 배틀을 시작하면 스텔라폼이 돼요. 메가진화와 합쳐 한 배틀에 한 마리만 변하고, 앞선 포켓몬이 먼저 해요. 홈 화면과 박스에서도 스텔라폼 모습이에요.",
          "Only Terapagos can use it. It takes its Stellar Form when a battle starts. It shares the one-per-battle limit with Mega Evolution, and an earlier Pokémon goes first. Shown in Stellar Form on the home screen and in the Box too.",
          "使えるのはテラパゴスだけ。バトル開始時にステラフォルムになります。メガシンカと合わせて1バトルに1匹だけで、先に出たポケモンが優先です。ホーム画面とボックスでもステラフォルムの姿になります。",
          "Solo Terapagos puede usarlo. Adopta la Forma Astral al empezar el combate. Comparte con la megaevolución el límite de uno por combate, y va primero el de delante. También se ve en Forma Astral en la pantalla de inicio y en la Caja.",
          "Seul Terapagos peut l'utiliser. Il prend la Forme Stellaire au début du combat. Il partage avec la méga-évolution la limite d'un seul par combat, et le premier en ligne passe devant. Visible en Forme Stellaire sur l'écran d'accueil et dans la Boîte.",
          "Só Terapagos pode usá-lo. Ele assume a Forma Estelar no início da batalha. Divide com a Mega Evolução o limite de um por batalha, e o da frente vai primeiro. Também aparece na Forma Estelar na tela inicial e na Caixa.",
          "Nur Terapagos kann ihn nutzen. Es nimmt zu Kampfbeginn die Stellar-Form an. Mit der Mega-Entwicklung teilt er sich das Limit von einem pro Kampf, das vordere Pokémon zuerst. Auch auf dem Startbildschirm und in der Box in Stellar-Form zu sehen.",
          "Только Терапагос может его использовать. В начале боя он принимает Звёздную форму. Делит с мега-эволюцией лимит «один за бой», сначала тот, кто впереди. Звёздная форма видна и на главном экране, и в Коробке.")
    }
}
