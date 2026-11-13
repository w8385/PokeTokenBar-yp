import Foundation

/// Strings for trading Pokémon with coworkers and for the Linking Cord.
extension L {
    // MARK: Battle tab and offer screen

    var tradeSectionTitle: String { t("교환", "Trade", "交換", "Intercambio", "Échange", "Troca", "Tausch", "Обмен") }
    var tradeSectionHint: String {
        t("연결한 동료와 졸업한 포켓몬을 맞바꿔요. 상대가 슬랙에서 수락하면 다음 동기화 때 도착해요.",
          "Swap a graduated Pokémon with a linked coworker. When they accept in Slack, it arrives on the next sync.",
          "つながった同僚と卒業したポケモンを交換します。Slackで相手が承諾すると、次の同期で届きます。",
          "Intercambia un Pokémon graduado con un compañero vinculado. Cuando acepte en Slack, llegará en la siguiente sincronización.",
          "Échange un Pokémon diplômé avec un collègue lié. Quand il accepte dans Slack, il arrive à la prochaine synchronisation.",
          "Troque um Pokémon formado com um colega vinculado. Quando ele aceitar no Slack, chega na próxima sincronização.",
          "Tausche ein Pokémon im Ruhestand mit einem verbundenen Kollegen. Sobald er in Slack zusagt, kommt es beim nächsten Abgleich an.",
          "Обменяйте выпустившегося покемона с коллегой. Когда он согласится в Slack, покемон придёт при следующей синхронизации.")
    }
    var tradeOfferButton: String { t("교환 제안", "Offer a trade", "交換を提案", "Proponer intercambio", "Proposer un échange", "Propor troca", "Tausch anbieten", "Предложить обмен") }
    var tradeOfferTitle: String { t("교환 제안", "Offer a trade", "交換の提案", "Proponer un intercambio", "Proposer un échange", "Propor uma troca", "Tausch anbieten", "Предложение обмена") }
    var tradePickPokemon: String { t("보낼 포켓몬", "Pokémon to send", "送るポケモン", "Pokémon a enviar", "Pokémon à envoyer", "Pokémon a enviar", "Zu sendendes Pokémon", "Покемон для отправки") }
    var tradePickCoworker: String { t("교환할 동료", "Trade with", "交換する相手", "Intercambiar con", "Échanger avec", "Trocar com", "Tauschen mit", "Обмен с") }
    var tradeNoPokemon: String {
        t("보낼 수 있는 포켓몬이 없어요. 졸업한 포켓몬만 교환할 수 있어요.",
          "No Pokémon can be sent yet. Only graduated Pokémon can be traded.",
          "送れるポケモンがいません。卒業したポケモンだけ交換できます。",
          "Aún no hay Pokémon para enviar. Solo se pueden intercambiar los graduados.",
          "Aucun Pokémon à envoyer. Seuls les Pokémon diplômés peuvent être échangés.",
          "Ainda não há Pokémon para enviar. Só os formados podem ser trocados.",
          "Noch kein Pokémon zum Senden. Nur Pokémon im Ruhestand lassen sich tauschen.",
          "Пока нечего отправлять. Обмениваются только выпустившиеся покемоны.")
    }
    var tradeLoadingCoworkers: String { t("동료를 불러오는 중…", "Loading coworkers…", "同僚を読み込み中…", "Cargando compañeros…", "Chargement des collègues…", "Carregando colegas…", "Kollegen werden geladen…", "Загрузка коллег…") }
    var tradeNoCoworkers: String {
        t("교환할 수 있는 동료가 아직 없어요. 상대도 앱을 연결하고 업데이트해야 해요.",
          "No coworker to trade with yet. They need to link and update the app too.",
          "交換できる同僚がまだいません。相手もアプリを連携して更新する必要があります。",
          "Aún no hay compañeros con quien intercambiar. También deben vincular y actualizar la app.",
          "Aucun collègue disponible pour l'instant. Il doit aussi lier et mettre à jour l'app.",
          "Ainda não há colegas para trocar. Eles também precisam vincular e atualizar o app.",
          "Noch kein Kollege zum Tauschen. Er muss die App ebenfalls verbinden und aktualisieren.",
          "Пока не с кем обмениваться. Коллега тоже должен подключить и обновить приложение.")
    }
    var tradeCoworkersUnavailable: String {
        t("봇에 연결하지 못했어요. 봇 주소와 토큰을 확인해 주세요.",
          "Could not reach the bot. Check the bot address and token.",
          "ボットに接続できません。アドレスとトークンを確認してください。",
          "No se pudo contactar con el bot. Revisa la dirección y el token.",
          "Impossible de joindre le bot. Vérifie l'adresse et le jeton.",
          "Não foi possível falar com o bot. Verifique o endereço e o token.",
          "Der Bot ist nicht erreichbar. Prüfe Adresse und Token.",
          "Не удалось связаться с ботом. Проверьте адрес и токен.")
    }
    var tradeSendOffer: String { t("제안 보내기", "Send offer", "提案を送る", "Enviar propuesta", "Envoyer l'offre", "Enviar proposta", "Angebot senden", "Отправить предложение") }
    var tradeSending: String { t("보내는 중…", "Sending…", "送信中…", "Enviando…", "Envoi…", "Enviando…", "Sende…", "Отправка…") }
    func tradeOfferSent(_ name: String) -> String {
        t("\(name)님에게 제안을 보냈어요. 슬랙 DM에서 상대가 고르고 수락하면 교환돼요. 24시간 안에 답이 없으면 사라져요.",
          "Offer sent to \(name). They pick a Pokémon and accept in a Slack DM. It expires after 24 hours.",
          "\(name)さんに提案を送りました。相手がSlackのDMで選んで承諾すると交換されます。24時間で期限切れになります。",
          "Propuesta enviada a \(name). Elegirá un Pokémon y aceptará en un MD de Slack. Caduca en 24 horas.",
          "Offre envoyée à \(name). Il choisit un Pokémon et accepte dans un MP Slack. Elle expire après 24 h.",
          "Proposta enviada para \(name). A pessoa escolhe um Pokémon e aceita em uma DM do Slack. Expira em 24 horas.",
          "Angebot an \(name) gesendet. Er wählt ein Pokémon und sagt in einer Slack-DM zu. Es verfällt nach 24 Stunden.",
          "Предложение отправлено: \(name). Коллега выберет покемона и согласится в личном сообщении Slack. Через 24 часа оно истечёт.")
    }
    var tradeSendFailed: String {
        t("제안을 보내지 못했어요. 잠시 뒤 다시 시도해 주세요.",
          "The offer could not be sent. Try again in a moment.",
          "提案を送れませんでした。しばらくしてから再試行してください。",
          "No se pudo enviar la propuesta. Inténtalo de nuevo en un momento.",
          "L'offre n'a pas pu être envoyée. Réessaie dans un instant.",
          "Não foi possível enviar a proposta. Tente novamente em instantes.",
          "Das Angebot konnte nicht gesendet werden. Versuche es gleich noch einmal.",
          "Не удалось отправить предложение. Повторите попытку чуть позже.")
    }

    var tradeLockedItemText: String {
        t("교환 중이라 지닌 도구를 바꿀 수 없어요. 교환이 끝나거나 취소되면 풀려요.",
          "In a trade, so its held item is locked until the trade ends or is cancelled.",
          "交換中のため持ち物は変更できません。交換が終わるか取り消されると解除されます。",
          "Está en un intercambio: su objeto equipado queda bloqueado hasta que termine o se cancele.",
          "En cours d'échange : son objet tenu est verrouillé jusqu'à la fin ou l'annulation de l'échange.",
          "Está em uma troca: o item equipado fica bloqueado até a troca terminar ou ser cancelada.",
          "Im Tausch: Das getragene Item ist gesperrt, bis der Tausch endet oder abgebrochen wird.",
          "Участвует в обмене: предмет заблокирован, пока обмен не завершится или не будет отменён.")
    }

    func tradeRefusalText(_ refusal: TradeRefusal) -> String {
        switch refusal {
        case .raising:
            return t("키우는 중인 포켓몬은 교환할 수 없어요.", "The Pokémon you are raising can't be traded.", "育成中のポケモンは交換できません。", "El Pokémon que estás criando no se puede intercambiar.", "Le Pokémon que tu élèves ne peut pas être échangé.", "O Pokémon que você está criando não pode ser trocado.", "Das Pokémon, das du aufziehst, kann nicht getauscht werden.", "Выращиваемого покемона нельзя обменять.")
        case .fighting:
            return t("전투 포켓몬은 교환할 수 없어요. 먼저 다른 포켓몬을 전투에 내보내세요.", "The battle Pokémon can't be traded. Pick another for battle first.", "対戦ポケモンは交換できません。先に別のポケモンを対戦に出してください。", "El Pokémon de combate no se puede intercambiar. Elige otro para combatir primero.", "Le Pokémon de combat ne peut pas être échangé. Choisis-en un autre pour le combat d'abord.", "O Pokémon de batalha não pode ser trocado. Escolha outro para a batalha primeiro.", "Das Kampf-Pokémon kann nicht getauscht werden. Wähle zuerst ein anderes für den Kampf.", "Боевого покемона нельзя обменять. Сначала выберите для боя другого.")
        case .arriving:
            return t("방금 도착해 진화를 확인하는 중이에요.", "It just arrived and is still being checked for evolution.", "届いたばかりで、進化を確認中です。", "Acaba de llegar y se está comprobando su evolución.", "Il vient d'arriver, son évolution est en cours de vérification.", "Acabou de chegar e a evolução está sendo verificada.", "Es ist gerade angekommen, die Entwicklung wird noch geprüft.", "Только что прибыл, эволюция ещё проверяется.")
        case .unavailable:
            return t("이 포켓몬은 교환할 수 없어요.", "This Pokémon can't be traded.", "このポケモンは交換できません。", "Este Pokémon no se puede intercambiar.", "Ce Pokémon ne peut pas être échangé.", "Este Pokémon não pode ser trocado.", "Dieses Pokémon kann nicht getauscht werden.", "Этого покемона нельзя обменять.")
        }
    }

    // MARK: Arrival and evolution

    func tradeArrivalReceived(_ pokemon: String, from sender: String) -> String {
        t("\(sender)님에게서 \(pokemon)이(가) 도착했어요!", "\(pokemon) arrived from \(sender)!", "\(sender)さんから\(pokemon)が届きました！", "¡\(pokemon) llegó de \(sender)!", "\(pokemon) est arrivé de la part de \(sender) !", "\(pokemon) chegou de \(sender)!", "\(pokemon) ist von \(sender) angekommen!", "\(pokemon) прибыл от \(sender)!")
    }
    func tradeArrivalEvolved(_ from: String, _ to: String) -> String {
        t("\(from)이(가) \(to)(으)로 진화했어요!", "\(from) evolved into \(to)!", "\(from)は\(to)に進化した！", "¡\(from) evolucionó a \(to)!", "\(from) a évolué en \(to) !", "\(from) evoluiu para \(to)!", "\(from) hat sich zu \(to) entwickelt!", "\(from) эволюционировал в \(to)!")
    }
    func notifTradeBody(_ pokemon: String, from sender: String) -> String { tradeArrivalReceived(pokemon, from: sender) }
    var notifTradeTitle: String { t("🔁 교환 완료!", "🔁 Trade complete!", "🔁 交換完了！", "🔁 ¡Intercambio completado!", "🔁 Échange terminé !", "🔁 Troca concluída!", "🔁 Tausch abgeschlossen!", "🔁 Обмен завершён!") }
    var notifTradeEvolveTitle: String { t("✨ 교환 진화!", "✨ Trade evolution!", "✨ 通信進化！", "✨ ¡Evolución por intercambio!", "✨ Évolution par échange !", "✨ Evolução por troca!", "✨ Tauschentwicklung!", "✨ Эволюция обменом!") }
    func notifTradeEvolveBody(_ from: String, _ to: String) -> String { tradeArrivalEvolved(from, to) }
    func originalTrainerLine(_ name: String) -> String {
        t("원래 트레이너: \(name)", "Original trainer: \(name)", "元のトレーナー：\(name)", "Entrenador original: \(name)", "Dresseur d'origine : \(name)", "Treinador original: \(name)", "Ursprünglicher Trainer: \(name)", "Первый тренер: \(name)")
    }
    func tradedAwayLine(_ name: String) -> String {
        t("\(name)님과 교환해 보냈어요", "Traded away to \(name)", "\(name)さんに交換で渡しました", "Intercambiado con \(name)", "Échangé avec \(name)", "Trocado com \(name)", "An \(name) getauscht", "Обменян: \(name)")
    }

    // MARK: Linking Cord

    var linkingCordDescription: String {
        t("졸업한 포켓몬에게 쓰면 교환한 것처럼 진화해요.",
          "Use it on a graduated Pokémon to evolve it as if it had been traded.",
          "卒業したポケモンに使うと、交換したかのように進化します。",
          "Úsalo con un Pokémon graduado para que evolucione como si lo hubieras intercambiado.",
          "À utiliser sur un Pokémon diplômé pour le faire évoluer comme s'il avait été échangé.",
          "Use em um Pokémon formado para evoluí-lo como se tivesse sido trocado.",
          "Auf ein Pokémon im Ruhestand angewendet, entwickelt es sich, als wäre es getauscht worden.",
          "Применяется к выпустившемуся покемону: он эволюционирует, как после обмена.")
    }
    var linkingCordBagHint: String {
        t("도감에서 졸업한 포켓몬을 열어 사용해요", "Open a graduated Pokémon in the Pokédex to use it", "図鑑で卒業したポケモンを開いて使います", "Abre un Pokémon graduado en la Pokédex para usarlo", "Ouvre un Pokémon diplômé dans le Pokédex pour l'utiliser", "Abra um Pokémon formado na Pokédex para usar", "Öffne ein Pokémon im Ruhestand im Pokédex, um es zu benutzen", "Откройте выпустившегося покемона в Покедексе")
    }
    var linkingCordUse: String { t("연결의끈 사용", "Use Linking Cord", "つながりのヒモを使う", "Usar Cordón Unión", "Utiliser le Fil de Liaison", "Usar Cordão Elo", "Verbindungsschnur benutzen", "Использовать шнур") }
    func linkingCordWrongTarget(_ pokemon: String) -> String {
        t("\(pokemon)은(는) 교환으로 진화하지 않아요. 연결의끈은 그대로 남아 있어요.",
          "\(pokemon) doesn't evolve by trade. Your Linking Cord is kept.",
          "\(pokemon)は交換では進化しません。つながりのヒモはそのまま残ります。",
          "\(pokemon) no evoluciona por intercambio. Conservas el Cordón Unión.",
          "\(pokemon) n'évolue pas par échange. Tu gardes le Fil de Liaison.",
          "\(pokemon) não evolui por troca. O Cordão Elo foi mantido.",
          "\(pokemon) entwickelt sich nicht durch Tausch. Die Verbindungsschnur bleibt erhalten.",
          "\(pokemon) не эволюционирует обменом. Шнур остался у вас.")
    }
    func linkingCordNotReady(_ pokemon: String) -> String {
        t("\(pokemon)은(는) 아직 진화할 수 없어요. 필요한 도구를 장착하거나 친구로 둔 뒤 다시 시도하세요. 연결의끈은 그대로 남아 있어요.",
          "\(pokemon) can't evolve yet. Equip the item it needs or have its partner as a friend, then try again. Your Linking Cord is kept.",
          "\(pokemon)はまだ進化できません。必要などうぐを持たせるか、相手をともだちにしてからもう一度。つながりのヒモはそのまま残ります。",
          "\(pokemon) aún no puede evolucionar. Equípale el objeto que necesita o ten a su pareja como amigo e inténtalo de nuevo. Conservas el Cordón Unión.",
          "\(pokemon) ne peut pas encore évoluer. Fais-lui tenir l'objet requis ou prends son partenaire comme ami, puis réessaie. Tu gardes le Fil de Liaison.",
          "\(pokemon) ainda não pode evoluir. Equipe o item de que precisa ou tenha o parceiro como amigo e tente de novo. O Cordão Elo foi mantido.",
          "\(pokemon) kann sich noch nicht entwickeln. Rüste das nötige Item aus oder nimm den Tauschpartner als Freund auf und versuche es erneut. Die Verbindungsschnur bleibt erhalten.",
          "\(pokemon) пока не может эволюционировать. Дайте нужный предмет или добавьте его партнёра в друзья и повторите. Шнур остался у вас.")
    }
    var linkingCordUnavailable: String {
        t("지금은 진화 정보를 불러오지 못했어요. 연결의끈은 그대로 남아 있어요.",
          "The evolution data could not be loaded right now. Your Linking Cord is kept.",
          "いま進化の情報を読み込めませんでした。つながりのヒモはそのまま残ります。",
          "No se pudieron cargar los datos de evolución. Conservas el Cordón Unión.",
          "Les données d'évolution n'ont pas pu être chargées. Tu gardes le Fil de Liaison.",
          "Não foi possível carregar os dados de evolução. O Cordão Elo foi mantido.",
          "Die Entwicklungsdaten konnten nicht geladen werden. Die Verbindungsschnur bleibt erhalten.",
          "Не удалось загрузить данные об эволюции. Шнур остался у вас.")
    }
}
