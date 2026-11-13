import Foundation

extension L {
    /// Official name from `ItemLoreTable`; pt and ru read the English name like the item text does.
    func evolutionItemName(_ kind: ItemKind) -> String {
        let slug = kind.loreSlug
        if let official = ItemLore.officialName(slug, in: lang) { return official }
        if let english = ItemLore.officialName(slug, in: .en) { return english }
        return slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    var evolutionHeldNote: String {
        t("포켓몬에게 지니게 하면 진화 조건에 쓰여요. 배틀에는 영향이 없어요.",
          "held by a Pokémon, it counts toward an evolution condition. It has no effect in battle.",
          "ポケモンに持たせると進化の条件になります。バトルでは効果がありません。",
          "si lo lleva un Pokémon, cuenta para una condición de evolución. No afecta al combate.",
          "tenu par un Pokémon, il compte pour une condition d'évolution. Sans effet en combat.",
          "se um Pokémon o segurar, conta para uma condição de evolução. Não afeta a batalha.",
          "von einem Pokémon getragen, zählt es für eine Entwicklungsbedingung. Im Kampf ohne Wirkung.",
          "если покемон держит его, он учитывается в условии эволюции. В бою не действует.")
    }

    var evolutionTradeItemNote: String {
        t("지니게 한 채 교환하면 함께 넘어가고, 진화에 쓰여요. 연결의끈으로도 같아요.",
          "held while it is traded, it goes along and is used up by the evolution. A Linking Cord works the same way.",
          "持たせたまま交換すると一緒に渡り、進化で使われます。つながりのヒモでも同じです。",
          "si lo lleva al intercambiarlo, viaja con él y se gasta en la evolución. El Cordón Unión funciona igual.",
          "tenu pendant un échange, il part avec le Pokémon et sert à l'évolution. Le Fil de Liaison fait de même.",
          "se estiver com o Pokémon na troca, vai junto e é gasto na evolução. O Cordão Elo funciona igual.",
          "beim Tausch getragen, geht es mit und wird bei der Entwicklung verbraucht. Die Verbindungsschnur wirkt genauso.",
          "если покемон держит его при обмене, он уходит вместе с ним и расходуется при эволюции. Шнур работает так же.")
    }

    var evolutionFlipAction: String {
        t("뒤집어 보기", "Turn it upside down", "さかさまにする", "Poner boca abajo", "Retourner",
          "Virar de cabeça para baixo", "Auf den Kopf stellen", "Перевернуть")
    }

    var evolutionSpinAction: String {
        t("빙글빙글 돌리기", "Spin it around", "くるくる回す", "Hacerlo girar", "Le faire tourner",
          "Girar", "Drehen", "Покрутить")
    }

    var evolutionHeldBagHint: String {
        t("도감 상세의 진화 카드에서 장착해요",
          "Equip it from the Evolution card in the dex detail",
          "図鑑の詳細にある進化カードで持たせます",
          "Equípalo desde la tarjeta de Evolución del detalle del Pokédex",
          "Équipe-le depuis la carte Évolution du détail du Pokédex",
          "Equipe no cartão de Evolução nos detalhes da Pokédex",
          "Rüste es auf der Entwicklungskarte im Pokédex-Detail aus",
          "Наденьте его на карточке «Эволюция» в описании покемона")
    }
}
