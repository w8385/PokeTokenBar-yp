import Foundation

extension L {
    var moveOnSetting: String {
        t("진화가 막히거나 경험치가 차면 자동으로 다음으로", "Move on automatically when evolution is stuck or XP is full",
          "進化が止まるか経験値が満タンなら自動で次へ", "Seguir solo cuando la evolución se atasca o la EXP está llena",
          "Passer à la suite tout seul quand l'évolution bloque ou que l'EXP est pleine",
          "Seguir sozinho quando a evolução trava ou a EXP está cheia",
          "Automatisch weiter, wenn die Entwicklung feststeckt oder die EP voll sind",
          "Двигаться дальше самому, когда эволюция застряла или опыт заполнен")
    }

    func moveOnSettingHint(_ minutes: Int) -> String {
        t("키우는 포켓몬이 내 행동을 기다린 채 \(minutes)분 동안 앱을 열지 않으면 박스로 보내고 경험치가 모자란 포켓몬이나 새 알을 키워요. 더 쓸 데가 없는 학습장치는 바로 옮겨요.",
          "If your raised Pokémon waits on you and the app stays closed for \(minutes) min, it goes to the Box and one still short of XP, or a new egg, takes its place. An Exp. Share that can't be used moves right away.",
          "育てているポケモンが操作を待ったまま\(minutes)分アプリを開かないと、ボックスへ送り、経験値が足りないポケモンか新しいタマゴを育てます。使い道のないがくしゅうそうちはすぐ移します。",
          "Si tu Pokémon espera algo de ti y no abres la app en \(minutes) min, va a la Caja y se cría otro al que le falte EXP, o un huevo nuevo. Un Repartir Exp sin uso se mueve al instante.",
          "Si ton Pokémon attend une action de ta part et que l'app reste fermée \(minutes) min, il va dans la Boîte et un autre à qui il manque de l'EXP, ou un nouvel œuf, prend sa place. Un Multi Exp inutile est déplacé tout de suite.",
          "Se o seu Pokémon espera algo de você e o app fica fechado por \(minutes) min, ele vai para a Caixa e outro que ainda precisa de EXP, ou um ovo novo, toma o lugar. Um Compart. Exp. sem uso muda na hora.",
          "Wartet dein Pokémon auf dich und bleibt die App \(minutes) Min. zu, kommt es in die Box und eins, dem noch EP fehlen, oder ein neues Ei rückt nach. Ein EP-Teiler ohne Nutzen wandert sofort weiter.",
          "Если покемон ждёт вашего действия, а приложение закрыто \(minutes) мин, он уходит в Коробку, а растить начинают того, кому не хватает опыта, или новое яйцо. Бесполезный Общий опыт переходит сразу.")
    }

    var moveOnTitle: String {
        t("➡️ 다음 포켓몬으로", "➡️ Moving on", "➡️ 次のポケモンへ", "➡️ Siguiente Pokémon", "➡️ Au suivant",
          "➡️ Próximo Pokémon", "➡️ Weiter geht's", "➡️ Дальше")
    }

    var keepWaiting: String {
        t("계속 기다리기", "Keep waiting", "待ち続ける", "Seguir esperando", "Continuer d'attendre", "Continuar esperando",
          "Weiter warten", "Ждать дальше")
    }

    /// The Home line under a stuck Pokémon.
    func moveOnCountdown(_ needs: String, minutes: Int, next: MoveOnNext, toGraduates: Bool) -> String {
        let plan: String
        switch (next, toGraduates) {
        case (.egg, _):
            plan = t("\(minutes)분 뒤 박스로 + 새 알", "Box + new egg in \(minutes) min", "\(minutes)分後にボックスへ+新しいタマゴ",
                     "Caja + huevo nuevo en \(minutes) min", "Boîte + nouvel œuf dans \(minutes) min",
                     "Caixa + ovo novo em \(minutes) min", "Box + neues Ei in \(minutes) Min.", "Коробка + новое яйцо через \(minutes) мин")
        case (.raise(let name), false):
            plan = t("\(minutes)분 뒤 박스로 + \(name) 키우기", "Box + raise \(name) in \(minutes) min",
                     "\(minutes)分後にボックスへ+\(name)を育てる", "Caja + criar a \(name) en \(minutes) min",
                     "Boîte + élever \(name) dans \(minutes) min", "Caixa + criar \(name) em \(minutes) min",
                     "Box + \(name) aufziehen in \(minutes) Min.", "Коробка + растить \(name) через \(minutes) мин")
        case (.raise(let name), true), (.resume(let name), _):
            plan = t("\(minutes)분 뒤 졸업 + \(name) 키우기", "Graduates + raise \(name) in \(minutes) min",
                     "\(minutes)分後に卒業へ+\(name)を育てる", "Graduados + criar a \(name) en \(minutes) min",
                     "Diplômés + élever \(name) dans \(minutes) min", "Formados + criar \(name) em \(minutes) min",
                     "Absolventen + \(name) aufziehen in \(minutes) Min.", "Выпускники + растить \(name) через \(minutes) мин")
        }
        return "\(needs) · \(plan)"
    }

    func moveOnBody(_ name: String, _ needs: String, _ next: MoveOnNext, toGraduates: Bool) -> String {
        let moved = toGraduates
            ? t("\(name)에게 \(KoreanParticle.subject.attach(to: needs)) 필요해서 졸업생으로 돌아갔어요.", "\(name) needs \(needs), so it went back to the graduates.",
                "\(name)は\(needs)が必要なので、卒業組に戻りました。", "\(name) necesita \(needs), así que volvió con los graduados.",
                "\(name) a besoin de : \(needs), il est donc retourné chez les diplômés.",
                "\(name) precisa de \(needs), então voltou para os formados.",
                "\(name) braucht \(needs), also ist es zu den Absolventen zurück.",
                "\(name) нужно: \(needs), поэтому он вернулся к выпускникам.")
            : t("\(name)에게 \(KoreanParticle.subject.attach(to: needs)) 필요해서 박스로 보냈어요.", "\(name) needs \(needs), so it went to the Box.",
                "\(name)は\(needs)が必要なので、ボックスへ送りました。", "\(name) necesita \(needs), así que fue a la Caja.",
                "\(name) a besoin de : \(needs), il est donc allé dans la Boîte.",
                "\(name) precisa de \(needs), então foi para a Caixa.",
                "\(name) braucht \(needs), also ist es in die Box gegangen.",
                "\(name) нужно: \(needs), поэтому он отправился в Коробку.")
        let after: String
        switch next {
        case .egg:
            after = t("새 알이 오고 있어요.", "A new egg is on the way.", "新しいタマゴがやってきます。", "Viene un huevo nuevo.",
                      "Un nouvel œuf arrive.", "Um ovo novo está a caminho.", "Ein neues Ei ist unterwegs.", "Новое яйцо уже в пути.")
        case .raise(let next), .resume(let next):
            after = t("이제 \(KoreanParticle.object.attach(to: next)) 키워요.", "Now raising \(next).", "これから\(next)を育てます。", "Ahora crías a \(next).",
                      "Tu élèves maintenant \(next).", "Agora você cria \(next).", "Jetzt ziehst du \(next) auf.",
                      "Теперь растёт \(next).")
        }
        return "\(moved) \(after)"
    }

    var expShareMovedTitle: String {
        t("🎒 학습장치를 옮겼어요", "🎒 Exp. Share moved", "🎒 がくしゅうそうちを移しました", "🎒 Repartir Exp movido",
          "🎒 Multi Exp déplacé", "🎒 Compart. Exp. movido", "🎒 EP-Teiler verschoben", "🎒 Общий опыт перемещён")
    }

    func expShareMovedLine(_ from: String, to: String) -> String { "\(from) → \(to)" }

    func boxGraduatedLine(_ name: String) -> String {
        t("\(KoreanParticle.subject.attach(to: name)) 박스에서 졸업했어요.", "\(name) graduated in the Box.",
          "\(name)がボックスで卒業しました。", "\(name) se graduó en la Caja.", "\(name) a obtenu son diplôme dans la Boîte.",
          "\(name) se formou na Caixa.", "\(name) hat in der Box seinen Abschluss gemacht.", "\(name) выпустился в Коробке.")
    }

    func expShareFromBagLine(to: String) -> String {
        t("가방 → \(to)", "Bag → \(to)", "バッグ → \(to)", "Mochila → \(to)", "Sac → \(to)", "Mochila → \(to)",
          "Beutel → \(to)", "Сумка → \(to)")
    }

    func expShareBaggedLine(_ from: String) -> String {
        t("\(from) → 가방", "\(from) → Bag", "\(from) → バッグ", "\(from) → Mochila", "\(from) → Sac", "\(from) → Mochila",
          "\(from) → Beutel", "\(from) → Сумка")
    }
}
