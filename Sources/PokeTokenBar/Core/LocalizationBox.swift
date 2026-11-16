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
        t("설정에서 연결하기", "Connect in Settings", "設定でつなぐ", "Conectar en Ajustes",
          "Connecter dans Réglages", "Conectar nos Ajustes", "In den Einstellungen verbinden",
          "Подключить в настройках")
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

    /// The Battle tab only picks the lineup; each row opens that Pokémon's Box page, where its moves and item are set.
    var battleTraining: String {
        t("트레이닝", "Training", "トレーニング", "Entrenar", "Entraîner", "Treinar", "Training", "Тренировка")
    }

    var moveGroupLevelUp: String {
        t("레벨업", "Level-up", "レベルアップ", "Por nivel", "Niveau", "Por nível", "Level-up", "По уровню")
    }

    var moveGroupMachine: String {
        t("기술머신", "TM", "わざマシン", "MT", "CT", "TM", "TM", "ТМ")
    }

    var moveSlotEmpty: String {
        t("기술 추가", "Add a move", "わざを追加", "Añadir movimiento", "Ajouter une capacité", "Adicionar golpe",
          "Attacke hinzufügen", "Добавить приём")
    }

    var moveTrainingHint: String {
        t("기술을 눌러 바꿔요. 기술머신 기술은 레벨과 상관없이 쓸 수 있어요. 대결에 나가는 포켓몬에게만 쓰여요.",
          "Tap a move to swap it. TM moves work at any level. Only Pokémon in the lineup use them.",
          "わざをタップして入れ替えます。わざマシンのわざはレベルに関係なく使えます。対戦に出るポケモンだけに使われます。",
          "Toca un movimiento para cambiarlo. Los de MT valen a cualquier nivel. Solo los usan los Pokémon de la alineación.",
          "Touche une capacité pour la changer. Celles des CT marchent à tout niveau. Seuls les Pokémon de l'équipe s'en servent.",
          "Toque num golpe para trocá-lo. Os de TM valem em qualquer nível. Só os Pokémon da formação os usam.",
          "Tippe eine Attacke an, um sie zu tauschen. TM-Attacken gehen auf jedem Level. Nur Pokémon in der Aufstellung nutzen sie.",
          "Нажмите на приём, чтобы заменить. Приёмы ТМ доступны на любом уровне. Их используют только покемоны из состава.")
    }

    var shopMachineHint: String {
        t("한 번 사면 계속 써요. 그 기술을 배우는 내 포켓몬은 모두 쓸 수 있어요.",
          "Buy a TM once and keep it. Every Pokémon of yours that can learn the move may use it.",
          "一度買えばずっと使えます。そのわざを覚えられる手持ちのポケモンはみな使えます。",
          "Cómprala una vez y es tuya. Todos tus Pokémon que aprendan el movimiento pueden usarla.",
          "Achète-la une fois, elle reste à toi. Tous tes Pokémon qui apprennent la capacité peuvent l'utiliser.",
          "Compre uma vez e fica sua. Todos os seus Pokémon que aprendem o golpe podem usar.",
          "Einmal kaufen, für immer behalten. Alle deine Pokémon, die die Attacke lernen, dürfen sie nutzen.",
          "Купите ТМ один раз, и она ваша. Её могут использовать все ваши покемоны, способные выучить приём.")
    }

    var shopMachineSearchPrompt: String {
        t("기술 이름 검색…", "Search moves…", "わざ名で検索…", "Buscar movimientos…", "Rechercher une capacité…",
          "Buscar golpes…", "Attacke suchen…", "Поиск приёмов…")
    }

    var shopMachineLearnableOnly: String {
        t("내 포켓몬이 배울 수 있는 기술만", "Only moves my Pokémon can learn", "手持ちが覚えられるわざだけ",
          "Solo lo que aprenden mis Pokémon", "Seulement ce que mes Pokémon apprennent",
          "Só o que meus Pokémon aprendem", "Nur was meine Pokémon lernen", "Только то, что учат мои покемоны")
    }

    func shopMachineMine(_ count: Int) -> String {
        t("내 포켓몬 \(count)마리", "\(count) of yours", "手持ち\(count)匹", "\(count) tuyos", "\(count) à toi",
          "\(count) seus", "\(count) von dir", "ваших: \(count)")
    }

    var shopMachineEmpty: String {
        t("맞는 기술머신이 없어요.", "No TMs match.", "該当するわざマシンがありません。", "Ninguna MT coincide.",
          "Aucune CT ne correspond.", "Nenhuma TM encontrada.", "Keine passende TM.", "Подходящих ТМ нет.")
    }

    var moveWeatherMove: String {
        t("날씨 기술", "Weather move", "天気わざ", "Mov. de clima", "Capacité météo", "Golpe de clima",
          "Wetter-Attacke", "Погодный приём")
    }

    var heldItemEquipAtTop: String {
        t("위쪽 지닌 도구 칸에서 장착해요.", "Equip it in the held item slot above.", "上のもちもの欄で持たせます。",
          "Equípalo en la casilla de objeto de arriba.", "Équipe-le dans l'emplacement d'objet ci-dessus.",
          "Equipe no espaço de item acima.", "Rüste es im Item-Feld oben aus.", "Выдайте его в ячейке предмета выше.")
    }
}

extension L {
    func title(of tab: SettingsTab) -> String {
        switch tab {
        case .general: generalSectionTitle
        case .usage: settingsTabUsage
        case .companion: settingsTabCompanion
        case .notifications: notificationsSection
        case .ypoke: "YPoke"
        case .advanced: advancedSectionTitle
        }
    }

    var settingsTabUsage: String {
        t("사용량", "Usage", "使用量", "Uso", "Utilisation", "Uso", "Nutzung", "Использование")
    }

    var settingsTabCompanion: String {
        t("동반자", "Companion", "相棒", "Compañero", "Compagnon", "Companheiro", "Begleiter", "Спутник")
    }

    var ypokeBattleLinkLine: String {
        t("YPoke 연결 안 됨 · 설정에서 연결", "YPoke not connected · Connect in Settings",
          "YPoke未接続 · 設定でつなぐ", "YPoke sin conectar · Conectar en Ajustes",
          "YPoke non connecté · Connecter dans Réglages", "YPoke não conectado · Conectar nos Ajustes",
          "YPoke nicht verbunden · In den Einstellungen verbinden", "YPoke не подключён · Подключить в настройках")
    }
}
