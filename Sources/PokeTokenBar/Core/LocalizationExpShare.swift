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
        t("보관 중에는 경험치만 쌓이고, 다시 키우면 그만큼 진화해요.",
          "While stored it only banks EXP. It evolves with it once you raise it again.",
          "預けている間は経験値がたまるだけで、また育てるとその分進化します。",
          "Mientras está guardado solo acumula EXP. Evoluciona con ella cuando vuelvas a criarlo.",
          "Rangé, il ne fait qu'accumuler de l'EXP. Il évolue avec quand tu le reprends.",
          "Guardado, ele só acumula EXP. Evolui com ela quando você voltar a criá-lo.",
          "Verwahrt sammelt es nur EP. Es entwickelt sich damit, sobald du es wieder aufziehst.",
          "На хранении он только копит опыт. Эволюционирует с ним, когда вы снова начнёте его растить.")
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
        t("가방에 남은 학습장치가 없어요. 다른 포켓몬에게서 떼면 달 수 있어요.",
          "No Exp. Share left in your bag. Detach one from another Pokémon to attach it here.",
          "バッグにがくしゅうそうちが残っていません。ほかのポケモンからはずすとつけられます。",
          "No te queda ningún Repartir Exp en la mochila. Quítaselo a otro Pokémon para ponérselo a este.",
          "Plus aucun Multi Exp dans le sac. Retire-le d'un autre Pokémon pour l'attacher ici.",
          "Nenhum Compart. Exp. sobrando na mochila. Remova de outro Pokémon para colocar neste.",
          "Kein EP-Teiler mehr im Beutel. Nimm einen einem anderen Pokémon ab, um ihn hier anzubringen.",
          "В сумке не осталось Общего опыта. Снимите его с другого покемона, чтобы прикрепить сюда.")
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
