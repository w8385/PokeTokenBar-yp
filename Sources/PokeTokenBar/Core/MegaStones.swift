import Foundation

/// One Mega Stone per Pokémon that has a PokéAPI `-mega` form (Rayquaza holds none: it needs no stone).
/// Held on the battle Pokémon it Mega Evolves at the start of a battle; on the home screen it only changes
/// the sprite, so species, level and save data stay the base form. Rows are generated from PokéAPI.
///
/// The inventory key is `mega-stone:<slug>`, so the stones live beside `ItemKind` without adding a case each.
struct MegaStone: Hashable, Sendable {
    static let price = 3_000_000_000
    static let keyPrefix = "mega-stone:"
    /// The PokéAPI sprites repo has no image for these Mega forms; they keep the base sprite.
    static let missingSpriteIDs: Set<Int> = [10301]

    let slug: String
    let speciesID: Int
    let megaID: Int
    let types: [String]
    /// hp, attack, defense, special-attack, special-defense, speed.
    let stats: [Int]
    private let names: String
    private let abilityNames: String

    init(_ slug: String, _ speciesID: Int, _ megaID: Int, _ types: [String], _ stats: [Int],
         _ names: String, _ abilityNames: String) {
        self.slug = slug
        self.speciesID = speciesID
        self.megaID = megaID
        self.types = types
        self.stats = stats
        self.names = names
        self.abilityNames = abilityNames
    }

    var inventoryKey: String { Self.keyPrefix + slug }
    var spriteID: Int? { Self.missingSpriteIDs.contains(megaID) ? nil : megaID }

    /// "X" / "Y" / "Z" for the stones of a species with more than one Mega form.
    var variantSuffix: String? {
        guard let last = slug.split(separator: "-").last, last.count == 1, "xyz".contains(last) else { return nil }
        return last.uppercased()
    }

    func name(in language: AppLanguage) -> String { Self.pick(names, language) }
    /// nil when PokéAPI lists no ability for the Mega form yet.
    func abilityName(in language: AppLanguage) -> String? { abilityNames.isEmpty ? nil : Self.pick(abilityNames, language) }

    private static func pick(_ joined: String, _ language: AppLanguage) -> String {
        let parts = joined.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let index: Int
        switch language {
        case .ko: index = 0
        case .en, .pt, .ru: index = 1
        case .ja: index = 2
        case .es: index = 3
        case .fr: index = 4
        case .de: index = 5
        }
        return parts.indices.contains(index) ? parts[index] : parts[1]
    }

    static func stone(inventoryKey key: String) -> MegaStone? {
        guard key.hasPrefix(keyPrefix) else { return nil }
        return bySlug[String(key.dropFirst(keyPrefix.count))]
    }

    static func stone(slug: String) -> MegaStone? { bySlug[slug] }

    static func stones(for speciesID: Int) -> [MegaStone] { all.filter { $0.speciesID == speciesID } }

    private static let bySlug = Dictionary(uniqueKeysWithValues: all.map { ($0.slug, $0) })

    static let all: [MegaStone] = [
        .init("venusaurite", 3, 10033, ["grass", "poison"], [80, 100, 123, 122, 120, 80],
              "이상해꽃나이트|Venusaurite|フシギバナイト|Venusaurita|Florizarrite|Bisaflornit",
              "두꺼운지방|Thick Fat|あついしぼう|Sebo|Isograisse|Speckschicht"),
        .init("charizardite-x", 6, 10034, ["fire", "dragon"], [78, 130, 111, 130, 85, 100],
              "리자몽나이트X|Charizardite X|リザードナイトＸ|Charizardita X|Dracaufite X|Gluraknit X",
              "단단한발톱|Tough Claws|かたいツメ|Garra Dura|Griffe Dure|Krallenwucht"),
        .init("charizardite-y", 6, 10035, ["fire", "flying"], [78, 104, 78, 159, 115, 100],
              "리자몽나이트Y|Charizardite Y|リザードナイトＹ|Charizardita Y|Dracaufite Y|Gluraknit Y",
              "가뭄|Drought|ひでり|Sequía|Sécheresse|Dürre"),
        .init("blastoisinite", 9, 10036, ["water"], [79, 103, 120, 135, 115, 78],
              "거북왕나이트|Blastoisinite|カメックスナイト|Blastoisita|Tortankite|Turtoknit",
              "메가런처|Mega Launcher|メガランチャー|Megadisparador|Méga Blaster|Megawumme"),
        .init("beedrillite", 15, 10090, ["bug", "poison"], [65, 150, 40, 15, 80, 145],
              "독침붕나이트|Beedrillite|スピアナイト|Beedrillita|Dardargnite|Bibornit",
              "적응력|Adaptability|てきおうりょく|Adaptable|Adaptabilité|Anpassung"),
        .init("pidgeotite", 18, 10073, ["normal", "flying"], [83, 80, 80, 135, 80, 121],
              "피죤투나이트|Pidgeotite|ピジョットナイト|Pidgeotita|Roucarnagite|Taubossnit",
              "노가드|No Guard|ノーガード|Indefenso|Annule Garde|Schildlos"),
        .init("raichunite-x", 26, 10304, ["electric"], [60, 135, 95, 90, 95, 110],
              "라이츄나이트X|Raichunite X|ライチュウナイトＸ|Raichunita X|Raichuïte X|Raichunit X",
              "일렉트릭메이커|Electric Surge|エレキメイカー|Electrogénesis|Créa-Élec|Elektro-Erzeuger"),
        .init("raichunite-y", 26, 10305, ["electric"], [60, 100, 55, 160, 80, 130],
              "라이츄나이트Y|Raichunite Y|ライチュウナイトＹ|Raichunita Y|Raichuïte Y|Raichunit Y",
              "노가드|No Guard|ノーガード|Indefenso|Annule Garde|Schildlos"),
        .init("clefablite", 36, 10278, ["fairy", "flying"], [95, 80, 93, 135, 110, 70],
              "픽시나이트|Clefablite|ピクシナイト|Clefablita|Mélodelfite|Pixinit",
              "매직미러|Magic Bounce|マジックミラー|Espejo Mágico|Miroir Magik|Magiespiegel"),
        .init("alakazite", 65, 10037, ["psychic"], [55, 50, 65, 175, 105, 150],
              "후디나이트|Alakazite|フーディナイト|Alakazamita|Alakazamite|Simsalanit",
              "트레이스|Trace|トレース|Calco|Calque|Erfassen"),
        .init("victreebelite", 71, 10279, ["grass", "poison"], [80, 125, 85, 135, 95, 70],
              "우츠보트나이트|Victreebelite|ウツボットナイト|Victreebelita|Empiflorite|Sarzenianit",
              "내용물분출|Innards Out|とびだすなかみ|Revés|Expuls’Organes|Magenkrempler"),
        .init("slowbronite", 80, 10071, ["water", "psychic"], [95, 75, 180, 130, 80, 30],
              "야도란나이트|Slowbronite|ヤドランナイト|Slowbronita|Flagadossite|Lahmusnit",
              "조가비갑옷|Shell Armor|シェルアーマー|Caparazón|Coque Armure|Panzerhaut"),
        .init("gengarite", 94, 10038, ["ghost", "poison"], [60, 65, 80, 170, 95, 130],
              "팬텀나이트|Gengarite|ゲンガナイト|Gengarita|Ectoplasmite|Gengarnit",
              "그림자밟기|Shadow Tag|かげふみ|Sombra Trampa|Marque Ombre|Wegsperre"),
        .init("kangaskhanite", 115, 10039, ["normal"], [105, 125, 100, 60, 100, 100],
              "캥카나이트|Kangaskhanite|ガルーラナイト|Kangaskhanita|Kangourexite|Kangamanit",
              "부자유친|Parental Bond|おやこあい|Amor Filial|Amour Filial|Familienbande"),
        .init("starminite", 121, 10280, ["water", "psychic"], [60, 100, 105, 130, 105, 120],
              "아쿠스타나이트|Starminite|スターミナイト|Starmita|Starossite|Starmienit",
              "천하장사|Huge Power|ちからもち|Potencia|Coloforce|Kraftkoloss"),
        .init("pinsirite", 127, 10040, ["bug", "flying"], [65, 155, 120, 65, 90, 105],
              "쁘사이저나이트|Pinsirite|カイロスナイト|Pinsirita|Scarabruite|Pinsirnit",
              "스카이스킨|Aerilate|スカイスキン|Piel Celeste|Peau Céleste|Zenithaut"),
        .init("gyaradosite", 130, 10041, ["water", "dark"], [95, 155, 109, 70, 130, 81],
              "갸라도스나이트|Gyaradosite|ギャラドスナイト|Gyaradosita|Léviatorite|Garadosnit",
              "틀깨기|Mold Breaker|かたやぶり|Rompemoldes|Brise Moule|Überbrückung"),
        .init("aerodactylite", 142, 10042, ["rock", "flying"], [80, 135, 85, 70, 95, 150],
              "프테라나이트|Aerodactylite|プテラナイト|Aerodactylita|Ptéraïte|Aerodactylonit",
              "단단한발톱|Tough Claws|かたいツメ|Garra Dura|Griffe Dure|Krallenwucht"),
        .init("dragoninite", 149, 10281, ["dragon", "flying"], [91, 124, 115, 145, 125, 100],
              "망나뇽나이트|Dragoninite|カイリュナイト|Dragonitita|Dracolossite|Dragoranit",
              "멀티스케일|Multiscale|マルチスケイル|Multiescamas|Multiécaille|Multischuppe"),
        .init("mewtwonite-x", 150, 10043, ["psychic", "fighting"], [106, 190, 100, 154, 100, 130],
              "뮤츠나이트X|Mewtwonite X|ミュウツナイトＸ|Mewtwoita X|Mewtwoïte X|Mewtunit X",
              "불굴의마음|Steadfast|ふくつのこころ|Impasible|Impassible|Felsenfest"),
        .init("mewtwonite-y", 150, 10044, ["psychic"], [106, 150, 70, 194, 120, 140],
              "뮤츠나이트Y|Mewtwonite Y|ミュウツナイトＹ|Mewtwoita Y|Mewtwoïte Y|Mewtunit Y",
              "불면|Insomnia|ふみん|Insomnio|Insomnia|Insomnia"),
        .init("meganiumite", 154, 10282, ["grass", "fairy"], [80, 92, 115, 143, 115, 80],
              "메가니움나이트|Meganiumite|メガニウムナイト|Meganiumita|Méganiumite|Meganienit",
              "메가솔라|Mega Sol|メガソーラー|Megasolar|Méga-Soleil|Mega-Solarladung"),
        .init("feraligite", 160, 10283, ["water", "dragon"], [85, 160, 125, 89, 93, 78],
              "장크로다일나이트|Feraligite|オーダイルナイト|Feraligatrita|Aligatueurite|Impergatornit",
              "드래곤스킨|Dragonize|ドラゴンスキン|Piel Dragontina|Peau Draconique|Drachenschicht"),
        .init("ampharosite", 181, 10045, ["electric", "dragon"], [90, 95, 105, 165, 110, 45],
              "전룡나이트|Ampharosite|デンリュウナイト|Ampharosita|Pharampite|Ampharosnit",
              "틀깨기|Mold Breaker|かたやぶり|Rompemoldes|Brise Moule|Überbrückung"),
        .init("steelixite", 208, 10072, ["steel", "ground"], [75, 125, 230, 55, 95, 30],
              "강철톤나이트|Steelixite|ハガネールナイト|Steelixita|Steelixite|Stahlosnit",
              "모래의힘|Sand Force|すなのちから|Poder Arena|Force Sable|Sandgewalt"),
        .init("scizorite", 212, 10046, ["bug", "steel"], [70, 150, 140, 65, 100, 75],
              "핫삼나이트|Scizorite|ハッサムナイト|Scizorita|Cizayoxite|Scheroxnit",
              "테크니션|Technician|テクニシャン|Experto|Technicien|Techniker"),
        .init("heracronite", 214, 10047, ["bug", "fighting"], [80, 185, 115, 40, 105, 75],
              "헤라크로스나이트|Heracronite|ヘラクロスナイト|Heracrossita|Scarhinoïte|Skarabornit",
              "스킬링크|Skill Link|スキルリンク|Encadenado|Multi-Coups|Wertelink"),
        .init("skarmorite", 227, 10284, ["steel", "flying"], [65, 140, 110, 40, 100, 110],
              "무장조나이트|Skarmorite|エアームドナイト|Skarmorita|Airmurite|Panzaeronit",
              "굳건한신념|Stalwart|すじがねいり|Acérrimo|Nerfs d’Acier|Stahlrückgrat"),
        .init("houndoominite", 229, 10048, ["dark", "fire"], [75, 90, 90, 140, 90, 115],
              "헬가나이트|Houndoominite|ヘルガナイト|Houndoomita|Démolossite|Hundemonit",
              "선파워|Solar Power|サンパワー|Poder Solar|Force Soleil|Solarkraft"),
        .init("tyranitarite", 248, 10049, ["rock", "dark"], [100, 164, 150, 95, 120, 71],
              "마기라스나이트|Tyranitarite|バンギラスナイト|Tyranitarita|Tyranocivite|Despotarnit",
              "모래날림|Sand Stream|すなおこし|Chorro Arena|Sable Volant|Sandsturm"),
        .init("sceptilite", 254, 10065, ["grass", "dragon"], [70, 110, 75, 145, 85, 145],
              "나무킹나이트|Sceptilite|ジュカインナイト|Sceptilita|Jungkite|Gewaldronit",
              "피뢰침|Lightning Rod|ひらいしん|Pararrayos|Paratonnerre|Blitzfänger"),
        .init("blazikenite", 257, 10050, ["fire", "fighting"], [80, 160, 80, 130, 80, 100],
              "번치코나이트|Blazikenite|バシャーモナイト|Blazikenita|Braségalite|Lohgocknit",
              "가속|Speed Boost|かそく|Impulso|Turbo|Temposchub"),
        .init("swampertite", 260, 10064, ["water", "ground"], [100, 150, 110, 95, 110, 70],
              "대짱이나이트|Swampertite|ラグラージナイト|Swampertita|Laggronite|Sumpexnit",
              "쓱쓱|Swift Swim|すいすい|Nado Rápido|Glissade|Wassertempo"),
        .init("gardevoirite", 282, 10051, ["psychic", "fairy"], [68, 85, 65, 165, 135, 100],
              "가디안나이트|Gardevoirite|サーナイトナイト|Gardevoirita|Gardevoirite|Guardevoirnit",
              "페어리스킨|Pixilate|フェアリースキン|Piel Feérica|Peau Féérique|Feenschicht"),
        .init("sablenite", 302, 10066, ["dark", "ghost"], [50, 85, 125, 85, 115, 20],
              "깜까미나이트|Sablenite|ヤミラミナイト|Sableynita|Ténéfixite|Zobirisnit",
              "매직미러|Magic Bounce|マジックミラー|Espejo Mágico|Miroir Magik|Magiespiegel"),
        .init("mawilite", 303, 10052, ["steel", "fairy"], [50, 105, 125, 55, 95, 50],
              "입치트나이트|Mawilite|クチートナイト|Mawilita|Mysdibulite|Flunkifernit",
              "천하장사|Huge Power|ちからもち|Potencia|Coloforce|Kraftkoloss"),
        .init("aggronite", 306, 10053, ["steel"], [70, 140, 230, 60, 80, 50],
              "보스로라나이트|Aggronite|ボスゴドラナイト|Aggronita|Galekingite|Stollossnit",
              "필터|Filter|フィルター|Filtro|Filtre|Filter"),
        .init("medichamite", 308, 10054, ["fighting", "psychic"], [60, 100, 85, 80, 85, 100],
              "요가램나이트|Medichamite|チャーレムナイト|Medichamita|Charminite|Meditalisnit",
              "순수한힘|Pure Power|ヨガパワー|Energía Pura|Force Pure|Mentalkraft"),
        .init("manectite", 310, 10055, ["electric"], [70, 75, 80, 135, 80, 135],
              "썬더볼트나이트|Manectite|ライボルトナイト|Manectricita|Élecsprintite|Voltensonit",
              "위협|Intimidate|いかく|Intimidación|Intimidation|Bedroher"),
        .init("sharpedonite", 319, 10070, ["water", "dark"], [70, 140, 70, 110, 65, 105],
              "샤크니아나이트|Sharpedonite|サメハダナイト|Sharpedonita|Sharpedite|Tohaidonit",
              "옹골찬턱|Strong Jaw|がんじょうあご|Mandíbula Fuerte|Prognathe|Titankiefer"),
        .init("cameruptite", 323, 10087, ["fire", "ground"], [70, 120, 100, 145, 105, 20],
              "폭타나이트|Cameruptite|バクーダナイト|Cameruptita|Caméruptite|Cameruptnit",
              "우격다짐|Sheer Force|ちからずく|Potencia Bruta|Sans Limite|Rohe Gewalt"),
        .init("altarianite", 334, 10067, ["dragon", "fairy"], [75, 110, 110, 110, 105, 80],
              "파비코리나이트|Altarianite|チルタリスナイト|Altarianita|Altarite|Altarianit",
              "페어리스킨|Pixilate|フェアリースキン|Piel Feérica|Peau Féérique|Feenschicht"),
        .init("banettite", 354, 10056, ["ghost"], [64, 165, 75, 93, 83, 75],
              "다크펫나이트|Banettite|ジュペッタナイト|Banettita|Branettite|Banetteonit",
              "짓궂은마음|Prankster|いたずらごころ|Bromista|Farceur|Strolch"),
        .init("chimechite", 358, 10306, ["psychic", "steel"], [75, 50, 110, 135, 120, 65],
              "치렁나이트|Chimechite|チリーンナイト|Chimechita|Éokite|Palimpalimonit",
              "부유|Levitate|ふゆう|Levitación|Lévitation|Schwebe"),
        .init("absolite", 359, 10057, ["dark"], [65, 150, 60, 115, 60, 115],
              "앱솔나이트|Absolite|アブソルナイト|Absolita|Absolite|Absolnit",
              "매직미러|Magic Bounce|マジックミラー|Espejo Mágico|Miroir Magik|Magiespiegel"),
        .init("absolite-z", 359, 10307, ["dark", "ghost"], [65, 154, 60, 75, 60, 151],
              "앱솔나이트Z|Absolite Z|アブソルナイトZ|Absolita Z|Absolite Z|Absolnit Z",
              "예리함|Sharpness|きれあじ|Cortante|Incisif|Scharfkantig"),
        .init("glalitite", 362, 10074, ["ice"], [80, 120, 80, 120, 80, 100],
              "얼음귀신나이트|Glalitite|オニゴーリナイト|Glalita|Oniglalite|Firnontornit",
              "프리즈스킨|Refrigerate|フリーズスキン|Piel Helada|Peau Gelée|Frostschicht"),
        .init("salamencite", 373, 10089, ["dragon", "flying"], [95, 145, 130, 120, 90, 120],
              "보만다나이트|Salamencite|ボーマンダナイト|Salamencita|Drattakite|Brutalandanit",
              "스카이스킨|Aerilate|スカイスキン|Piel Celeste|Peau Céleste|Zenithaut"),
        .init("metagrossite", 376, 10076, ["steel", "psychic"], [80, 145, 150, 105, 110, 110],
              "메타그로스나이트|Metagrossite|メタグロスナイト|Metagrossita|Métalossite|Metagrossnit",
              "단단한발톱|Tough Claws|かたいツメ|Garra Dura|Griffe Dure|Krallenwucht"),
        .init("latiasite", 380, 10062, ["dragon", "psychic"], [80, 100, 120, 140, 150, 110],
              "라티아스나이트|Latiasite|ラティアスナイト|Latiasita|Latiasite|Latiasnit",
              "부유|Levitate|ふゆう|Levitación|Lévitation|Schwebe"),
        .init("latiosite", 381, 10063, ["dragon", "psychic"], [80, 130, 100, 160, 120, 110],
              "라티오스나이트|Latiosite|ラティオスナイト|Latiosita|Latiosite|Latiosnit",
              "부유|Levitate|ふゆう|Levitación|Lévitation|Schwebe"),
        .init("staraptite", 398, 10308, ["fighting", "flying"], [85, 140, 100, 60, 90, 110],
              "찌르호크나이트|Staraptite|ムクホークナイト|Staraptorita|Étouraptorite|Staraptornit",
              "심술꾸러기|Contrary|あまのじゃく|Respondón|Contestation|Umkehrung"),
        .init("lopunnite", 428, 10088, ["normal", "fighting"], [65, 136, 94, 54, 96, 135],
              "이어롭나이트|Lopunnite|ミミロップナイト|Lopunnita|Lockpinite|Schlapornit",
              "배짱|Scrappy|きもったま|Intrépido|Querelleur|Rauflust"),
        .init("garchompite", 445, 10058, ["dragon", "ground"], [108, 170, 115, 120, 95, 92],
              "한카리아스나이트|Garchompite|ガブリアスナイト|Garchompita|Carchacrokite|Knakracknit",
              "모래의힘|Sand Force|すなのちから|Poder Arena|Force Sable|Sandgewalt"),
        .init("garchompite-z", 445, 10309, ["dragon"], [108, 130, 85, 141, 85, 151],
              "한카리아스나이트Z|Garchompite Z|ガブリアスナイトZ|Garchompita Z|Carchacrokite Z|Knakracknit Z",
              "부유|Levitate|ふゆう|Levitación|Lévitation|Schwebe"),
        .init("lucarionite", 448, 10059, ["fighting", "steel"], [70, 145, 88, 140, 70, 112],
              "루카리오나이트|Lucarionite|ルカリオナイト|Lucarita|Lucarite|Lucarionit",
              "적응력|Adaptability|てきおうりょく|Adaptable|Adaptabilité|Anpassung"),
        .init("lucarionite-z", 448, 10310, ["fighting", "steel"], [70, 100, 70, 164, 70, 151],
              "루카리오나이트Z|Lucarionite Z|ルカリオナイトZ|Lucarita Z|Lucarite Z|Lucarionit Z",
              "Aura Guard|Aura Guard|Aura Guard|Aura Guard|Aura Guard|Aura Guard"),
        .init("abomasite", 460, 10060, ["grass", "ice"], [90, 132, 105, 132, 105, 30],
              "눈설왕나이트|Abomasite|ユキノオナイト|Abomasnowita|Blizzarite|Rexblisarnit",
              "눈퍼뜨리기|Snow Warning|ゆきふらし|Nevada|Alerte Neige|Hagelalarm"),
        .init("galladite", 475, 10068, ["psychic", "fighting"], [68, 165, 95, 65, 115, 110],
              "엘레이드나이트|Galladite|エルレイドナイト|Galladita|Gallamite|Galagladinit",
              "정신력|Inner Focus|せいしんりょく|Fuerza Mental|Attention|Konzentrator"),
        .init("froslassite", 478, 10285, ["ice", "ghost"], [70, 80, 70, 140, 100, 120],
              "눈여아나이트|Froslassite|ユキメノコナイト|Froslassita|Momartikite|Frosdedjenit",
              "눈퍼뜨리기|Snow Warning|ゆきふらし|Nevada|Alerte Neige|Hagelalarm"),
        .init("heatranite", 485, 10311, ["fire", "steel"], [91, 120, 106, 175, 141, 67],
              "히드런나이트|Heatranite|ヒードラナイト|Heatranita|Heatranite|Heatranit",
              ""),
        .init("darkranite", 491, 10312, ["dark"], [70, 120, 130, 165, 130, 85],
              "다크라이나이트|Darkranite|ダークライナイト|Darkrainita|Darkraïte|Darkrainit",
              ""),
        .init("emboarite", 500, 10286, ["fire", "fighting"], [110, 148, 75, 110, 110, 75],
              "염무왕나이트|Emboarite|エンブオナイト|Emboarita|Roitiflamite|Flambirexonit",
              "틀깨기|Mold Breaker|かたやぶり|Rompemoldes|Brise Moule|Überbrückung"),
        .init("excadrite", 530, 10287, ["ground", "steel"], [110, 165, 100, 65, 65, 103],
              "몰드류나이트|Excadrite|ドリュウズナイト|Excadrillita|Minotaupite|Stalobornit",
              "관통드릴|Piercing Drill|かんつうドリル|Turbotaladro|Transperceuse|Stichbohrer"),
        .init("audinite", 531, 10069, ["normal", "fairy"], [103, 60, 126, 80, 126, 50],
              "다부니나이트|Audinite|タブンネナイト|Audinita|Nanméouïte|Ohrdochnit",
              "치유의마음|Healer|いやしのこころ|Alma Cura|Cœur Soin|Heilherz"),
        .init("scolipite", 545, 10288, ["bug", "poison"], [60, 140, 149, 75, 99, 62],
              "펜드라나이트|Scolipite|ペンドラナイト|Scolipedita|Brutapodite|Cerapendranit",
              "조가비갑옷|Shell Armor|シェルアーマー|Caparazón|Coque Armure|Panzerhaut"),
        .init("scraftinite", 560, 10289, ["dark", "fighting"], [65, 130, 135, 55, 135, 68],
              "곤율거니나이트|Scraftinite|ズルズキナイト|Scraftita|Baggaïdite|Irokexonit",
              "위협|Intimidate|いかく|Intimidación|Intimidation|Bedroher"),
        .init("eelektrossite", 604, 10290, ["electric"], [85, 145, 80, 135, 90, 80],
              "저리더프나이트|Eelektrossite|シビルドナイト|Eelektrossita|Ohmassacrite|Zapplarangonit",
              "Eelevate|Eelevate|Eelevate|Eelevate|Eelevate|Eelevate"),
        .init("chandelurite", 609, 10291, ["ghost", "fire"], [60, 75, 110, 175, 110, 90],
              "샹델라나이트|Chandelurite|シャンデラナイト|Chandelurita|Lugulabrite|Skelabranit",
              "틈새포착|Infiltrator|すりぬけ|Allanamiento|Infiltration|Schwebedurch"),
        .init("golurkite", 623, 10313, ["ground", "ghost"], [89, 159, 105, 70, 105, 55],
              "골루그나이트|Golurkite|ゴルーグナイト|Golurkita|Golemastokite|Golgantesnit",
              "보이지않는주먹|Unseen Fist|ふかしのこぶし|Puño Invisible|Poing Invisible|Verborgene Faust"),
        .init("chesnaughtite", 652, 10292, ["grass", "fighting"], [88, 137, 172, 74, 115, 44],
              "브리가론나이트|Chesnaughtite|ブリガロナイト|Chesnaughtita|Blindépiquite|Brigaronit",
              "방탄|Bulletproof|ぼうだん|Antibalas|Pare-Balles|Kugelsicher"),
        .init("delphoxite", 655, 10293, ["fire", "psychic"], [75, 69, 72, 159, 125, 134],
              "마폭시나이트|Delphoxite|マフォクシナイト|Delphoxita|Goupelinite|Fennexisnit",
              "부유|Levitate|ふゆう|Levitación|Lévitation|Schwebe"),
        .init("greninjite", 658, 10294, ["water", "dark"], [72, 125, 77, 133, 81, 142],
              "개굴닌자나이트|Greninjite|ゲッコウガナイト|Greninjanita|Amphinolite|Quajutsunit",
              "변환자재|Protean|へんげんじざい|Mutatipo|Protéen|Wandlungskunst"),
        .init("pyroarite", 668, 10295, ["fire", "normal"], [86, 88, 92, 129, 86, 126],
              "화염레오나이트|Pyroarite|カエンジシナイト|Pyroarita|Néméliosite|Pyroleonit",
              "Fire Mane|Fire Mane|Fire Mane|Fire Mane|Fire Mane|Fire Mane"),
        .init("floettite", 670, 10296, ["fairy"], [74, 85, 87, 155, 148, 102],
              "플라베베나이트|Floettite|フラエッテナイト|Floettita|Floettite|Floetteonit",
              "페어리오라|Fairy Aura|フェアリーオーラ|Aura Feérica|Aura Féérique|Feenaura"),
        .init("meowsticite", 678, 10314, ["psychic"], [74, 48, 76, 143, 101, 124],
              "냐오닉스나이트|Meowsticite|ニャオニクスナイト|Meowsticita|Mistigrixite|Psiaugonit",
              "트레이스|Trace|トレース|Calco|Calque|Erfassen"),
        .init("malamarite", 687, 10297, ["dark", "psychic"], [86, 102, 88, 98, 120, 88],
              "칼라마네로나이트|Malamarite|カラマネナイト|Malamarita|Sepiatrocite|Calamaneronit",
              "심술꾸러기|Contrary|あまのじゃく|Respondón|Contestation|Umkehrung"),
        .init("barbaracite", 689, 10298, ["rock", "fighting"], [72, 140, 130, 64, 106, 88],
              "거북손데스나이트|Barbaracite|ガメノデスナイト|Barbaraclita|Golgopathite|Thanathoranit",
              "단단한발톱|Tough Claws|かたいツメ|Garra Dura|Griffe Dure|Krallenwucht"),
        .init("dragalgite", 691, 10299, ["poison", "dragon"], [65, 85, 105, 132, 163, 44],
              "드래캄나이트|Dragalgite|ドラミドナイト|Dragalgita|Kravarekite|Tandraknit",
              "재생력|Regenerator|さいせいりょく|Regeneración|Régé-Force|Belebekraft"),
        .init("hawluchanite", 701, 10300, ["fighting", "flying"], [78, 137, 100, 74, 93, 118],
              "루차불나이트|Hawluchanite|ルチャブルナイト|Hawluchanita|Brutalibrite|Resladeronit",
              "노가드|No Guard|ノーガード|Indefenso|Annule Garde|Schildlos"),
        .init("zygardite", 718, 10301, ["dragon", "ground"], [216, 70, 91, 216, 85, 100],
              "지가르데나이트|Zygardite|ジガルデナイト|Zygardita|Zygardite|Zygardenit",
              ""),
        .init("diancite", 719, 10075, ["rock", "fairy"], [50, 160, 110, 160, 110, 110],
              "디안시나이트|Diancite|ディアンシナイト|Diancita|Diancite|Diancienit",
              "매직미러|Magic Bounce|マジックミラー|Espejo Mágico|Miroir Magik|Magiespiegel"),
        .init("crabominite", 740, 10315, ["fighting", "ice"], [97, 157, 122, 62, 107, 33],
              "모단단게나이트|Crabominite|ケケンカニナイト|Crabominablita|Crabominablite|Krawellonit",
              "철주먹|Iron Fist|てつのこぶし|Puño Férreo|Poing de Fer|Eisenfaust"),
        .init("golisopite", 768, 10316, ["bug", "steel"], [75, 150, 175, 70, 120, 40],
              "갑주무사나이트|Golisopite|グソクムシャナイト|Golisopodita|Sarmuraïte|Tectassnit",
              "단단한발톱|Tough Claws|かたいツメ|Garra Dura|Griffe Dure|Krallenwucht"),
        .init("drampanite", 780, 10302, ["normal", "dragon"], [78, 85, 110, 160, 116, 36],
              "할비롱나이트|Drampanite|ジジーロナイト|Drampanita|Draïeulite|Sen-Longnit",
              "발끈|Berserk|ぎゃくじょう|Cólera|Folle Furie|Wutausbruch"),
        .init("magearnite", 801, 10317, ["steel", "fairy"], [80, 125, 115, 170, 115, 95],
              "마기아나이트|Magearnite|マギアナイト|Magearnita|Magearnite|Magearnanit",
              ""),
        .init("zeraorite", 807, 10319, ["electric"], [88, 157, 75, 147, 80, 153],
              "제라오라나이트|Zeraorite|ゼラオラナイト|Zeraoranita|Zeraorite|Zeraoranit",
              ""),
        .init("falinksite", 870, 10303, ["fighting"], [65, 135, 135, 70, 65, 100],
              "대여르나이트|Falinksite|タイレーツナイト|Falinksita|Hexadronite|Legiosnit",
              "오기|Defiant|まけんき|Competitivo|Acharné|Siegeswille"),
        .init("scovillainite", 952, 10320, ["grass", "fire"], [65, 138, 85, 138, 85, 75],
              "스코빌런나이트|Scovillainite|スコヴィラナイト|Scovillainita|Scovilainite|Halupenjonit",
              "하바네로분출|Spicy Spray|とびだすハバネロ|Salpicante|Habanéruption|Chilispritzer"),
        .init("glimmoranite", 970, 10321, ["rock", "poison"], [83, 90, 105, 150, 96, 101],
              "킬라플로르나이트|Glimmoranite|キラフロルナイト|Glimmoranita|Floréclatite|Lumifloranit",
              "적응력|Adaptability|てきおうりょく|Adaptable|Adaptabilité|Anpassung"),
        .init("tatsugirinite", 978, 10322, ["dragon", "water"], [68, 65, 90, 135, 125, 92],
              "싸리용나이트|Tatsugirinite|シャリタツナイト|Tatsugirita|Nigirigonite|Nigiraginit",
              ""),
        .init("baxcalibrite", 998, 10325, ["dragon", "ice"], [115, 175, 117, 105, 101, 87],
              "드닐레이브나이트|Baxcalibrite|セグレイブナイト|Baxcaliburita|Glaivodite|Espinodonit",
              "열교환|Thermal Exchange|ねつこうかん|Termoconversión|Thermodynamique|Thermowandel"),
    ]
}
