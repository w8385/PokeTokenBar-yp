import Foundation

extension L {
    func changerMoveEffect(_ moveID: Int) -> String? {
        switch moveID {
        case 160:
            t("자신의 타입을 첫 번째 기술의 타입으로 바꿈", "Changes its type to its first move's type",
              "自分のタイプを 1番目の技のタイプにする", "Cambia su tipo al de su primer movimiento",
              "Prend le type de sa première capacité", "Muda seu tipo para o do seu primeiro golpe",
              "Nimmt den Typ seiner ersten Attacke an", "Меняет свой тип на тип первого приёма")
        case 176:
            t("상대가 마지막에 쓴 기술을 반감하는 타입으로 바뀜",
              "Changes its type to one that resists the target's last move",
              "相手が最後に使った技を いまひとつにするタイプになる",
              "Cambia a un tipo que resiste el último movimiento del objetivo",
              "Prend un type qui résiste à la dernière capacité de la cible",
              "Muda para um tipo que resiste ao último golpe do alvo",
              "Nimmt einen Typ an, der der letzten Attacke des Ziels widersteht",
              "Принимает тип, устойчивый к последнему приёму цели")
        case 293:
            t("필드 타입으로 바뀜 (필드가 없으면 노말)", "Changes its type to match the terrain (Normal without one)",
              "フィールドに合わせたタイプになる (なければノーマル)",
              "Cambia su tipo según el campo (Normal si no hay)",
              "Prend le type du terrain (Normal sans terrain)",
              "Muda seu tipo conforme o campo (Normal sem campo)",
              "Nimmt den Typ des Feldes an (ohne Feld Normal)",
              "Принимает тип поля (без поля — Нормальный)")
        case 513:
            t("상대와 같은 타입이 됨", "Copies the target's types", "相手と同じタイプになる",
              "Copia los tipos del objetivo", "Copie les types de la cible", "Copia os tipos do alvo",
              "Kopiert die Typen des Ziels", "Копирует типы цели")
        case 487:
            t("상대를 물 단일 타입으로 바꿈", "Makes the target a pure Water type", "相手を みず単タイプにする",
              "Convierte al objetivo en tipo Agua puro", "Rend la cible de type Eau pur",
              "Torna o alvo do tipo Água puro", "Macht das Ziel zu einem reinen Wasser-Pokémon",
              "Делает цель чисто Водным типом")
        case 750:
            t("상대를 에스퍼 단일 타입으로 바꿈", "Makes the target a pure Psychic type", "相手を エスパー単タイプにする",
              "Convierte al objetivo en tipo Psíquico puro", "Rend la cible de type Psy pur",
              "Torna o alvo do tipo Psíquico puro", "Macht das Ziel zu einem reinen Psycho-Pokémon",
              "Делает цель чисто Психическим типом")
        case 567:
            t("상대에게 고스트 타입을 더함", "Adds the Ghost type to the target", "相手に ゴーストタイプを追加",
              "Añade el tipo Fantasma al objetivo", "Ajoute le type Spectre à la cible",
              "Adiciona o tipo Fantasma ao alvo", "Fügt dem Ziel den Typ Geist hinzu",
              "Добавляет цели Призрачный тип")
        case 571:
            t("상대에게 풀 타입을 더함", "Adds the Grass type to the target", "相手に くさタイプを追加",
              "Añade el tipo Planta al objetivo", "Ajoute le type Plante à la cible",
              "Adiciona o tipo Planta ao alvo", "Fügt dem Ziel den Typ Pflanze hinzu",
              "Добавляет цели Травяной тип")
        case 272, 867:
            t("상대의 특성을 복사함", "Copies the target's Ability", "相手の とくせいをコピーする",
              "Copia la habilidad del objetivo", "Copie le talent de la cible", "Copia a habilidade do alvo",
              "Kopiert die Fähigkeit des Ziels", "Копирует способность цели")
        case 285:
            t("상대와 특성을 맞바꿈", "Swaps Abilities with the target", "相手と とくせいを入れ替える",
              "Intercambia habilidades con el objetivo", "Échange son talent avec la cible",
              "Troca de habilidade com o alvo", "Tauscht die Fähigkeit mit dem Ziel",
              "Меняется способностями с целью")
        case 494:
            t("상대의 특성을 자신의 특성으로 바꿈", "Gives the target its own Ability", "相手の とくせいを自分と同じにする",
              "Da su habilidad al objetivo", "Donne son talent à la cible", "Dá sua habilidade ao alvo",
              "Gibt dem Ziel die eigene Fähigkeit", "Передаёт цели свою способность")
        case 493:
            t("상대의 특성을 단순으로 바꿈", "Changes the target's Ability to Simple", "相手の とくせいを たんじゅんにする",
              "Cambia la habilidad del objetivo a Simple", "Change le talent de la cible en Simple",
              "Muda a habilidade do alvo para Simple", "Ändert die Fähigkeit des Ziels zu Wankelmut",
              "Меняет способность цели на Простоту")
        case 388:
            t("상대의 특성을 불면으로 바꿈 (잠들어 있으면 깨어남)",
              "Changes the target's Ability to Insomnia (a sleeping target wakes up)",
              "相手の とくせいを ふみんにする (ねむっていれば目を覚ます)",
              "Cambia la habilidad del objetivo a Insomnio (si duerme, despierta)",
              "Change le talent de la cible en Insomnia (une cible endormie se réveille)",
              "Muda a habilidade do alvo para Insônia (um alvo adormecido acorda)",
              "Ändert die Fähigkeit des Ziels zu Insomnia (ein schlafendes Ziel wacht auf)",
              "Меняет способность цели на Бессонницу (спящая цель просыпается)")
        case 380:
            t("교체될 때까지 상대의 특성을 없앰", "Suppresses the target's Ability until it switches out",
              "交代するまで 相手の とくせいを消す", "Anula la habilidad del objetivo hasta que se retire",
              "Neutralise le talent de la cible jusqu'à son retrait",
              "Anula a habilidade do alvo até ele sair", "Unterdrückt die Fähigkeit des Ziels bis zum Austausch",
              "Подавляет способность цели до её замены")
        case 271, 415:
            t("상대와 지닌 도구를 맞바꿈", "Swaps held items with the target", "相手と 持ち物を入れ替える",
              "Intercambia los objetos equipados con el objetivo", "Échange les objets tenus avec la cible",
              "Troca os itens segurados com o alvo", "Tauscht die getragenen Items mit dem Ziel",
              "Меняется предметами с целью")
        case 516:
            t("빈손인 상대에게 지닌 도구를 건넴 (대타출동을 통과)",
              "Gives its held item to a target holding none (passes a Substitute)",
              "持ち物のない相手に 自分の持ち物を渡す (みがわりを無視)",
              "Da su objeto a un objetivo sin objeto (ignora Sustituto)",
              "Donne son objet à une cible qui n'en tient pas (ignore Clonage)",
              "Dá seu item a um alvo sem item (ignora Substituto)",
              "Gibt sein Item einem Ziel ohne Item (ignoriert Delegator)",
              "Отдаёт свой предмет цели без предмета (проходит сквозь Замену)")
        case 278:
            t("다 쓴 도구를 되살림 (빼앗기거나 건넨 도구는 제외)",
              "Restores the item it used up (not one taken or given away)",
              "使った持ち物を元に戻す (奪われたり渡した持ち物は除く)",
              "Recupera el objeto que gastó (no uno quitado o dado)",
              "Récupère l'objet qu'il a utilisé (pas un objet perdu ou donné)",
              "Recupera o item que usou (não um tirado ou dado)",
              "Holt sein verbrauchtes Item zurück (kein geraubtes oder abgegebenes)",
              "Возвращает израсходованный предмет (не отнятый и не отданный)")
        case 810:
            t("상대가 지닌 도구를 녹여 없앰", "Melts away the target's held item", "相手の持ち物を溶かして なくす",
              "Derrite el objeto del objetivo", "Fait fondre l'objet tenu par la cible",
              "Derrete o item segurado pelo alvo", "Löst das getragene Item des Ziels auf",
              "Растворяет предмет цели")
        case 752:
            t("양쪽 모두 지닌 나무열매를 바로 먹음", "Every Pokémon eats its held Berry at once",
              "全員が 持っているきのみを すぐに食べる", "Todos los Pokémon se comen su baya al instante",
              "Tous les Pokémon mangent aussitôt leur Baie", "Todos os Pokémon comem sua fruta na hora",
              "Alle Pokémon essen sofort ihre Beere", "Все покемоны сразу съедают свои ягоды")
        case 747:
            t("지닌 나무열매를 먹고 방어 2랭크 상승", "Eats its held Berry, then raises Defense by 2 stages",
              "持っているきのみを食べ 防御2段階アップ", "Se come su baya y sube 2 niveles su Defensa",
              "Mange sa Baie et augmente de 2 niveaux sa Défense", "Come sua fruta e aumenta 2 estágios a Defesa",
              "Isst seine Beere und erhöht die Verteidigung um 2 Stufen",
              "Съедает свою ягоду и повышает Защиту на 2 ступени")
        case 478:
            t("5턴 동안 모든 도구가 효과를 잃음 (다시 쓰면 풀림)", "Held items do nothing for 5 turns (using it again ends it)",
              "5ターン 全員の持ち物が効果を失う (もう一度使うと解除)",
              "Los objetos no tienen efecto durante 5 turnos (usarlo otra vez lo termina)",
              "Les objets tenus n'ont aucun effet pendant 5 tours (le relancer y met fin)",
              "Os itens não têm efeito por 5 turnos (usar de novo encerra)",
              "Getragene Items wirken 5 Runden lang nicht (erneuter Einsatz beendet es)",
              "Предметы не действуют 5 ходов (повторное применение отменяет)")
        case 472:
            t("5턴 동안 모두의 방어와 특방이 뒤바뀜 (다시 쓰면 풀림)",
              "Swaps everyone's Defense and Sp. Def for 5 turns (using it again ends it)",
              "5ターン 全員の防御と特防が入れ替わる (もう一度使うと解除)",
              "Intercambia la Defensa y la Def. Esp. de todos durante 5 turnos (usarlo otra vez lo termina)",
              "Échange la Défense et la Déf. Spé. de tous pendant 5 tours (le relancer y met fin)",
              "Troca a Defesa e a Def. Esp. de todos por 5 turnos (usar de novo encerra)",
              "Tauscht 5 Runden lang Verteidigung und Spezial-Verteidigung aller (erneuter Einsatz beendet es)",
              "Меняет местами Защиту и Особую защиту у всех на 5 ходов (повторное применение отменяет)")
        case 100:
            t("물러나고 다음 포켓몬이 나옴 (가장 늦게 씀)", "Switches out for the next Pokémon (moves last)",
              "引っ込んで 次のポケモンが出る (最後に出す)", "Se retira y sale el siguiente Pokémon (actúa el último)",
              "Se retire pour le Pokémon suivant (agit en dernier)",
              "Sai e entra o próximo Pokémon (age por último)",
              "Wird gegen das nächste Pokémon ausgetauscht (handelt zuletzt)",
              "Уходит, выходит следующий покемон (действует последним)")
        case 226:
            t("물러나며 능력 변화·대타출동을 다음 포켓몬에게 넘김",
              "Switches out and passes its stat changes and Substitute to the next Pokémon",
              "引っ込んで 能力変化と みがわりを 次のポケモンに引き継ぐ",
              "Se retira y pasa sus cambios de características y Sustituto al siguiente Pokémon",
              "Se retire et transmet ses changements de stats et son Clonage au Pokémon suivant",
              "Sai e passa as mudanças de atributos e o Substituto ao próximo Pokémon",
              "Wird ausgetauscht und gibt Statuswertänderungen und Delegator an das nächste Pokémon weiter",
              "Уходит и передаёт изменения характеристик и Замену следующему покемону")
        case 575:
            t("상대의 공격·특공을 1랭크 내리고 물러남", "Lowers the target's Attack and Sp. Atk by 1 stage, then switches out",
              "相手の攻撃と特攻を1段階下げて 引っ込む",
              "Baja 1 nivel el Ataque y el Ataque Esp. del objetivo y se retira",
              "Baisse d'un niveau l'Attaque et l'Atq. Spé. de la cible, puis se retire",
              "Diminui 1 estágio o Ataque e o Atq. Esp. do alvo e sai",
              "Senkt Angriff und Spezial-Angriff des Ziels um 1 Stufe und wird ausgetauscht",
              "Понижает Атаку и Особую атаку цели на 1 ступень и уходит")
        case 881:
            t("5턴 동안 눈을 내리게 하고 물러남", "Starts snow for 5 turns, then switches out",
              "5ターン 雪を降らせて 引っ込む", "Hace nevar durante 5 turnos y se retira",
              "Fait tomber la neige pendant 5 tours, puis se retire",
              "Faz nevar por 5 turnos e sai", "Lässt 5 Runden lang Schnee fallen und wird ausgetauscht",
              "Вызывает снег на 5 ходов и уходит")
        default: nil
        }
    }
}
