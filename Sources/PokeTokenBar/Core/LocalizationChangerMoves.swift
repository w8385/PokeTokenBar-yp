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
        default: nil
        }
    }
}
