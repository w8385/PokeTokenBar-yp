import Foundation

extension L {
    var raiseThis: String {
        t("이 포켓몬 키우기", "Raise this Pokémon", "このポケモンを育てる", "Criar a este Pokémon", "Élever ce Pokémon",
          "Criar este Pokémon", "Dieses Pokémon aufziehen", "Растить этого покемона")
    }

    var resumeLine: String {
        t("다시 키우기", "Raise again", "育成を再開", "Volver a criar", "Reprendre l'élevage",
          "Voltar a criar", "Wieder aufziehen", "Продолжить выращивание")
    }

    var parkedBadge: String {
        t("쉬는 중", "Resting", "休み中", "Descansando", "Au repos", "Descansando", "Ruht", "Отдыхает")
    }

    var storedBadge: String {
        t("보관 중", "Stored", "預け中", "Guardado", "Rangé", "Guardado", "Verwahrt", "На хранении")
    }

    var storedRaiseLocked: String {
        t("알이 부화하면 다시 키울 수 있어요.", "You can raise it again once your egg hatches.",
          "タマゴが孵ると、また育てられます。", "Podrás volver a criarlo cuando eclosione tu huevo.",
          "Tu pourras de nouveau l'élever une fois ton œuf éclos.", "Dá para voltar a criá-lo quando seu ovo chocar.",
          "Du kannst es wieder aufziehen, sobald dein Ei geschlüpft ist.", "Снова растить его можно, когда вылупится яйцо.")
    }

    var parkedEggName: String {
        t("알", "Egg", "タマゴ", "Huevo", "Œuf", "Ovo", "Ei", "Яйцо")
    }

    var parkedLockedHint: String {
        t("쉬는 중인 포켓몬을 다시 키우면 쓸 수 있어요.", "Raise your resting Pokémon again to use this.",
          "休んでいるポケモンの育成を再開すると使えます。", "Vuelve a criar a tu Pokémon en descanso para usarlo.",
          "Reprends l'élevage de ton Pokémon au repos pour l'utiliser.",
          "Volte a criar o Pokémon que está descansando para usar.",
          "Zieh dein ruhendes Pokémon wieder auf, um das zu nutzen.",
          "Снова начните выращивать отдыхающего покемона, чтобы использовать это.")
    }

    /// Home line under a raised graduate: what waits and how to get it back.
    func parkedLineNote(_ name: String) -> String {
        t("\(name) · 쉬는 중 (진행은 그대로 보관돼요)", "\(name) · resting (progress is kept)",
          "\(name) · 休み中（進行はそのまま保管されます）", "\(name) · descansando (el progreso se conserva)",
          "\(name) · au repos (la progression est conservée)", "\(name) · descansando (o progresso é mantido)",
          "\(name) · ruht (der Fortschritt bleibt erhalten)", "\(name) · отдыхает (прогресс сохранён)")
    }

    var representativeSetHere: String {
        t("대표로 지정", "Set as representative", "代表に指定", "Fijar como representante", "Définir comme représentatif",
          "Definir como representante", "Als Repräsentant festlegen", "Назначить основным")
    }

    var representativeClear: String {
        t("대표 해제", "Clear representative", "代表を解除", "Quitar representante", "Retirer le représentatif",
          "Remover representante", "Repräsentant aufheben", "Снять основного")
    }
}
