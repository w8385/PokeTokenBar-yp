import Foundation

extension L {
    var friendAdd: String {
        t("친구 포켓몬 추가", "Add a friend", "ともだちを追加", "Añadir un amigo", "Ajouter un compagnon", "Adicionar um amigo", "Freund hinzufügen", "Добавить друга")
    }
    var friendRemove: String {
        t("친구 빼기", "Remove friend", "ともだちを外す", "Quitar amigo", "Retirer le compagnon", "Remover amigo", "Freund entfernen", "Убрать друга")
    }
    var friendLabel: String {
        t("친구 포켓몬", "Friend Pokémon", "ともだちポケモン", "Pokémon amigo", "Pokémon compagnon", "Pokémon amigo", "Freund-Pokémon", "Покемон-друг")
    }
    func friendPickerTitle(_ max: Int) -> String {
        t("함께 있을 포켓몬 (최대 \(max)마리)", "Who joins you (up to \(max))", "いっしょにいるポケモン(最大\(max)匹)",
          "Quién te acompaña (hasta \(max))", "Qui t'accompagne (jusqu'à \(max))", "Quem te acompanha (até \(max))",
          "Wer dabei ist (bis zu \(max))", "Кто рядом (до \(max))")
    }
    var friendJoinsWithEggSwap: String {
        t("친구 칸이 비어 있어서, 박스로 가는 포켓몬이 친구로 함께 다녀요.",
          "A friend slot is free, so the Pokémon heading to the Box walks with you as a friend.",
          "ともだちの枠が空いているので、ボックスに行くポケモンがともだちとしていっしょにいます。",
          "Hay un hueco de amigo libre, así que el Pokémon que va a la Caja te acompaña como amigo.",
          "Une place de compagnon est libre : le Pokémon qui part dans la Boîte t'accompagne comme compagnon.",
          "Há uma vaga de amigo livre, então o Pokémon que vai para a Caixa acompanha você como amigo.",
          "Ein Freundesplatz ist frei, also begleitet dich das Pokémon, das in die Box geht, als Freund.",
          "Есть свободное место для друга, поэтому покемон, который уходит в Коробку, будет рядом как друг.")
    }
}
