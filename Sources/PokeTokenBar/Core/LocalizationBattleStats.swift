import Foundation

/// Strings for the battle stats on the battle tab's lineup rows.
extension L {
    /// `key` is a `PokemonStatCalculator.order` name.
    func battleStatName(_ key: String) -> String {
        key == "hp" ? t("HP", "HP", "HP", "PS", "PV", "HP", "KP", "HP")
            : statName(key.replacingOccurrences(of: "-", with: "_"))
    }

    func battleStatFormLabel(_ form: BattleStatLine.Form) -> String {
        switch form {
        case .normal: t("평소", "Normal", "通常", "Normal", "Normal", "Normal", "Normal", "Обычно")
        case .mega: t("메가", "Mega", "メガ", "Mega", "Méga", "Mega", "Mega", "Мега")
        case .stellar: t("스텔라", "Stellar", "ステラ", "Astral", "Stellaire", "Estelar", "Stellar", "Звёздная")
        }
    }
}
