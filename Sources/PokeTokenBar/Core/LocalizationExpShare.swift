import Foundation

extension L {
    var expShareAttach: String {
        t("달기", "Attach", "つける", "Poner", "Attacher", "Colocar", "Anbringen", "Прикрепить")
    }

    var expShareDetach: String {
        t("떼기", "Detach", "はずす", "Quitar", "Retirer", "Remover", "Abnehmen", "Снять")
    }

    var expShareHolding: String {
        let p = ExpShare.sharePercent
        return t("지금 키우는 포켓몬이나 알이 얻는 경험치의 \(p)%를 함께 받아요.",
                 "Gets \(p)% of the EXP your current Pokémon or egg earns.",
                 "いま育てているポケモンかタマゴが得る経験値の\(p)%をもらえます。",
                 "Recibe el \(p) % de la EXP que gana tu Pokémon actual o tu huevo.",
                 "Reçoit \(p) % de l'EXP gagnée par ton Pokémon actuel ou ton œuf.",
                 "Recebe \(p)% da EXP que o seu Pokémon atual ou ovo ganha.",
                 "Erhält \(p) % der EP, die dein aktuelles Pokémon oder Ei bekommt.",
                 "Получает \(p)% опыта, который зарабатывает текущий покемон или яйцо.")
    }

    var expShareStoredNote: String {
        t("보관 중에도 경험치가 쌓이고, 저절로 열리는 진화는 박스에서 해요. 도구·쓰다듬기·배틀이 필요한 진화는 다시 키울 때 해요.",
          "It banks EXP in the Box and takes any evolution that opens by itself. Steps that need an item, pets or battles wait until you raise it again.",
          "預けている間も経験値がたまり、ひとりでに開く進化はボックスでします。道具・なでる・バトルが必要な進化はまた育てるときにします。",
          "Acumula EXP en la Caja y evoluciona allí cuando la evolución se abre sola. Las que necesitan un objeto, caricias o combates esperan a que vuelvas a criarlo.",
          "Il accumule de l'EXP dans la Boîte et y évolue quand l'évolution s'ouvre toute seule. Celles qui demandent un objet, des caresses ou des combats attendent que tu le reprennes.",
          "Acumula EXP na Caixa e evolui lá quando a evolução se abre sozinha. As que precisam de item, carinho ou batalhas esperam até você voltar a criá-lo.",
          "Es sammelt EP in der Box und entwickelt sich dort, wenn sich die Entwicklung von selbst öffnet. Schritte mit Item, Streicheln oder Kämpfen warten, bis du es wieder aufziehst.",
          "В Коробке он копит опыт и эволюционирует там, если эволюция открывается сама. Шаги, которым нужен предмет, поглаживания или бои, ждут, пока вы снова начнёте его растить.")
    }

    var expShareMoveHere: String {
        t("여기로 옮기기", "Move here", "ここに移す", "Mover aquí", "Déplacer ici", "Mover para cá", "Hierher verschieben", "Перенести сюда")
    }

    var expShareMoveTitle: String {
        t("학습장치를 가져올 포켓몬", "Take the Exp. Share from", "がくしゅうそうちを移すポケモン",
          "Quitarle el Repartir Exp a", "Prendre le Multi Exp de", "Pegar o Compart. Exp. de",
          "EP-Teiler nehmen von", "Забрать Общий опыт у")
    }

    var expShareIdleWhileRaised: String {
        t("키우거나 쉬는 동안은 나눠 받지 않아요.",
          "It gets no share while it is being raised or resting.",
          "育成中や休み中は分けてもらえません。",
          "No recibe su parte mientras se cría o descansa.",
          "Il ne reçoit rien pendant qu'il est élevé ou au repos.",
          "Não recebe a parte enquanto é criado ou descansa.",
          "Während es aufgezogen wird oder ruht, bekommt es nichts ab.",
          "Пока его растят или он отдыхает, доля ему не идёт.")
    }

    var expShareGoesWithEggSwap: String {
        t("가방의 학습장치 하나를 박스로 가는 포켓몬에 달아 줘요.",
          "One Exp. Share from your bag goes on the Pokémon heading to the Box.",
          "バッグのがくしゅうそうちを1つ、ボックスに行くポケモンにつけます。",
          "Uno de los Repartir Exp de tu mochila se le pone al Pokémon que va a la Caja.",
          "Un Multi Exp de ton sac est attaché au Pokémon qui part dans la Boîte.",
          "Um Compart. Exp. da mochila é colocado no Pokémon que vai para a Caixa.",
          "Ein EP-Teiler aus deinem Beutel kommt an das Pokémon, das in die Box geht.",
          "Один Общий опыт из сумки прикрепится к покемону, который уходит в Коробку.")
    }

    var expShareNoneInBag: String {
        t("가방에 남은 학습장치가 없어요. 다른 포켓몬의 학습장치를 여기로 옮길 수 있어요.",
          "No Exp. Share left in your bag. Move one here from another Pokémon.",
          "バッグにがくしゅうそうちが残っていません。ほかのポケモンのものをここに移せます。",
          "No te queda ningún Repartir Exp en la mochila. Puedes moverle aquí el de otro Pokémon.",
          "Plus aucun Multi Exp dans le sac. Tu peux déplacer ici celui d'un autre Pokémon.",
          "Nenhum Compart. Exp. sobrando na mochila. Você pode mover para cá o de outro Pokémon.",
          "Kein EP-Teiler mehr im Beutel. Du kannst den eines anderen Pokémon hierher verschieben.",
          "В сумке не осталось Общего опыта. Можно перенести сюда его с другого покемона.")
    }

    var expShareBagHint: String {
        t("박스에서 포켓몬을 골라 달아요.",
          "Attach it from a Pokémon's page in the Box.",
          "ボックスでポケモンを選んでつけます。",
          "Pónselo desde la página de un Pokémon en la Caja.",
          "Attache-le depuis la page d'un Pokémon dans la Boîte.",
          "Coloque pela página de um Pokémon na Caixa.",
          "Bring ihn über die Seite eines Pokémon in der Box an.",
          "Прикрепите его на странице покемона в Боксе.")
    }
}
