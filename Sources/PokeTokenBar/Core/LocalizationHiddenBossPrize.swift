import Foundation

/// Text of the hidden boss prize: the shiny egg, the candies and the signature items.
extension L {
    /// The egg, the candies, then each item; all plates at once read as one line.
    func hiddenBossPrizeLines(eggSpeciesID: Int, itemKeys: [String]) -> [String] {
        var lines = [prizeEggName(eggSpeciesID), "\(itemName(.rareCandy)) ×\(HiddenBossPrize.candyCount)"]
        let plateKeys = ItemKind.plates.map(\.rawValue)
        if !itemKeys.isEmpty, itemKeys == plateKeys {
            lines.append(prizePlates(plateKeys.count))
        } else {
            lines += itemKeys.compactMap { key in
                MegaStone.stone(inventoryKey: key).map(megaStoneName) ?? ItemKind(rawValue: key).map(itemName)
            }
        }
        return lines
    }

    func prizePlates(_ count: Int) -> String {
        t("플레이트 \(count)종", "\(count) Plates", "プレート\(count)種", "\(count) tablas", "\(count) plaques",
          "\(count) placas", "\(count) Tafeln", "Пластины ×\(count)")
    }

    func prizeEggName(_ speciesID: Int) -> String {
        let name = prizeSpeciesName(speciesID)
        return t("빛나는 \(name)의 알", "Shiny \(name) Egg", "色違い\(name)のタマゴ", "Huevo de \(name) variocolor",
                 "Œuf de \(name) chromatique", "Ovo de \(name) brilhante", "Schillerndes \(name)-Ei", "Сияющее яйцо: \(name)")
    }

    var prizeEggDescription: String {
        t("부화하면 반드시 색이 다른 포켓몬이 나와요. 지금 포켓몬은 박스로 가요.",
          "It always hatches shiny. Your current Pokémon goes to the Box.",
          "かならず色違いが生まれます。いまのポケモンはボックスへ送られます。",
          "Siempre eclosiona variocolor. Tu Pokémon actual va a la Caja.",
          "Il éclot toujours chromatique. Ton Pokémon actuel part dans la Boîte.",
          "Sempre choca brilhante. Seu Pokémon atual vai para a Caixa.",
          "Schlüpft immer schillernd. Dein aktuelles Pokémon kommt in die Box.",
          "Всегда вылупляется сияющим. Нынешний покемон отправится в бокс.")
    }

    var prizeEggIncubate: String {
        t("품기", "Incubate", "あたためる", "Incubar", "Couver", "Chocar", "Ausbrüten", "Высиживать")
    }

    private func prizeSpeciesName(_ speciesID: Int) -> String {
        switch speciesID {
        case 150: t("뮤츠", "Mewtwo", "ミュウツー", "Mewtwo", "Mewtwo", "Mewtwo", "Mewtu", "Мьюту")
        case 251: t("세레비", "Celebi", "セレビィ", "Celebi", "Celebi", "Celebi", "Celebi", "Селеби")
        case 384: t("레쿠쟈", "Rayquaza", "レックウザ", "Rayquaza", "Rayquaza", "Rayquaza", "Rayquaza", "Рейкваза")
        case 493: t("아르세우스", "Arceus", "アルセウス", "Arceus", "Arceus", "Arceus", "Arceus", "Арсеус")
        case 494: t("비크티니", "Victini", "ビクティニ", "Victini", "Victini", "Victini", "Victini", "Виктини")
        case 718: t("지가르데", "Zygarde", "ジガルデ", "Zygarde", "Zygarde", "Zygarde", "Zygarde", "Зайгард")
        case 800: t("네크로즈마", "Necrozma", "ネクロズマ", "Necrozma", "Necrozma", "Necrozma", "Necrozma", "Некрозма")
        case 890: t("무한다이노", "Eternatus", "ムゲンダイナ", "Eternatus", "Éthernatos", "Eternatus", "Endynalos", "Этернатус")
        case 1024: t("테라파고스", "Terapagos", "テラパゴス", "Terapagos", "Terapagos", "Terapagos", "Terapagos", "Терапагос")
        default: "#\(speciesID)"
        }
    }
}
