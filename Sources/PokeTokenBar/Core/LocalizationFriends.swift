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
}
