import Foundation

/// The Mirror Herb and the attacking egg moves it unlocks.
extension L {
    var mirrorHerbName: String {
        t("흉내허브", "Mirror Herb", "ものまねハーブ", "Hierba Copia", "Feuille Copieuse", "Erva Espelho", "Kopierkraut",
          "Зеркальная трава")
    }

    var mirrorHerbEffect: String {
        t("포켓몬 하나의 알 기술(공격기)을 영영 배울 수 있게 해요. 진화해도 그대로예요.",
          "Lets one Pokémon learn its attacking egg moves for good, also after it evolves.",
          "ポケモン1匹がタマゴわざ（攻撃技）をずっとおぼえられるようにします。進化してもそのままです。",
          "Permite a un Pokémon aprender sus movimientos huevo de ataque para siempre, aunque evolucione.",
          "Permet à un Pokémon d'apprendre ses capacités Œuf offensives pour de bon, même après évolution.",
          "Deixa um Pokémon aprender seus golpes de ovo de ataque para sempre, mesmo depois de evoluir.",
          "Ein Pokémon kann seine offensiven Ei-Attacken dauerhaft erlernen, auch nach der Entwicklung.",
          "Покемон навсегда сможет учить атакующие яйцевые приёмы, даже после эволюции.")
    }

    var moveGroupEgg: String {
        t("알 기술", "Egg moves", "タマゴわざ", "Movimientos huevo", "Capacités Œuf", "Golpes de ovo", "Ei-Attacken",
          "Яйцевые приёмы")
    }

    var mirrorHerbNeeded: String {
        t("흉내허브 필요", "Needs a Mirror Herb", "ものまねハーブが必要", "Necesita Hierba Copia", "Feuille Copieuse requise",
          "Precisa de Erva Espelho", "Braucht Kopierkraut", "Нужна зеркальная трава")
    }

    var mirrorHerbUse: String {
        t("흉내허브 쓰기", "Use Mirror Herb", "ものまねハーブを使う", "Usar Hierba Copia", "Utiliser Feuille Copieuse",
          "Usar Erva Espelho", "Kopierkraut nutzen", "Применить траву")
    }

    var mirrorHerbBagHint: String {
        t("포켓몬을 고르면 알 기술이 열려요", "Pick a Pokémon to unlock its egg moves",
          "ポケモンをえらぶとタマゴわざが使えます", "Elige un Pokémon para desbloquear sus movimientos huevo",
          "Choisis un Pokémon pour débloquer ses capacités Œuf", "Escolha um Pokémon para liberar os golpes de ovo",
          "Wähle ein Pokémon, um seine Ei-Attacken freizuschalten", "Выберите покемона, чтобы открыть яйцевые приёмы")
    }

    func mirrorHerbConfirmLine(_ name: String) -> String {
        t("\(name)의 알 기술을 열어요", "Unlock \(name)'s egg moves", "\(name)のタマゴわざを解放",
          "Desbloquear los movimientos huevo de \(name)", "Débloquer les capacités Œuf de \(name)",
          "Liberar os golpes de ovo de \(name)", "Ei-Attacken von \(name) freischalten",
          "Открыть яйцевые приёмы: \(name)")
    }

    func mirrorHerbPaymentLine(_ payment: MintPayment) -> String {
        switch payment {
        case .stock(let count):
            t("흉내허브 1개를 써요 (남은 흉내허브 \(count - 1)개)", "Uses 1 Mirror Herb (\(count - 1) left)",
              "ものまねハーブを1個使います（残り\(count - 1)個）", "Usa 1 Hierba Copia (quedan \(count - 1))",
              "Utilise 1 Feuille Copieuse (reste \(count - 1))", "Usa 1 Erva Espelho (restam \(count - 1))",
              "Verbraucht 1 Kopierkraut (noch \(count - 1))", "Тратит 1 траву (останется \(count - 1))")
        case .buy(let price):
            t("가방에 흉내허브가 없어요. \(TokenFormatter.compact(price))에 사서 바로 써요.",
              "No Mirror Herb in the bag. Buys one for \(TokenFormatter.compact(price)) and uses it.",
              "バッグにものまねハーブがありません。\(TokenFormatter.compact(price))で買ってすぐ使います。",
              "No tienes Hierba Copia. Compra una por \(TokenFormatter.compact(price)) y la usa.",
              "Pas de Feuille Copieuse dans le sac. En achète une pour \(TokenFormatter.compact(price)) et l'utilise.",
              "Sem Erva Espelho na bolsa. Compra uma por \(TokenFormatter.compact(price)) e usa.",
              "Kein Kopierkraut im Beutel. Kauft eins für \(TokenFormatter.compact(price)) und nutzt es.",
              "Травы нет в сумке. Купит одну за \(TokenFormatter.compact(price)) и применит.")
        case .short(let price):
            t("토큰이 모자라요. 흉내허브는 \(TokenFormatter.compact(price))이에요.",
              "Not enough tokens. A Mirror Herb costs \(TokenFormatter.compact(price)).",
              "トークンが足りません。ものまねハーブは\(TokenFormatter.compact(price))です。",
              "No tienes tokens suficientes. Una Hierba Copia cuesta \(TokenFormatter.compact(price)).",
              "Pas assez de jetons. Une Feuille Copieuse coûte \(TokenFormatter.compact(price)).",
              "Tokens insuficientes. Uma Erva Espelho custa \(TokenFormatter.compact(price)).",
              "Nicht genug Tokens. Ein Kopierkraut kostet \(TokenFormatter.compact(price)).",
              "Не хватает токенов. Трава стоит \(TokenFormatter.compact(price)).")
        }
    }
}
