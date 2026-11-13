import Foundation

/// Text for the dex Evolution card: what the games ask for, and what this app asks for instead.
extension L {
    /// An item or move name from its PokéAPI slug: the official item name when known, else the slug in words.
    func evolutionSlugName(_ slug: String) -> String {
        if let official = ItemLore.officialName(slug, in: lang) ?? ItemLore.officialName(slug, in: .en) { return official }
        return slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    func evolutionTypeName(_ type: String) -> String {
        switch type {
        case "fairy": return t("페어리", "Fairy", "フェアリー", "Hada", "Fée", "Fada", "Fee", "Фея")
        case "dark": return t("악", "Dark", "あく", "Siniestro", "Ténèbres", "Sombrio", "Unlicht", "Тёмный")
        default: return type.capitalized
        }
    }

    func stoneNotReadyHint(_ pokemon: String) -> String {
        t("\(pokemon)에게 맞는 돌이지만 아직 조건이 남았어요. 도감의 진화 카드를 확인하세요. 돌은 그대로 남아 있어요.",
          "This fits \(pokemon), but its other conditions are not met yet. Check the Evolution card in the Pokédex. Your item is kept.",
          "\(pokemon)に合うアイテムですが、まだ条件が残っています。図鑑の進化カードを確認してください。アイテムはそのまま残ります。",
          "Sirve para \(pokemon), pero aún faltan condiciones. Mira la tarjeta de evolución en la Pokédex. Conservas el objeto.",
          "Convient à \(pokemon), mais d'autres conditions manquent encore. Voir la carte Évolution du Pokédex. Tu gardes l'objet.",
          "Serve para \(pokemon), mas ainda faltam condições. Veja o cartão de evolução na Pokédex. O item foi mantido.",
          "Passt zu \(pokemon), aber weitere Bedingungen fehlen noch. Siehe die Entwicklungskarte im Pokédex. Der Gegenstand bleibt erhalten.",
          "Подходит для \(pokemon), но остальные условия ещё не выполнены. Смотрите карточку эволюции в Покедексе. Предмет остался у вас.")
    }

    func evolutionPathText(_ path: [EvolutionRequirement], speciesName: (Int) -> String) -> String {
        path.map { evolutionRequirementText($0, speciesName: speciesName) }.joined(separator: " + ")
    }

    var evolutionBecomesThisForm: String {
        t("이 모습이 되는 조건", "How it becomes this form", "この姿になる条件", "Cómo llega a esta forma",
          "Comment atteindre cette forme", "Como chega a esta forma", "So wird es zu dieser Form",
          "Как достичь этой формы")
    }

    func evolutionNextStep(_ name: String) -> String {
        t("다음: \(name)", "Next: \(name)", "つぎ: \(name)", "Siguiente: \(name)", "Suivant : \(name)",
          "Próximo: \(name)", "Als Nächstes: \(name)", "Далее: \(name)")
    }

    var evolutionInGames: String {
        t("원작", "In the games", "原作", "En los juegos", "Dans les jeux", "Nos jogos", "In den Spielen", "В играх")
    }

    var evolutionInApp: String {
        t("이 앱", "In this app", "このアプリ", "En esta app", "Dans cette app", "Neste app", "In dieser App",
          "В этом приложении")
    }

    var evolutionOr: String {
        t("또는", "or", "または", "o", "ou", "ou", "oder", "или")
    }

    var evolutionTowerDarkness: String {
        t("악의 탑", "Tower of Darkness", "あくのとう", "Torre Oscura", "Tour Ténèbres", "Torre das Trevas",
          "Dunkelturm", "Башня Тьмы")
    }

    var evolutionTowerWaters: String {
        t("물의 탑", "Tower of Waters", "みずのとう", "Torre Agua", "Tour Eau", "Torre da Água", "Wasserturm",
          "Башня Воды")
    }

    func evolutionOriginalText(_ original: EvolutionOriginal, speciesName: (Int) -> String) -> String {
        switch original {
        case .happiness:
            return t("친밀도가 높은 상태로 레벨업", "Level up with high friendship", "なかよし度が高い状態でレベルアップ",
                     "Subir de nivel con mucha amistad", "Monter de niveau avec beaucoup d'affection",
                     "Subir de nível com muita amizade", "Mit hoher Freundschaft aufsteigen",
                     "Повысить уровень при высокой дружбе")
        case .affection(let n):
            return t("친밀 하트 \(n)개 이상으로 레벨업", "Level up with \(n) hearts of affection",
                     "なかよしハート\(n)個以上でレベルアップ", "Subir de nivel con \(n) corazones de cariño",
                     "Monter de niveau avec \(n) cœurs d'affection", "Subir de nível com \(n) corações de afeto",
                     "Mit \(n) Herzen Zuneigung aufsteigen", "Повысить уровень при \(n) сердечках привязанности")
        case .time(let period):
            switch period {
            case .day:
                return t("낮에 레벨업", "Level up during the day", "昼にレベルアップ", "Subir de nivel de día",
                         "Monter de niveau de jour", "Subir de nível de dia", "Tagsüber aufsteigen",
                         "Повысить уровень днём")
            case .night:
                return t("밤에 레벨업", "Level up at night", "夜にレベルアップ", "Subir de nivel de noche",
                         "Monter de niveau la nuit", "Subir de nível à noite", "Nachts aufsteigen",
                         "Повысить уровень ночью")
            }
        case .fullMoon:
            return t("보름달이 뜬 밤에 사용", "Use it on a full-moon night", "満月の夜に使う",
                     "Usar en una noche de luna llena", "À utiliser une nuit de pleine lune",
                     "Usar em uma noite de lua cheia", "In einer Vollmondnacht anwenden", "Применить в полнолуние")
        case .knownMove(let slug):
            let move = evolutionSlugName(slug)
            return t("\(move)을(를) 배운 채로 레벨업", "Level up while knowing \(move)", "\(move)を覚えた状態でレベルアップ",
                     "Subir de nivel conociendo \(move)", "Monter de niveau en connaissant \(move)",
                     "Subir de nível conhecendo \(move)", "Aufsteigen, während \(move) bekannt ist",
                     "Повысить уровень, зная \(move)")
        case .knownMoveType(let type):
            let name = evolutionTypeName(type)
            return t("\(name)타입 기술을 배운 채로 레벨업", "Level up knowing a \(name)-type move",
                     "\(name)タイプのわざを覚えた状態でレベルアップ",
                     "Subir de nivel conociendo un movimiento de tipo \(name)",
                     "Monter de niveau en connaissant une capacité de type \(name)",
                     "Subir de nível conhecendo um golpe do tipo \(name)",
                     "Aufsteigen, während eine \(name)-Attacke bekannt ist",
                     "Повысить уровень, зная приём типа «\(name)»")
        case .heldItem(let slug):
            let item = evolutionSlugName(slug)
            return t("\(item)을(를) 지닌 채로 레벨업", "Level up while holding \(item)", "\(item)を持たせてレベルアップ",
                     "Subir de nivel llevando \(item)", "Monter de niveau en tenant \(item)",
                     "Subir de nível segurando \(item)", "Aufsteigen, während \(item) getragen wird",
                     "Повысить уровень, держа \(item)")
        case .partySpecies(let id):
            let name = speciesName(id)
            return t("파티에 \(name)이(가) 있는 상태로 레벨업", "Level up with \(name) in the party",
                     "手持ちに\(name)がいる状態でレベルアップ", "Subir de nivel con \(name) en el equipo",
                     "Monter de niveau avec \(name) dans l'équipe", "Subir de nível com \(name) na equipe",
                     "Aufsteigen, mit \(name) im Team", "Повысить уровень, когда в команде есть \(name)")
        case .partyType(let type):
            let name = evolutionTypeName(type)
            return t("파티에 \(name)타입이 있는 상태로 레벨업", "Level up with a \(name)-type Pokémon in the party",
                     "手持ちに\(name)タイプがいる状態でレベルアップ",
                     "Subir de nivel con un Pokémon de tipo \(name) en el equipo",
                     "Monter de niveau avec un Pokémon de type \(name) dans l'équipe",
                     "Subir de nível com um Pokémon do tipo \(name) na equipe",
                     "Aufsteigen, mit einem \(name)-Pokémon im Team",
                     "Повысить уровень, когда в команде есть покемон типа «\(name)»")
        case .relativeStats(let sign):
            if sign > 0 {
                return t("레벨 20 이상에서 공격이 방어보다 높을 때 레벨업", "Level up from Lv.20 with Attack above Defense",
                         "Lv.20以上で、こうげきがぼうぎょより高いときレベルアップ",
                         "Subir de nivel desde el Nv. 20 con Ataque mayor que Defensa",
                         "Monter de niveau dès le N.20 avec Attaque supérieure à Défense",
                         "Subir de nível a partir do Nv. 20 com Ataque maior que Defesa",
                         "Ab Lv. 20 aufsteigen, wenn Angriff über Verteidigung liegt",
                         "С 20-го уровня, если Атака выше Защиты")
            } else if sign < 0 {
                return t("레벨 20 이상에서 방어가 공격보다 높을 때 레벨업", "Level up from Lv.20 with Defense above Attack",
                         "Lv.20以上で、ぼうぎょがこうげきより高いときレベルアップ",
                         "Subir de nivel desde el Nv. 20 con Defensa mayor que Ataque",
                         "Monter de niveau dès le N.20 avec Défense supérieure à Attaque",
                         "Subir de nível a partir do Nv. 20 com Defesa maior que Ataque",
                         "Ab Lv. 20 aufsteigen, wenn Verteidigung über Angriff liegt",
                         "С 20-го уровня, если Защита выше Атаки")
            }
            return t("레벨 20 이상에서 공격과 방어가 같을 때 레벨업", "Level up from Lv.20 with Attack equal to Defense",
                     "Lv.20以上で、こうげきとぼうぎょが同じときレベルアップ",
                     "Subir de nivel desde el Nv. 20 con Ataque igual a Defensa",
                     "Monter de niveau dès le N.20 avec Attaque égale à Défense",
                     "Subir de nível a partir do Nv. 20 com Ataque igual a Defesa",
                     "Ab Lv. 20 aufsteigen, wenn Angriff gleich Verteidigung ist",
                     "С 20-го уровня, если Атака равна Защите")
        case .beauty(_):
            return t("아름다움이 높은 상태로 레벨업", "Level up with high Beauty", "うつくしさが高い状態でレベルアップ",
                     "Subir de nivel con mucha belleza", "Monter de niveau avec beaucoup de beauté",
                     "Subir de nível com muita beleza", "Mit hoher Schönheit aufsteigen",
                     "Повысить уровень при высокой красоте")
        case .upsideDown:
            return t("본체를 뒤집은 채로 레벨업", "Level up while holding the console upside down",
                     "本体をさかさまにしてレベルアップ", "Subir de nivel con la consola boca abajo",
                     "Monter de niveau avec la console à l'envers",
                     "Subir de nível com o console de cabeça para baixo",
                     "Aufsteigen, während die Konsole auf dem Kopf steht", "Повысить уровень, перевернув консоль")
        case .rain:
            return t("비가 내리는 동안 레벨업", "Level up while it is raining", "雨が降っている間にレベルアップ",
                     "Subir de nivel mientras llueve", "Monter de niveau sous la pluie",
                     "Subir de nível enquanto chove", "Bei Regen aufsteigen", "Повысить уровень во время дождя")
        case .steps(let n):
            return t("맨 앞에 두고 \(n)걸음 걸은 뒤 레벨업", "Level up after walking \(n) steps with it in the lead",
                     "先頭にして\(n)歩あるいたあとレベルアップ", "Subir de nivel tras caminar \(n) pasos con él al frente",
                     "Monter de niveau après \(n) pas en tête d'équipe",
                     "Subir de nível após caminhar \(n) passos com ele na frente",
                     "Nach \(n) Schritten an der Spitze aufsteigen",
                     "Повысить уровень после \(n) шагов впереди команды")
        case .multiplayer:
            return t("유니온 서클(여럿이 함께 플레이) 중 레벨업", "Level up while playing together (Union Circle)",
                     "ユニオンサークルでみんなと遊んでいる間にレベルアップ",
                     "Subir de nivel jugando en grupo (Círculo Unión)",
                     "Monter de niveau en jouant à plusieurs (Cercle Union)",
                     "Subir de nível jogando em grupo (Círculo União)",
                     "Aufsteigen beim Spielen mit anderen (Union-Kreis)",
                     "Повысить уровень, играя вместе с другими (Круг союза)")
        case .criticalHits(let n):
            return t("한 번의 배틀에서 급소를 \(n)번 맞힌 뒤 레벨업", "Land \(n) critical hits in one battle, then level up",
                     "1回のバトルで急所に\(n)回当てたあとレベルアップ",
                     "Asestar \(n) golpes críticos en un combate y subir de nivel",
                     "Infliger \(n) coups critiques en un combat, puis monter de niveau",
                     "Acertar \(n) golpes críticos em uma batalha e subir de nível",
                     "In einem Kampf \(n) Volltreffer landen, dann aufsteigen",
                     "Нанести \(n) критических ударов за бой и повысить уровень")
        case .damageTaken(let n):
            return t("배틀에서 \(n) 이상의 대미지를 받은 뒤 레벨업", "Take at least \(n) damage in battle, then level up",
                     "バトルで\(n)以上のダメージを受けたあとレベルアップ",
                     "Recibir al menos \(n) de daño en combate y subir de nivel",
                     "Subir au moins \(n) dégâts en combat, puis monter de niveau",
                     "Sofrer pelo menos \(n) de dano em batalha e subir de nível",
                     "Im Kampf mindestens \(n) Schaden nehmen, dann aufsteigen",
                     "Получить не менее \(n) урона в бою и повысить уровень")
        case .recoil(let n):
            return t("반동 대미지를 \(n) 이상 입은 뒤 레벨업", "Take at least \(n) recoil damage, then level up",
                     "反動ダメージを\(n)以上受けたあとレベルアップ",
                     "Recibir al menos \(n) de daño por retroceso y subir de nivel",
                     "Subir au moins \(n) dégâts de recul, puis monter de niveau",
                     "Sofrer pelo menos \(n) de dano de recuo e subir de nível",
                     "Mindestens \(n) Rückstoßschaden nehmen, dann aufsteigen",
                     "Получить не менее \(n) урона от отдачи и повысить уровень")
        case .moveUses(let slug, let n):
            let move = evolutionSlugName(slug)
            return t("\(move)을(를) \(n)번 쓴 뒤 레벨업", "Use \(move) \(n) times, then level up",
                     "\(move)を\(n)回使ったあとレベルアップ", "Usar \(move) \(n) veces y subir de nivel",
                     "Utiliser \(move) \(n) fois, puis monter de niveau", "Usar \(move) \(n) vezes e subir de nível",
                     "\(move) \(n)-mal einsetzen, dann aufsteigen", "Использовать \(move) \(n) раз и повысить уровень")
        case .defeatedBisharp(let n):
            let boss = speciesName(625)
            return t("무리를 이끄는 \(boss)을(를) \(n)마리 쓰러뜨린 뒤 레벨업",
                     "Defeat \(n) group-leading \(boss), then level up",
                     "むれを率いる\(boss)を\(n)匹たおしたあとレベルアップ",
                     "Derrotar a \(n) \(boss) líderes de grupo y subir de nivel",
                     "Vaincre \(n) \(boss) chefs de groupe, puis monter de niveau",
                     "Derrotar \(n) \(boss) líderes de grupo e subir de nível",
                     "\(n) anführende \(boss) besiegen, dann aufsteigen",
                     "Победить \(n) предводителей группы (\(boss)) и повысить уровень")
        case .coins(let n):
            return t("코인을 \(n)개 모은 뒤 레벨업", "Collect \(n) coins, then level up",
                     "コインを\(n)枚あつめたあとレベルアップ", "Reunir \(n) monedas y subir de nivel",
                     "Rassembler \(n) pièces, puis monter de niveau", "Juntar \(n) moedas e subir de nível",
                     "\(n) Münzen sammeln, dann aufsteigen", "Собрать \(n) монет и повысить уровень")
        case .candies(let n):
            return t("사탕을 \(n)개 먹인 뒤 진화", "Feed it \(n) candies", "アメを\(n)個あげると進化",
                     "Darle \(n) caramelos", "Lui donner \(n) bonbons", "Dar \(n) doces", "\(n) Bonbons verfüttern",
                     "Скормить \(n) конфет")
        case .tower:
            return t("악의 탑 또는 물의 탑을 돌파", "Clear the Tower of Darkness or the Tower of Waters",
                     "あくのとう　または　みずのとうを　クリア", "Superar la Torre Oscura o la Torre Agua",
                     "Réussir la Tour Ténèbres ou la Tour Eau", "Concluir a Torre das Trevas ou a Torre da Água",
                     "Den Dunkelturm oder den Wasserturm abschließen", "Пройти Башню Тьмы или Башню Воды")
        case .spinWithSweet:
            return t("단것을 지니게 하고 빙글빙글 돌리기", "Hold a sweet and spin around", "あまいものを持たせてくるくる回す",
                     "Llevar un dulce y girar", "Tenir une sucrerie et tourner sur soi-même",
                     "Segurar um doce e girar", "Eine Süßigkeit tragen und sich drehen",
                     "Держать сладость и покрутиться")
        case .random:
            return t("무작위(개체마다 정해짐)", "Random (set per individual)", "ランダム(個体ごとに決まる)",
                     "Aleatorio (según el individuo)", "Aléatoire (selon l'individu)",
                     "Aleatório (definido por indivíduo)", "Zufall (je nach Individuum)",
                     "Случайно (зависит от особи)")
        case .nature:
            return t("성격에 따라 모습이 갈린다", "The form depends on its nature", "せいかくで姿が決まる",
                     "La forma depende de su naturaleza", "La forme dépend de son caractère",
                     "A forma depende da natureza", "Die Form hängt vom Wesen ab", "Форма зависит от характера")
        case .shed:
            return t("파티에 빈자리와 몬스터볼이 있으면 한 마리가 더 나타난다",
                     "With a free party slot and a spare Poké Ball, a second Pokémon appears",
                     "手持ちに空きとモンスターボールがあると、もう1匹あらわれる",
                     "Con un hueco en el equipo y una Poké Ball, aparece un segundo Pokémon",
                     "Avec une place libre et une Poké Ball, un second Pokémon apparaît",
                     "Com espaço na equipe e uma Poké Bola, surge um segundo Pokémon",
                     "Mit freiem Platz und einem Pokéball erscheint ein zweites Pokémon",
                     "При свободном месте и Покеболе появляется второй покемон")
        case .useItem(let slug):
            let item = evolutionSlugName(slug)
            return t("\(item)을(를) 사용", "Use \(item)", "\(item)を使う", "Usar \(item)", "Utiliser \(item)",
                     "Usar \(item)", "\(item) verwenden", "Применить \(item)")
        }
    }

    func evolutionRequirementText(_ requirement: EvolutionRequirement, speciesName: (Int) -> String) -> String {
        switch requirement {
        case .pets(let n):
            return t("쓰다듬기 \(n)번", "Pet it \(n) times", "\(n)回なでる", "Acariciarlo \(n) veces",
                     "Le caresser \(n) fois", "Fazer carinho \(n) vezes", "\(n)-mal streicheln", "Погладить \(n) раз")
        case .time(let period):
            switch period {
            case .day: return t("낮에", "During the day", "昼に", "De día", "De jour", "De dia", "Tagsüber", "Днём")
            case .night: return t("밤에", "At night", "夜に", "De noche", "La nuit", "À noite", "Nachts", "Ночью")
            }
        case .knownMove(let slug, _):
            let move = evolutionSlugName(slug)
            return t("\(move) 습득", "Know \(move)", "\(move)を覚えている", "Conocer \(move)", "Connaître \(move)",
                     "Conhecer \(move)", "\(move) können", "Знать \(move)")
        case .knownFairyMove:
            return t("페어리타입 기술 습득", "Know a Fairy-type move", "フェアリータイプのわざを覚えている",
                     "Conocer un movimiento de tipo Hada", "Connaître une capacité de type Fée",
                     "Conhecer um golpe do tipo Fada", "Eine Fee-Attacke können", "Знать приём типа «Фея»")
        case .holds(let kind):
            let item = itemName(kind)
            return t("\(item) 장착", "Hold \(item)", "\(item)を持たせる", "Llevar \(item)", "Tenir \(item)",
                     "Segurar \(item)", "\(item) tragen", "Держать \(item)")
        case .bag(let kind):
            let item = itemName(kind)
            return t("\(item) 사용", "Use \(item)", "\(item)を使う", "Usar \(item)", "Utiliser \(item)",
                     "Usar \(item)", "\(item) verwenden", "Применить \(item)")
        case .friendLine(let id):
            let name = speciesName(id)
            return t("\(name) 계열을 친구로 두기", "Have \(name) as a friend", "\(name)をともだちにする",
                     "Tener a \(name) como amigo", "Avoir \(name) comme ami", "Ter \(name) como amigo",
                     "\(name) als Freund haben", "Иметь \(name) в друзьях")
        case .friendType(let type):
            let name = evolutionTypeName(type)
            return t("\(name)타입 친구 두기", "Have a \(name)-type friend", "\(name)タイプのともだちを持つ",
                     "Tener un amigo de tipo \(name)", "Avoir un ami de type \(name)",
                     "Ter um amigo do tipo \(name)", "Einen \(name)-Freund haben", "Иметь друга типа «\(name)»")
        case .anyFriend:
            return t("친구 한 마리 두기", "Have a friend", "ともだちを1匹持つ", "Tener un amigo", "Avoir un ami",
                     "Ter um amigo", "Einen Freund haben", "Иметь друга")
        case .flipped:
            return t("홈 화면 스프라이트를 우클릭해 뒤집기", "Turn the Home sprite upside down (right-click it)",
                     "ホームのスプライトを右クリックでさかさまにする",
                     "Poner boca abajo el sprite de Inicio (clic derecho)",
                     "Retourner le sprite de l'accueil (clic droit)",
                     "Virar o sprite da tela inicial de cabeça para baixo (clique direito)",
                     "Das Home-Sprite auf den Kopf stellen (Rechtsklick)",
                     "Перевернуть спрайт на главной (правый клик)")
        case .spun:
            return t("홈 화면 스프라이트를 우클릭해 돌리기", "Spin the Home sprite (right-click it)",
                     "ホームのスプライトを右クリックで回す", "Hacer girar el sprite de Inicio (clic derecho)",
                     "Faire tourner le sprite de l'accueil (clic droit)",
                     "Girar o sprite da tela inicial (clique direito)", "Das Home-Sprite drehen (Rechtsklick)",
                     "Покрутить спрайт на главной (правый клик)")
        case .tokenRain:
            return t("토큰 소모 속도가 최고 단계에 이르기", "Reach the top token burn rate",
                     "トークン消費が最高ペースになる", "Alcanzar el ritmo máximo de consumo de tokens",
                     "Atteindre le rythme maximal de consommation de tokens",
                     "Atingir o ritmo máximo de consumo de tokens", "Die höchste Token-Verbrauchsrate erreichen",
                     "Достичь максимальной скорости расхода токенов")
        case .longStage(let percent):
            return t("성장 게이지를 \(percent)%까지 채우기", "Fill the growth bar to \(percent)%",
                     "せいちょうゲージを\(percent)%まで貯める", "Llenar la barra de crecimiento al \(percent)%",
                     "Remplir la barre de croissance à \(percent) %", "Encher a barra de crescimento até \(percent)%",
                     "Wachstumsleiste auf \(percent) % füllen", "Заполнить шкалу роста до \(percent)%")
        case .battles(let tally, let n):
            switch tally {
            case .won:
                return t("배틀 \(n)번 승리", "Win \(n) battles", "バトルに\(n)回勝つ", "Ganar \(n) combates",
                         "Gagner \(n) combats", "Vencer \(n) batalhas", "\(n) Kämpfe gewinnen", "Выиграть \(n) боёв")
            case .lost:
                return t("배틀 \(n)번 패배", "Lose \(n) battles", "バトルに\(n)回負ける", "Perder \(n) combates",
                         "Perdre \(n) combats", "Perder \(n) batalhas", "\(n) Kämpfe verlieren", "Проиграть \(n) боёв")
            case .played:
                return t("배틀 \(n)번 참가", "Fight \(n) battles", "バトルを\(n)回する", "Disputar \(n) combates",
                         "Livrer \(n) combats", "Disputar \(n) batalhas", "\(n) Kämpfe bestreiten",
                         "Провести \(n) боёв")
            }
        case .towerChosen:
            return t("탑 고르기", "Choose a tower", "とうをえらぶ", "Elegir una torre", "Choisir une tour",
                     "Escolher uma torre", "Einen Turm wählen", "Выбрать башню")
        case .spent(let n):
            let amount = TokenFormatter.compact(n)
            return t("상점에서 토큰 \(amount) 쓰기", "Spend \(amount) tokens in the shop", "ショップでトークンを\(amount)使う",
                     "Gastar \(amount) tokens en la tienda", "Dépenser \(amount) tokens à la boutique",
                     "Gastar \(amount) tokens na loja", "\(amount) Tokens im Shop ausgeben",
                     "Потратить \(amount) токенов в магазине")
        case .candies(let n):
            let name = itemName(.rareCandy)
            return t("\(name) \(n)개 사용", "Use \(n) \(name)", "\(name)を\(n)個使う", "Usar \(n) \(name)",
                     "Utiliser \(n) \(name)", "Usar \(n) \(name)", "\(n) \(name) verwenden",
                     "Использовать \(name): \(n)")
        }
    }

    func evolutionSelectorText(_ selector: EvolutionSelector) -> String {
        switch selector {
        case .attackAbove, .defenseAbove, .attackEqualsDefense:
            return t("레벨 20 기준 공격·방어 능력치(개체값·성격)로 정해져요",
                     "Settled by Attack and Defense at Lv.20 (IVs and nature)",
                     "Lv.20のこうげき・ぼうぎょ(個体値・せいかく)で決まります",
                     "Se decide por el Ataque y la Defensa a Nv. 20 (IV y naturaleza)",
                     "Décidé par l'Attaque et la Défense au N.20 (IV et caractère)",
                     "Definido por Ataque e Defesa no Nv. 20 (IVs e natureza)",
                     "Entschieden durch Angriff und Verteidigung auf Lv. 20 (IVs und Wesen)",
                     "Определяется Атакой и Защитой на 20-м уровне (IV и характер)")
        case .seedEven, .seedOdd:
            return t("개체마다 정해져요(절반씩)", "Settled per individual (half take each form)",
                     "個体ごとに決まります(半々)", "Se decide por individuo (mitad y mitad)",
                     "Décidé par individu (moitié-moitié)", "Definido por indivíduo (metade cada)",
                     "Je nach Individuum entschieden (je zur Hälfte)", "Определяется особью (поровну)")
        case .never:
            return t("앞 단계가 진화할 때 함께 나타나요", "Appears alongside the other evolution, when the earlier form evolves",
                     "前の姿が進化するときに一緒にあらわれます",
                     "Aparece junto a la otra evolución, cuando evoluciona la forma anterior",
                     "Apparaît avec l'autre évolution, quand la forme précédente évolue",
                     "Surge junto da outra evolução, quando a forma anterior evolui",
                     "Erscheint zusammen mit der anderen Entwicklung, wenn die Vorstufe sich entwickelt",
                     "Появляется вместе с другой эволюцией, когда эволюционирует предыдущая форма")
        }
    }
}
