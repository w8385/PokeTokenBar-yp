import Foundation

extension L {
    func title(of tab: PopoverTab) -> String {
        switch tab {
        case .home: home
        case .shop: shop
        case .bag: bag
        case .dex: dexTitle
        case .box: boxTab
        case .battle: battle
        case .coworkers: friendsTitle
        }
    }

    var coworkersNotConnected: String {
        t("YPoke 봇에 연결하면 동료와 교환할 수 있어요.", "Connect to the YPoke bot to see coworkers and trade.",
          "YPokeボットにつなぐと、同僚の確認と交換ができます。", "Conéctate al bot YPoke para ver compañeros e intercambiar.",
          "Connecte-toi au bot YPoke pour voir tes collègues et échanger.",
          "Conecte-se ao bot YPoke para ver colegas e trocar.",
          "Verbinde dich mit dem YPoke-Bot, um Kollegen zu sehen und zu tauschen.",
          "Подключитесь к боту YPoke, чтобы видеть коллег и обмениваться.")
    }

    var coworkersOpenConnection: String {
        t("대결 탭에서 연결하기", "Connect in the Battle tab", "対戦タブでつなぐ", "Conectar en la pestaña Combate",
          "Connecter dans l'onglet Combat", "Conectar na aba Batalha", "Im Kampf-Tab verbinden",
          "Подключить на вкладке «Бой»")
    }

    var boxTab: String { t("박스", "Box", "ボックス", "Caja", "Boîte", "Caixa", "Box", "Коробка") }

    var boxEmptyTitle: String {
        t("박스가 비어 있어요", "Your Box is empty", "ボックスは空っぽです", "Tu caja está vacía", "Ta boîte est vide",
          "Sua caixa está vazia", "Deine Box ist leer", "Коробка пуста")
    }

    var boxEmptyHint: String {
        t("알을 부화시키면 이곳에 내 포켓몬이 모여요.", "Hatch an egg and your Pokémon gather here.",
          "タマゴを孵すと、ここに手持ちのポケモンが集まります。", "Eclosiona un huevo y tus Pokémon se reunirán aquí.",
          "Fais éclore un œuf et tes Pokémon se retrouvent ici.", "Choque um ovo e seus Pokémon se reúnem aqui.",
          "Brüte ein Ei aus, dann sammeln sich deine Pokémon hier.", "Выведите яйцо, и ваши покемоны соберутся здесь.")
    }

    func label(for option: BoxSortOption) -> String {
        switch option {
        case .recent: t("최근", "Recent", "新しい順", "Recientes", "Récents", "Recentes", "Neueste", "Недавние")
        case .level: t("레벨", "Level", "レベル", "Nivel", "Niveau", "Nível", "Level", "Уровень")
        case .number: t("도감 번호", "Dex number", "図鑑番号", "N.º de Pokédex", "N° du Pokédex", "N.º da Pokédex",
                        "Pokédex-Nr.", "Номер в Покедексе")
        case .name: t("이름", "Name", "名前", "Nombre", "Nom", "Nome", "Name", "Имя")
        }
    }

    var boxFilterHasItem: String {
        t("도구 지님", "Holding an item", "もちもの あり", "Con objeto", "Avec objet", "Com item", "Mit Item", "С предметом")
    }

    func boxOnlySpecies(_ name: String) -> String {
        t("\(name)만 보는 중", "Showing only \(name)", "\(name)だけ表示中", "Solo \(name)", "\(name) seulement",
          "Só \(name)", "Nur \(name)", "Только \(name)")
    }

    var boxShowAll: String {
        t("전체 보기", "Show all", "すべて表示", "Ver todo", "Tout afficher", "Ver tudo", "Alle zeigen", "Показать всех")
    }

    func boxCount(_ n: Int) -> String {
        t("박스에 \(n)마리", "\(n) in your Box", "ボックスに\(n)匹", "\(n) en tu caja", "\(n) dans ta boîte",
          "\(n) na sua caixa", "\(n) in deiner Box", "В коробке: \(n)")
    }

    var boxViewInDex: String {
        t("도감에서 보기", "View in Pokédex", "図鑑で見る", "Ver en la Pokédex", "Voir dans le Pokédex", "Ver na Pokédex",
          "Im Pokédex ansehen", "Открыть в Покедексе")
    }

    var heldItemSwap: String { t("바꾸기", "Swap", "入れ替える", "Cambiar", "Changer", "Trocar", "Tauschen", "Сменить") }

    /// The Battle tab and the evolution cards only show the held item; the one place to change it is the Box.
    var heldItemChangeInBox: String {
        t("박스에서 바꿀 수 있어요", "Change it in the Box", "ボックスで変えられます", "Cámbialo en la caja",
          "Change-le dans la boîte", "Troque na caixa", "Im Box änderbar", "Меняется в коробке")
    }

    var heldItemEquipAtTop: String {
        t("위쪽 지닌 도구 칸에서 장착해요.", "Equip it in the held item slot above.", "上のもちもの欄で持たせます。",
          "Equípalo en la casilla de objeto de arriba.", "Équipe-le dans l'emplacement d'objet ci-dessus.",
          "Equipe no espaço de item acima.", "Rüste es im Item-Feld oben aus.", "Выдайте его в ячейке предмета выше.")
    }
}
