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

    var boxFilterMenu: String { t("필터", "Filters", "絞り込み", "Filtros", "Filtres", "Filtros", "Filter", "Фильтры") }
    var boxFilterType: String { t("타입", "Type", "タイプ", "Tipo", "Type", "Tipo", "Typ", "Тип") }
    var boxFilterRarity: String { t("등급", "Rarity", "レア度", "Rareza", "Rareté", "Raridade", "Seltenheit", "Редкость") }
    var boxFilterInLineup: String {
        t("대결 엔트리", "In battle lineup", "対戦メンバー", "En la alineación", "Dans l'équipe de combat",
          "Na escalação", "In der Kampfaufstellung", "В боевом составе")
    }
    var boxFilterTradable: String {
        t("교환 가능", "Tradable now", "交換できる", "Intercambiable", "Échangeable", "Pode trocar", "Tauschbar", "Можно обменять")
    }
    var boxFilterLevel: String { t("레벨", "Level", "レベル", "Nivel", "Niveau", "Nível", "Level", "Уровень") }

    func label(for level: BoxLevelFilter) -> String {
        switch level {
        case .any: t("전체", "All", "すべて", "Todos", "Tous", "Todos", "Alle", "Все")
        case .fiftyPlus: t("Lv50 이상", "Lv50 and up", "Lv50以上", "Nv. 50 o más", "Niv. 50 et plus", "Nv. 50 ou mais",
                           "Lv. 50 und höher", "Ур. 50 и выше")
        case .underFifty: t("Lv50 미만", "Under Lv50", "Lv50未満", "Menos de Nv. 50", "Moins de niv. 50",
                            "Abaixo do Nv. 50", "Unter Lv. 50", "Ниже ур. 50")
        }
    }

    var purchaseDone: String { t("구매함", "Bought", "購入しました", "Comprado", "Acheté", "Comprado", "Gekauft", "Куплено") }
    var purchaseUndo: String { t("되돌리기", "Undo", "元に戻す", "Deshacer", "Annuler", "Desfazer", "Rückgängig", "Отменить") }

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

    var moveGroupStatus: String {
        t("변화 기술", "Status moves", "変化技", "Movimientos de estado", "Capacités de statut", "Golpes de status",
          "Statusattacken", "Статусные приёмы")
    }

    var moveStatusClass: String { t("변화", "Status", "変化", "Estado", "Statut", "Status", "Status", "Статус") }

    var moveEggSource: String {
        t("알 기술", "Egg move", "タマゴわざ", "Mov. huevo", "Cap. Œuf", "Golpe de ovo", "Ei-Attacke", "Яйцевой")
    }

    /// What the bot's battle does with each status move it offers (`GET /v1/moves?status=1`), by PokéAPI id.
    func statusMoveEffect(_ moveID: Int) -> String? {
        switch moveID {
        case 14:
            t("공격 2랭크 상승", "Attack +2 stages", "こうげき2段階アップ", "Ataque +2 niveles", "Attaque +2 niveaux",
              "Ataque +2 estágios", "Angriff +2 Stufen", "Атака +2 ступени")
        case 86:
            t("상대를 마비", "Paralyzes the target", "相手をまひさせる", "Paraliza al objetivo", "Paralyse la cible",
              "Paralisa o alvo", "Paralysiert das Ziel", "Парализует цель")
        case 281:
            t("다음 턴 끝에 상대가 잠듦", "Target sleeps at the end of next turn", "次のターンの終わりに相手がねむる",
              "El objetivo se duerme al final del siguiente turno", "La cible s'endort à la fin du tour suivant",
              "O alvo adormece no fim do próximo turno", "Ziel schläft am Ende der nächsten Runde ein",
              "Цель засыпает в конце следующего хода")
        case 433:
            t("5턴 동안 느린 포켓몬부터 행동", "Slower Pokémon move first for 5 turns", "5ターンの間 遅いポケモンから動く",
              "Los Pokémon lentos actúan primero 5 turnos", "Les Pokémon lents agissent d'abord pendant 5 tours",
              "Pokémon mais lentos agem primeiro por 5 turnos", "Langsamere Pokémon handeln 5 Runden zuerst",
              "5 ходов первыми ходят медленные покемоны")
        case 446:
            t("교체해 나오는 상대에게 바위 피해", "Foes that switch in take Rock damage", "交代で出てくる相手にいわのダメージ",
              "Los rivales que entran reciben daño Roca", "Les adversaires qui entrent subissent des dégâts Roche",
              "Rivais que entram sofrem dano de Pedra", "Eingewechselte Gegner nehmen Gestein-Schaden",
              "Выходящие соперники получают урон Камнем")
        case 604:
            t("5턴 동안 전기 기술 강화, 땅 위 포켓몬은 잠들지 않음", "5 turns: Electric moves up, grounded Pokémon can't fall asleep",
              "5ターン でんきわざ強化、地面にいるポケモンはねむらない",
              "5 turnos: más poder Eléctrico, los Pokémon en el suelo no se duermen",
              "5 tours : capacités Électrik renforcées, pas de sommeil au sol",
              "5 turnos: golpes Elétricos mais fortes, Pokémon no chão não dormem",
              "5 Runden: Elektro-Attacken stärker, Pokémon am Boden schlafen nicht ein",
              "5 ходов: электроприёмы сильнее, покемоны на земле не засыпают")
        case 580:
            t("5턴 동안 풀 기술 강화, 땅 위 포켓몬 매 턴 회복", "5 turns: Grass moves up, grounded Pokémon heal each turn",
              "5ターン くさわざ強化、地面にいるポケモンが毎ターン回復",
              "5 turnos: más poder Planta, los Pokémon en el suelo se curan cada turno",
              "5 tours : capacités Plante renforcées, soin à chaque tour au sol",
              "5 turnos: golpes de Planta mais fortes, Pokémon no chão curam a cada turno",
              "5 Runden: Pflanzen-Attacken stärker, Pokémon am Boden heilen jede Runde",
              "5 ходов: травяные приёмы сильнее, покемоны на земле лечатся каждый ход")
        case 678:
            t("5턴 동안 에스퍼 기술 강화, 땅 위 포켓몬에게 오는 선공기를 막음",
              "5 turns: Psychic moves up, blocks priority moves on grounded Pokémon",
              "5ターン エスパーわざ強化、地面にいるポケモンへの先制わざを防ぐ",
              "5 turnos: más poder Psíquico, bloquea la prioridad contra Pokémon en el suelo",
              "5 tours : capacités Psy renforcées, bloque les capacités prioritaires au sol",
              "5 turnos: golpes Psíquicos mais fortes, bloqueia prioridade contra Pokémon no chão",
              "5 Runden: Psycho-Attacken stärker, blockt Erstschläge gegen Pokémon am Boden",
              "5 ходов: психические приёмы сильнее, без приоритетных приёмов по покемонам на земле")
        case 581:
            t("5턴 동안 드래곤 기술 반감, 땅 위 포켓몬은 상태이상에 걸리지 않음",
              "5 turns: halves Dragon moves, grounded Pokémon can't get a status",
              "5ターン ドラゴンわざ半減、地面にいるポケモンは状態異常にならない",
              "5 turnos: el tipo Dragón hace la mitad, sin problemas de estado en el suelo",
              "5 tours : capacités Dragon réduites de moitié, pas de statut au sol",
              "5 turnos: golpes de Dragão pela metade, sem status no chão",
              "5 Runden: Drachen-Attacken halbiert, keine Statusprobleme am Boden",
              "5 ходов: драконьи приёмы вдвое слабее, покемоны на земле без статусов")
        case 115:
            t("5턴 동안 물리 피해 반감", "Halves physical damage for 5 turns", "5ターン 物理ダメージ半減",
              "Reduce a la mitad el daño físico 5 turnos", "Divise par deux les dégâts physiques pendant 5 tours",
              "Corta o dano físico pela metade por 5 turnos", "Halbiert physischen Schaden 5 Runden lang",
              "Вдвое снижает физический урон на 5 ходов")
        case 113:
            t("5턴 동안 특수 피해 반감", "Halves special damage for 5 turns", "5ターン 特殊ダメージ半減",
              "Reduce a la mitad el daño especial 5 turnos", "Divise par deux les dégâts spéciaux pendant 5 tours",
              "Corta o dano especial pela metade por 5 turnos", "Halbiert Spezialschaden 5 Runden lang",
              "Вдвое снижает специальный урон на 5 ходов")
        case 694:
            t("설경·싸라기눈일 때 5턴 동안 모든 피해 반감", "In snow or hail, halves all damage for 5 turns",
              "ゆき・あられの時 5ターン ダメージ半減", "Con nieve o granizo, reduce a la mitad todo el daño 5 turnos",
              "Sous la neige ou la grêle, divise par deux tous les dégâts pendant 5 tours",
              "Com neve ou granizo, corta todo o dano pela metade por 5 turnos",
              "Bei Schnee oder Hagel halbiert allen Schaden 5 Runden lang",
              "В снег или град вдвое снижает весь урон на 5 ходов")
        case 191:
            t("교체해 나오는 상대에게 피해 (3번까지 쌓임)", "Foes that switch in take damage (stacks up to 3)",
              "交代で出てくる相手にダメージ（3回まで重なる）", "Los rivales que entran reciben daño (hasta 3 capas)",
              "Les adversaires qui entrent subissent des dégâts (jusqu'à 3 couches)",
              "Rivais que entram sofrem dano (até 3 camadas)", "Eingewechselte Gegner nehmen Schaden (bis zu 3 Lagen)",
              "Выходящие соперники получают урон (до 3 слоёв)")
        case 390:
            t("교체해 나오는 상대를 독 (2번 깔면 맹독)", "Foes that switch in get poisoned (badly with 2 layers)",
              "交代で出てくる相手をどくにする（2回でもうどく）", "Envenena a los rivales que entran (gravemente con 2 capas)",
              "Empoisonne les adversaires qui entrent (gravement avec 2 couches)",
              "Envenena rivais que entram (gravemente com 2 camadas)", "Vergiftet eingewechselte Gegner (schwer bei 2 Lagen)",
              "Отравляет выходящих соперников (сильно при 2 слоях)")
        case 564:
            t("교체해 나오는 상대의 스피드 1랭크 하락", "Foes that switch in lose 1 Speed stage",
              "交代で出てくる相手のすばやさ1段階ダウン", "Los rivales que entran bajan 1 nivel de Velocidad",
              "Les adversaires qui entrent perdent 1 niveau de Vitesse", "Rivais que entram perdem 1 estágio de Velocidade",
              "Eingewechselte Gegner verlieren 1 Initiative-Stufe", "Выходящие соперники теряют 1 ступень скорости")
        case 366:
            t("4턴 동안 우리 편 스피드 2배", "Doubles your side's Speed for 4 turns", "4ターン 味方のすばやさ2倍",
              "Duplica la Velocidad de tu lado 4 turnos", "Double la Vitesse de ton camp pendant 4 tours",
              "Dobra a Velocidade do seu lado por 4 turnos", "Verdoppelt die Initiative deiner Seite 4 Runden lang",
              "Удваивает скорость вашей стороны на 4 хода")
        case 219:
            t("5턴 동안 상대가 거는 상태이상을 막음", "Blocks status from foes for 5 turns", "5ターン 相手からの状態異常を防ぐ",
              "Bloquea problemas de estado del rival 5 turnos", "Bloque les statuts adverses pendant 5 tours",
              "Bloqueia status vindos do rival por 5 turnos", "Blockt Statusprobleme durch Gegner 5 Runden lang",
              "Защищает от статусов соперника на 5 ходов")
        case 54:
            t("5턴 동안 상대가 능력치를 낮추지 못함", "Foes can't lower your stats for 5 turns", "5ターン 相手に能力を下げられない",
              "Los rivales no pueden bajar tus características 5 turnos",
              "L'adversaire ne peut pas baisser tes stats pendant 5 tours",
              "Rivais não podem baixar seus atributos por 5 turnos",
              "Gegner können deine Werte 5 Runden lang nicht senken",
              "Соперник не может снижать ваши характеристики 5 ходов")
        case 381:
            t("5턴 동안 급소에 맞지 않음", "No critical hits against your side for 5 turns", "5ターン 急所に当たらない",
              "Sin golpes críticos contra tu lado 5 turnos", "Aucun coup critique contre ton camp pendant 5 tours",
              "Sem golpes críticos contra o seu lado por 5 turnos", "Keine Volltreffer gegen deine Seite 5 Runden lang",
              "По вашей стороне нет критических ударов 5 ходов")
        case 356:
            t("5턴 동안 모두 땅에 붙고 명중률 상승, 공중 기술 못 씀",
              "5 turns: everyone is grounded, accuracy up, no airborne moves",
              "5ターン 全員が地面に落ち命中率アップ、空中わざが使えない",
              "5 turnos: todos en el suelo, más precisión, sin movimientos aéreos",
              "5 tours : tout le monde au sol, précision accrue, pas de capacités aériennes",
              "5 turnos: todos no chão, precisão maior, sem golpes aéreos",
              "5 Runden: alle am Boden, höhere Genauigkeit, keine Flug-Attacken",
              "5 ходов: все на земле, точность выше, без воздушных приёмов")
        case 114:
            t("양쪽의 능력 변화를 모두 없앰", "Resets every stat change on both sides", "両方の能力変化をすべて元に戻す",
              "Anula todos los cambios de características de ambos lados",
              "Annule toutes les modifications de stats des deux camps",
              "Zera todas as mudanças de atributos dos dois lados", "Setzt alle Wertänderungen beider Seiten zurück",
              "Сбрасывает все изменения характеристик у обеих сторон")
        case 432:
            t("양쪽 함정, 상대의 벽과 필드를 걷어냄", "Clears hazards on both sides, the foe's screens and the terrain",
              "両方の設置わざと相手の壁、フィールドを消す", "Quita trampas de ambos lados, las barreras rivales y el campo",
              "Retire les pièges des deux camps, les protections adverses et le terrain",
              "Remove armadilhas dos dois lados, barreiras do rival e o campo",
              "Entfernt Fallen beider Seiten, gegnerische Schilde und das Feld",
              "Убирает ловушки обеих сторон, экраны соперника и поле")
        case 756:
            t("양쪽의 벽·순풍·함정을 맞바꿈", "Swaps screens, Tailwind and hazards between sides",
              "両方の壁・おいかぜ・設置わざを入れ替える", "Intercambia barreras, Viento Afín y trampas entre lados",
              "Échange protections, Vent Arrière et pièges entre les camps",
              "Troca barreiras, Vento a Favor e armadilhas entre os lados",
              "Tauscht Schilde, Rückenwind und Fallen zwischen den Seiten",
              "Меняет местами экраны, попутный ветер и ловушки сторон")
        case 882:
            t("양쪽 함정을 치우고 공격·스피드 1랭크 상승", "Clears hazards on both sides, Attack and Speed +1 stage",
              "両方の設置わざを片付け、こうげき・すばやさ1段階アップ", "Quita trampas de ambos lados, Ataque y Velocidad +1 nivel",
              "Retire les pièges des deux camps, Attaque et Vitesse +1 niveau",
              "Remove armadilhas dos dois lados, Ataque e Velocidade +1 estágio",
              "Entfernt Fallen beider Seiten, Angriff und Initiative +1 Stufe",
              "Убирает ловушки обеих сторон, атака и скорость +1 ступень")
        default: moreStatusMoveEffect(moveID)
        }
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
