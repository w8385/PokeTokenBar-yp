import Foundation

/// Mint, Ability Capsule and Patch, Bottle Caps and the form key items.
extension L {
    func trainingItemName(_ kind: ItemKind) -> String? {
        switch kind {
        case .abilityCapsule:
            t("특성캡슐", "Ability Capsule", "とくせいカプセル", "Cáps. Habilidad", "Pilule Talent", "Cápsula de Habilidade",
              "Fähigkeiten-Kapsel", "Капсула способности")
        case .abilityPatch:
            t("특성패치", "Ability Patch", "とくせいパッチ", "Parche Habilidad", "Patch Talent", "Adesivo de Habilidade",
              "Fähigkeiten-Pflaster", "Пластырь способности")
        case .bottleCap:
            t("은색병뚜껑", "Bottle Cap", "ぎんのおうかん", "Chapa Plateada", "Capsule d’Argent", "Tampinha de Prata",
              "Silberkronkorken", "Серебряная крышка")
        case .goldBottleCap:
            t("금색병뚜껑", "Gold Bottle Cap", "きんのおうかん", "Chapa Dorada", "Capsule d’Or", "Tampinha de Ouro",
              "Goldkronkorken", "Золотая крышка")
        case .revealGlass:
            t("비추는거울", "Reveal Glass", "うつしかがみ", "Espejo Veraz", "Miroir Sacré", "Espelho da Verdade",
              "Wahrspiegel", "Зеркало истины")
        case .dnaSplicers:
            t("유전자쐐기", "DNA Splicers", "いでんしのくさび", "Punta ADN", "Pointeau ADN", "Cunha de DNA",
              "DNS-Keil", "ДНК-клинья")
        case .reinsOfUnity:
            t("유대의고삐", "Reins of Unity", "キズナのタヅナ", "Riendas Unión", "Rênes de l’Unité", "Rédeas da União",
              "Zügel des Bundes", "Поводья единства")
        default: nil
        }
    }

    /// What the item does in this app, one line.
    func trainingEffect(_ kind: ItemKind) -> String? {
        switch kind {
        case .mint:
            t("고른 성격으로 바꿔요. 성격 옆 민트 버튼으로 바로 쓸 수 있어요.",
              "Changes the nature to the one you pick. Use the Mint button next to a nature.",
              "えらんだせいかくに変えます。せいかくの横のミントボタンからすぐ使えます。",
              "Cambia la naturaleza por la que elijas. Usa el botón de Menta junto a la naturaleza.",
              "Change la nature pour celle que tu choisis. Utilise le bouton Menthe à côté de la nature.",
              "Muda a natureza para a que você escolher. Use o botão de Menta ao lado da natureza.",
              "Ändert das Wesen in das gewählte. Nutze die Minze-Taste neben dem Wesen.",
              "Меняет характер на выбранный. Кнопка мяты стоит рядом с характером.")
        case .abilityCapsule:
            t("종의 다른 일반 특성으로 바꿔요. 숨겨진 특성이나 특성이 하나뿐인 종에는 쓸 수 없어요.",
              "Switches to the species' other regular ability. Not for a hidden ability or a species with one ability.",
              "種族のもうひとつの通常特性に変えます。隠れ特性や特性がひとつの種族には使えません。",
              "Cambia a la otra habilidad normal de la especie. No sirve con habilidad oculta ni con una sola habilidad.",
              "Passe à l'autre talent normal de l'espèce. Pas pour un talent caché ni une espèce à talent unique.",
              "Troca para a outra habilidade normal da espécie. Não serve para habilidade oculta nem espécie com uma só.",
              "Wechselt zur anderen normalen Fähigkeit der Art. Nicht für versteckte oder einzige Fähigkeiten.",
              "Меняет на другую обычную способность вида. Не для скрытой и не для вида с одной способностью.")
        case .abilityPatch:
            t("일반 특성과 숨겨진 특성을 서로 바꿔요.",
              "Switches between a regular ability and the hidden one.",
              "通常特性と隠れ特性を入れ替えます。",
              "Cambia entre una habilidad normal y la oculta.",
              "Passe d'un talent normal au talent caché, et inversement.",
              "Troca entre uma habilidade normal e a oculta.",
              "Wechselt zwischen einer normalen und der versteckten Fähigkeit.",
              "Меняет обычную способность на скрытую и обратно.")
        case .bottleCap:
            t("고른 능력치 하나의 개체값을 31로 올려요.",
              "Raises one chosen IV to 31.",
              "えらんだ能力ひとつの個体値を31にします。",
              "Sube a 31 el IV que elijas.",
              "Monte à 31 l'IV de ton choix.",
              "Aumenta para 31 o IV escolhido.",
              "Setzt einen gewählten DV auf 31.",
              "Поднимает выбранный IV до 31.")
        case .goldBottleCap:
            t("여섯 개체값을 모두 31로 올려요.",
              "Raises all six IVs to 31.",
              "6つの個体値をすべて31にします。",
              "Sube a 31 los seis IV.",
              "Monte les six IV à 31.",
              "Aumenta os seis IVs para 31.",
              "Setzt alle sechs DVs auf 31.",
              "Поднимает все шесть IV до 31.")
        case .revealGlass:
            t("토네로스·볼트로스·랜드로스·러브로스를 화신폼과 영물폼 사이에서 바꿔요. 쓰지 않아도 없어지지 않아요.",
              "Switches Tornadus, Thundurus, Landorus and Enamorus between Incarnate and Therian Forme. Never used up.",
              "トルネロス・ボルトロス・ランドロス・ラブトロスをけしんとれいじゅうの間で変えます。なくなりません。",
              "Cambia a Tornadus, Thundurus, Landorus y Enamorus entre Forma Avatar y Tótem. No se gasta.",
              "Fait passer Boréas, Fulguris, Démétéros et Amovénus de Forme Avatar à Totémique. Jamais consommé.",
              "Troca Tornadus, Thundurus, Landorus e Enamorus entre Forma Materializada e Therian. Nunca se gasta.",
              "Wechselt Boreos, Voltolos, Demeteros und Cupidos zwischen Inkarnations- und Tiergeistform. Wird nicht verbraucht.",
              "Переключает Торнадуса, Тандуруса, Ландоруса и Энаморуса между воплощённой и териан-формой. Не расходуется.")
        case .dnaSplicers:
            t("큐레무를 원래 모습·블랙큐레무·화이트큐레무 사이에서 바꿔요. 쓰지 않아도 없어지지 않아요.",
              "Switches Kyurem between its usual form, Black Kyurem and White Kyurem. Never used up.",
              "キュレムをいつもの姿・ブラックキュレム・ホワイトキュレムの間で変えます。なくなりません。",
              "Cambia a Kyurem entre su forma normal, Kyurem Negro y Kyurem Blanco. No se gasta.",
              "Fait passer Kyurem de sa forme normale à Kyurem Noir ou Blanc. Jamais consommé.",
              "Troca Kyurem entre a forma normal, Kyurem Negro e Kyurem Branco. Nunca se gasta.",
              "Wechselt Kyurem zwischen normaler Form, Schwarzem und Weißem Kyurem. Wird nicht verbraucht.",
              "Переключает Кюрема между обычной формой, Чёрным и Белым Кюремом. Не расходуется.")
        case .reinsOfUnity:
            t("버드렉스를 원래 모습·백마 탄 모습·흑마 탄 모습 사이에서 바꿔요. 쓰지 않아도 없어지지 않아요.",
              "Switches Calyrex between its usual form, Ice Rider and Shadow Rider. Never used up.",
              "バドレックスをいつもの姿・はくばじょう・こくばじょうの間で変えます。なくなりません。",
              "Cambia a Calyrex entre su forma normal, Jinete Glacial y Jinete Espectral. No se gasta.",
              "Fait passer Sylveroy de sa forme normale à Cavalier du Froid ou d'Effroi. Jamais consommé.",
              "Troca Calyrex entre a forma normal, Cavaleiro Glacial e Cavaleiro Espectral. Nunca se gasta.",
              "Wechselt Coronospa zwischen normaler Form, Schimmel- und Rappenreiter. Wird nicht verbraucht.",
              "Переключает Каляйрекса между обычной формой, Ледяным и Теневым всадником. Не расходуется.")
        default: nil
        }
    }

    func trainingItemHelp(_ kind: ItemKind) -> String { trainingEffect(kind) ?? itemName(kind) }

    func trainingBagHint(_ kind: ItemKind) -> String {
        kind == .mint
            ? t("포켓몬을 고른 뒤 성격을 골라요", "Pick a Pokémon, then its nature", "ポケモンをえらんでからせいかくをえらぶ",
                "Elige un Pokémon y luego su naturaleza", "Choisis un Pokémon puis sa nature",
                "Escolha um Pokémon e depois a natureza", "Pokémon wählen, dann sein Wesen",
                "Выберите покемона, затем характер")
            : t("포켓몬을 고르면 박스 화면에서 써요", "Pick a Pokémon to use it on its Box page",
                "ポケモンをえらぶとボックス画面で使えます", "Elige un Pokémon para usarlo en su página de la Caja",
                "Choisis un Pokémon pour l'utiliser sur sa page de Boîte", "Escolha um Pokémon para usar na página da Caixa",
                "Wähle ein Pokémon, um es auf seiner Box-Seite zu nutzen",
                "Выберите покемона, чтобы применить на его странице Бокса")
    }

    var trainingPickTarget: String {
        t("누구에게 쓸까요?", "Use it on which Pokémon?", "どのポケモンに使う？", "¿En qué Pokémon?", "Sur quel Pokémon ?",
          "Em qual Pokémon?", "Bei welchem Pokémon?", "На какого покемона?")
    }

    var trainingNoTarget: String {
        t("쓸 수 있는 포켓몬이 없어요.", "No Pokémon to use it on.", "使えるポケモンがいません。",
          "No hay ningún Pokémon en el que usarlo.", "Aucun Pokémon sur qui l'utiliser.",
          "Nenhum Pokémon para usar.", "Kein Pokémon, bei dem es wirkt.", "Нет покемона, на котором это сработает.")
    }

    var trainingUnavailable: String {
        t("지금 이 포켓몬에게는 쓸 수 없어요.", "Can't use it on this Pokémon right now.",
          "いまこのポケモンには使えません。", "Ahora no se puede usar en este Pokémon.",
          "Impossible de l'utiliser sur ce Pokémon pour l'instant.", "Não dá para usar neste Pokémon agora.",
          "Bei diesem Pokémon gerade nicht nutzbar.", "Сейчас нельзя применить к этому покемону.")
    }

    var abilityNothingToSwitch: String {
        t("이 포켓몬은 바꿀 특성이 없어요. 아이템은 그대로 남아요.",
          "This Pokémon has no other ability to switch to. The item stays in the bag.",
          "このポケモンには変えられる特性がありません。道具はそのまま残ります。",
          "Este Pokémon no tiene otra habilidad. El objeto se queda en la mochila.",
          "Ce Pokémon n'a pas d'autre talent. L'objet reste dans le sac.",
          "Este Pokémon não tem outra habilidade. O item fica na bolsa.",
          "Dieses Pokémon hat keine andere Fähigkeit. Das Item bleibt im Beutel.",
          "У этого покемона нет другой способности. Предмет остаётся в сумке.")
    }

    func bottleCapUse(_ stat: String) -> String {
        t("은색병뚜껑: \(stat) 개체값을 31로", "Bottle Cap: \(stat) IV to 31", "ぎんのおうかん：\(stat)の個体値を31に",
          "Chapa Plateada: IV de \(stat) a 31", "Capsule d’Argent : IV \(stat) à 31", "Tampinha de Prata: IV de \(stat) para 31",
          "Silberkronkorken: \(stat)-DV auf 31", "Серебряная крышка: IV «\(stat)» до 31")
    }

    // MARK: Nature picker

    var naturePickerTitle: String {
        t("성격 고르기", "Pick a nature", "せいかくをえらぶ", "Elige naturaleza", "Choisir une nature", "Escolher natureza",
          "Wesen wählen", "Выбор характера")
    }

    var natureCurrent: String {
        t("지금 성격", "Current", "いまのせいかく", "Actual", "Actuelle", "Atual", "Aktuell", "Текущий")
    }

    var naturePicked: String {
        t("고름", "Picked", "えらんだ", "Elegida", "Choisie", "Escolhida", "Gewählt", "Выбран")
    }

    var mintChange: String { t("바꾸기", "Change", "かえる", "Cambiar", "Changer", "Trocar", "Ändern", "Сменить") }

    var mintChangeHelp: String {
        t("민트로 성격 바꾸기", "Change the nature with a Mint", "ミントでせいかくを変える", "Cambiar naturaleza con Menta",
          "Changer de nature avec une Menthe", "Mudar a natureza com Menta", "Wesen mit Minze ändern",
          "Сменить характер мятой")
    }

    func mintConfirmLine(_ name: String, from: String, to: String) -> String { "\(name): \(from) → \(to)" }

    func mintPaymentLine(_ payment: MintPayment) -> String {
        switch payment {
        case .stock(let count):
            t("민트 1개를 써요 (남은 민트 \(count - 1)개)", "Uses 1 Mint (\(count - 1) left)",
              "ミントを1個使います（残り\(count - 1)個）", "Usa 1 Menta (quedan \(count - 1))",
              "Utilise 1 Menthe (reste \(count - 1))", "Usa 1 Menta (restam \(count - 1))",
              "Verbraucht 1 Minze (noch \(count - 1))", "Тратит 1 мяту (останется \(count - 1))")
        case .buy(let price):
            t("가방에 민트가 없어요. \(TokenFormatter.compact(price))에 사서 바로 써요.",
              "No Mint in the bag. Buys one for \(TokenFormatter.compact(price)) and uses it.",
              "バッグにミントがありません。\(TokenFormatter.compact(price))で買ってすぐ使います。",
              "No tienes Menta. Compra una por \(TokenFormatter.compact(price)) y la usa.",
              "Pas de Menthe dans le sac. En achète une pour \(TokenFormatter.compact(price)) et l'utilise.",
              "Sem Menta na bolsa. Compra uma por \(TokenFormatter.compact(price)) e usa.",
              "Keine Minze im Beutel. Kauft eine für \(TokenFormatter.compact(price)) und nutzt sie.",
              "Мяты нет в сумке. Купит одну за \(TokenFormatter.compact(price)) и применит.")
        case .short(let price):
            t("토큰이 모자라요. 민트는 \(TokenFormatter.compact(price))이에요.",
              "Not enough tokens. A Mint costs \(TokenFormatter.compact(price)).",
              "トークンが足りません。ミントは\(TokenFormatter.compact(price))です。",
              "No tienes tokens suficientes. Una Menta cuesta \(TokenFormatter.compact(price)).",
              "Pas assez de jetons. Une Menthe coûte \(TokenFormatter.compact(price)).",
              "Tokens insuficientes. Uma Menta custa \(TokenFormatter.compact(price)).",
              "Nicht genug Tokens. Eine Minze kostet \(TokenFormatter.compact(price)).",
              "Не хватает токенов. Мята стоит \(TokenFormatter.compact(price)).")
        }
    }

    func mintConfirmButton(_ payment: MintPayment) -> String {
        if case .stock = payment { return use }
        return t("사서 쓰기", "Buy & use", "買って使う", "Comprar y usar", "Acheter et utiliser", "Comprar e usar",
                 "Kaufen & nutzen", "Купить и применить")
    }
}
