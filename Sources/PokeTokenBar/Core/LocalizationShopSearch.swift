import Foundation

extension L {
    var shopSearchPrompt: String {
        t("아이템·기술 이름이나 효과 검색…", "Search items, moves or effects…", "アイテム・わざの名前や効果で検索…",
          "Buscar objetos, movimientos o efectos…", "Rechercher objets, capacités ou effets…",
          "Buscar itens, golpes ou efeitos…", "Items, Attacken oder Effekte suchen…", "Поиск предметов, приёмов или эффектов…")
    }

    var shopSearchEmpty: String {
        t("찾는 아이템이 없어요.", "No items match.", "見つかりませんでした。", "Ningún objeto coincide.",
          "Aucun objet ne correspond.", "Nenhum item encontrado.", "Keine passenden Items.", "Ничего не найдено.")
    }
}
