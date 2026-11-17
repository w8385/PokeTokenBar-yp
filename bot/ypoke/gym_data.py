"""The PvE trainers: original characters, none taken from any game or show.

Every row is `(name ko, en, ja, line ko, en, ja)`. A region has eight gym leaders, four Elite Four members, a
champion and a villain organization (its name and grunt line, an admin and a boss). Types are the focus of each
trainer's team; the champion has none.
"""

GYM_TYPES = {
    "kanto": ("water", "poison", "normal", "flying", "ground", "grass", "fire", "psychic"),
    "johto": ("water", "flying", "bug", "grass", "rock", "psychic", "normal", "ground"),
    "hoenn": ("water", "normal", "psychic", "grass", "dark", "bug", "flying", "rock"),
    "sinnoh": ("flying", "grass", "normal", "ground", "steel", "water", "ghost", "bug"),
    "unova": ("grass", "normal", "flying", "bug", "water", "dark", "fire", "fighting"),
    "kalos": ("fire", "grass", "normal", "rock", "dragon", "flying", "water", "fairy"),
    "alola": ("fighting", "fire", "ghost", "bug", "grass", "water", "normal", "fairy"),
    "galar": ("water", "normal", "ghost", "psychic", "dark", "ice", "electric", "dragon"),
    "paldea": ("dark", "psychic", "dragon", "fighting", "water", "ghost", "normal", "grass"),
}

ELITE_TYPES = {
    "kanto": ("bug", "fighting", "rock", "ice"),
    "johto": ("steel", "fire", "dark", "fairy"),
    "hoenn": ("ground", "fighting", "ghost", "dragon"),
    "sinnoh": ("electric", "dark", "ice", "fighting"),
    "unova": ("psychic", "steel", "electric", "ghost"),
    "kalos": ("fighting", "psychic", "dark", "ghost"),
    "alola": ("dragon", "flying", "rock", "steel"),
    "galar": ("grass", "bug", "rock", "fighting"),
    "paldea": ("electric", "steel", "fire", "fairy"),
}

ORG_TYPES = {
    "kanto": ("electric", "ghost"),
    "johto": ("poison", "electric"),
    "hoenn": ("steel", "fire"),
    "sinnoh": ("poison", "rock"),
    "unova": ("ground", "rock"),
    "kalos": ("steel", "electric"),
    "alola": ("dark", "poison"),
    "galar": ("ground", "steel"),
    "paldea": ("bug", "flying"),
}

LEADERS = {
    "kanto": (
        ("물결", "Rippa", "リッパ", "파도는 멈추지 않아. 너도 그래야 해.", "Waves never stop. Neither should you.", "波は止まらない。君もだ。"),
        ("독초", "Venn", "ヴェン", "한 방울이면 충분하지.", "One drop is plenty.", "一滴で十分さ。"),
        ("한결", "Hal", "ハル", "평범함이 가장 단단해.", "Ordinary is the hardest thing to break.", "ふつうが一番かたいんだ。"),
        ("새벽", "Aeron", "エアロン", "높이 나는 쪽이 먼저 본다.", "The higher flier sees first.", "高く飛ぶ者が先に見る。"),
        ("자갈", "Dunn", "ダン", "발밑부터 단단히 다져.", "Pack the ground under you first.", "足元から固めなさい。"),
        ("새싹", "Fennel", "フェンネル", "천천히 자라서 크게 이겨.", "Grow slow, win big.", "ゆっくり育って、大きく勝つ。"),
        ("불씨", "Kade", "ケイド", "작은 불씨도 숲을 태워.", "A spark can burn a forest.", "火花ひとつで森も燃える。"),
        ("가온", "Oriel", "オリエル", "네 다음 수는 이미 읽었어.", "I read your next move already.", "君の次の手は読んでいる。"),
    ),
    "johto": (
        ("소나기", "Brine", "ブライン", "깊이를 모르면 빠진다.", "Not knowing the depth is how you drown.", "深さを知らないと溺れるよ。"),
        ("제비", "Pike", "パイク", "바람을 읽는 자가 이긴다.", "Whoever reads the wind wins.", "風を読む者が勝つ。"),
        ("반딧불", "Lumo", "ルーモ", "밤길은 내가 밝혀 주지.", "I light the night road.", "夜道は僕が照らすよ。"),
        ("대숲", "Cane", "ケイン", "휘어질지언정 꺾이지 않아.", "I bend but never break.", "しなっても折れない。"),
        ("돌탑", "Cairn", "ケルン", "쌓은 만큼 무너지지 않는다.", "What I stack does not fall.", "積んだ分だけ崩れない。"),
        ("달무리", "Selva", "セルヴァ", "점괘가 네 패배를 말하네.", "The omens say you lose.", "占いは君の負けと出ている。"),
        ("동백", "Winnow", "ウィノー", "기본기가 다 이긴다.", "Fundamentals win it all.", "基本がすべてに勝つ。"),
        ("두렁", "Furrow", "ファロー", "땅은 거짓말을 안 해.", "The earth doesn't lie.", "大地は嘘をつかない。"),
    ),
    "hoenn": (
        ("산호", "Coralis", "コラリス", "바다는 넓고 나는 깊어.", "The sea is wide and I run deep.", "海は広く、私は深い。"),
        ("나루", "Ames", "エイムズ", "정직한 한 방이 최고지.", "An honest hit is the best hit.", "正直な一撃が一番さ。"),
        ("별헤", "Quill", "クイル", "별자리에 네 이름은 없다.", "Your name isn't among the stars.", "星座に君の名前はない。"),
        ("야자", "Palma", "パルマ", "햇볕은 공짜, 승리는 아니지.", "Sun is free; victory isn't.", "日差しはタダ、勝利はタダじゃない。"),
        ("그믐", "Nocturn", "ノクターン", "달 없는 밤이 제일 편해.", "I'm most at home on a moonless night.", "月のない夜が一番落ち着く。"),
        ("물방개", "Skitter", "スキッター", "발이 빠른 놈이 오래 산다.", "The quick-legged live longest.", "足の速いやつが長生きする。"),
        ("갈매기", "Rennick", "レニック", "바다 위에선 내가 길이야.", "Over the sea, I am the road.", "海の上では私が道しるべだ。"),
        ("갯바위", "Skerry", "スケリー", "파도가 쳐도 난 그대로야.", "Waves hit me; I stay put.", "波が打っても俺は動かない。"),
    ),
    "sinnoh": (
        ("고갯마루", "Corrie", "コリー", "산 위 바람은 매서워.", "The wind up the pass is fierce.", "峠の風は容赦ないよ。"),
        ("이끼", "Tolliver", "トリヴァー", "서두르면 미끄러져.", "Hurry and you'll slip.", "急ぐと滑るよ。"),
        ("마을지기", "Dell", "デル", "우리 동네는 내가 지켜.", "I look after this town.", "この町は私が守る。"),
        ("광부", "Hobb", "ホブ", "파 내려가면 다 드러나지.", "Dig deep enough and it all shows.", "掘り下げれば全部見える。"),
        ("무쇠", "Tuck", "タック", "쇠는 불평 안 해. 너도 그래.", "Steel doesn't complain. Neither should you.", "鉄は文句を言わない。君もな。"),
        ("호숫가", "Lakeley", "レイクリー", "잔잔할 때가 제일 깊어.", "Still water runs deepest.", "静かな時こそ深い。"),
        ("넋", "Lorn", "ローン", "여긴 오래된 이야기가 많아.", "This place has many old stories.", "ここには古い話がたくさんある。"),
        ("나방", "Mothe", "モース", "빛을 따라오면 길을 잃지.", "Follow the light and you get lost.", "光を追えば道に迷う。"),
    ),
    "unova": (
        ("옥상정원", "Pax", "パックス", "도시에도 숲은 자라.", "Even a city grows a forest.", "街にも森は育つ。"),
        ("배달부", "Nye", "ナイ", "빠르고 정확하게, 그게 전부야.", "Fast and exact. That's all.", "速く正確に。それがすべてだ。"),
        ("고가도로", "Reeve", "リーヴ", "다리 위에선 내가 먼저 본다.", "On the bridge I see first.", "橋の上では私が先に見る。"),
        ("하루살이", "Mayfly", "メイフライ", "하루면 충분해. 널 이기는 데.", "One day's enough to beat you.", "一日あれば十分。君に勝つのにね。"),
        ("분수대", "Fount", "ファウント", "솟아오르면 못 막아.", "Once I surge, you can't stop me.", "湧き上がったら止められないよ。"),
        ("뒷골목", "Cray", "クレイ", "정면승부는 취미 없어.", "I'm not into fair fights.", "正面勝負は趣味じゃない。"),
        ("용접", "Weld", "ウェルド", "불꽃 튀는 게 내 일이야.", "Making sparks fly is my job.", "火花を散らすのが俺の仕事だ。"),
        ("격투장", "Dax", "ダックス", "링 위에선 다 평등해.", "Everyone's equal in the ring.", "リングの上では皆平等だ。"),
    ),
    "kalos": (
        ("화덕", "Sear", "シア", "센 불에 빨리 끝내자.", "High heat, finish fast.", "強火で手早く終わらせよう。"),
        ("허브", "Sorrel", "ソレル", "향기에 취하면 늦어.", "Drunk on the scent, too late.", "香りに酔ったら手遅れよ。"),
        ("제빵사", "Lune", "リュンヌ", "갓 구운 승부, 어때?", "A fresh-baked match, how's that?", "焼きたての勝負はどう？"),
        ("조각가", "Ardent", "アーデント", "깎아낼수록 본모습이 나오지.", "Chip away and the truth appears.", "削るほど本当の姿が現れる。"),
        ("비룡", "Solenne", "ソレンヌ", "용의 춤은 우아하고 잔혹해.", "The dragon's dance is graceful and cruel.", "竜の舞は優雅で残酷よ。"),
        ("연", "Valmont", "ヴァルモン", "구름 위 풍경을 보여 줄게.", "Let me show you the view above the clouds.", "雲の上の景色を見せてあげる。"),
        ("화가", "Aquarelle", "アクアレル", "번지는 색처럼 스며들어.", "I seep in like spreading color.", "にじむ色のように染み込むわ。"),
        ("리본", "Frill", "フリル", "예쁜 건 강해. 증명해 줄게.", "Pretty things are strong. Watch.", "かわいいものは強いの。見せてあげる。"),
    ),
    "alola": (
        ("씨름꾼", "Koa", "コア", "정정당당히 한판 붙자!", "Let's have a fair fight!", "正々堂々一本勝負だ！"),
        ("횃불", "Makana", "マカナ", "불춤을 구경하고 가.", "Stay and watch the fire dance.", "ファイアダンスを見ていきな。"),
        ("등불", "Pua", "プア", "축제의 밤엔 누가 따라올지 몰라.", "On festival night, who knows who follows you.", "祭りの夜は誰がついてくるかわからないよ。"),
        ("나비", "Nohea", "ノヘア", "꽃 사이를 날아다니는 게 내 일.", "Fluttering between flowers is my job.", "花から花へ舞うのが私の仕事。"),
        ("고사리", "Frond", "フロンド", "숲은 우리 둘을 다 품어.", "The forest holds us both.", "森は私たち二人を包む。"),
        ("파도타기", "Swell", "スウェル", "큰 파도를 기다렸어!", "I've been waiting for a big wave!", "大きな波を待ってたんだ！"),
        ("모래사장", "Tamarind", "タマリンド", "느긋하게, 근데 방심은 금물.", "Take it easy, but don't let your guard down.", "のんびりいこう、でも油断は禁物。"),
        ("꽃목걸이", "Anuenue", "アヌエヌエ", "환영해요, 그리고 잘 가요.", "Welcome. And goodbye.", "ようこそ。そして、さようなら。"),
    ),
    "galar": (
        ("수영선수", "Lane", "レーン", "기록은 깨라고 있는 거야.", "Records are made to be broken.", "記録は破るためにある。"),
        ("골키퍼", "Dobbs", "ドブス", "한 골도 못 넣게 해 주마.", "You won't score a single goal.", "一点も入れさせない。"),
        ("빈 경기장", "Hollis", "ホリス", "텅 빈 관중석에서 박수가 들려.", "I hear applause from empty stands.", "空っぽの客席から拍手が聞こえる。"),
        ("감독", "Quist", "クイスト", "작전은 이미 짜 놨어.", "The tactics are already set.", "作戦はもう組んである。"),
        ("반칙왕", "Rook", "ルーク", "심판이 안 보면 반칙 아니야.", "If the ref doesn't see it, it's no foul.", "審判が見てなきゃ反則じゃない。"),
        ("빙판", "Rink", "リンク", "미끄러지지 않게 조심해.", "Careful not to slip.", "滑らないように気をつけてね。"),
        ("전광판", "Lumen", "ルーメン", "점수판이 켜졌다, 시작이야!", "The scoreboard's lit. Let's go!", "スコアボードが点いた、始めよう！"),
        ("마스코트", "Roar", "ロア", "관중석이 다 내 편이야!", "The whole stand is on my side!", "客席は全部私の味方だ！"),
    ),
    "paldea": (
        ("문제아", "Vik", "ヴィク", "교칙? 그게 뭐였더라.", "School rules? What were those.", "校則？何だっけそれ。"),
        ("수학자", "Sigma", "シグマ", "정답은 이미 나와 있어.", "The answer's already worked out.", "答えはもう出ている。"),
        ("산맥", "Rhodri", "ロドリ", "내 용은 다루기 까다로워.", "My dragon is hard to handle.", "私の竜は扱いが難しいわよ。"),
        ("체육", "Rally", "ラリー", "수업 시작, 엎드려!", "Class begins—get down!", "授業開始、伏せ！"),
        ("뱃사공", "Ferrule", "フェルール", "물길은 내가 제일 잘 알지.", "I know the waterways best.", "水路は私が一番よく知ってる。"),
        ("도서관", "Maud", "モード", "금서는 읽는 순간 널 읽어.", "A forbidden book reads you as you read it.", "禁書は読んだ瞬間に君を読む。"),
        ("매점 주인", "Biscuit", "ビスケット", "배불리 먹고 싸우자고!", "Eat up, then fight!", "たらふく食べて戦おう！"),
        ("식물학", "Ilex", "アイレックス", "교과서에 없는 걸 가르쳐 줄게.", "I'll teach you what's not in the textbook.", "教科書にないことを教えてあげる。"),
    ),
}

ELITE = {
    "kanto": (
        ("메뚜기", "Pell", "ペル", "작다고 얕보면 물려.", "Small things bite hard.", "小さいからって侮ると噛まれるよ。"),
        ("주먹", "Tor", "トール", "말은 필요 없다. 덤벼라.", "No talk. Come at me.", "言葉はいらん。かかってこい。"),
        ("바위", "Holt", "ホルト", "산은 한 번도 물러난 적 없다.", "A mountain has never stepped back.", "山は一歩も退いたことがない。"),
        ("서리", "Rime", "ライム", "식을 때까지 기다려 줄게.", "I'll wait until you cool off.", "頭が冷えるまで待ってあげる。"),
    ),
    "johto": (
        ("쇠솥", "Greer", "グリア", "두드릴수록 단단해진다.", "Hit me and I only get harder.", "叩かれるほど固くなる。"),
        ("화로", "Hearth", "ハース", "마지막 불꽃까지 태워 주마.", "I'll burn you to the last spark.", "最後の火花まで燃やしてやる。"),
        ("그늘", "Corvin", "コルヴィン", "정정당당? 그건 지는 쪽이 하는 말이지.", "Fair play? That's what losers say.", "正々堂々？負ける側の台詞さ。"),
        ("꽃잠", "Pim", "ピム", "귀엽다고 봐주지 않아요.", "Cute doesn't mean easy.", "かわいくても手加減はしないわよ。"),
    ),
    "hoenn": (
        ("모래톱", "Shoal", "ショール", "한 걸음씩, 가라앉아라.", "Step by step. Sink.", "一歩ずつ沈んでいけ。"),
        ("정권", "Rourke", "ローク", "몸으로 배운 건 안 잊어.", "What the body learns, it keeps.", "体で覚えたことは忘れない。"),
        ("도깨비불", "Marrow", "マロウ", "밤에 혼자 걷지 마라.", "Don't walk alone at night.", "夜道を一人で歩くなよ。"),
        ("비늘", "Scalen", "スケイレン", "용은 부른다고 오지 않아. 찾아가는 거야.", "Dragons aren't called. They're sought.", "竜は呼んでも来ない。探しに行くものだ。"),
    ),
    "sinnoh": (
        ("벼락", "Thorne", "ソーン", "번쩍하고 끝나.", "One flash, and it's over.", "ピカッと一瞬で終わる。"),
        ("먹구름", "Gloam", "グローム", "빛이 닿지 않는 곳이 내 집이다.", "My home is where light can't reach.", "光の届かない場所が私の家だ。"),
        ("눈꽃", "Aske", "アスク", "눈이 쌓이면 발자국도 사라져.", "Snow piles up and tracks vanish.", "雪が積もれば足跡も消える。"),
        ("장작패기", "Hew", "ヒュー", "산사람 주먹이 제일 무겁지.", "A mountain man's fist hits hardest.", "山男の拳が一番重い。"),
    ),
    "unova": (
        ("관제탑", "Isen", "アイゼン", "모든 신호가 나에게 온다.", "Every signal reaches me.", "すべての信号が私に届く。"),
        ("철골", "Girder", "ガーダー", "무너지게 설계된 몸이 아니야.", "I wasn't built to collapse.", "崩れる設計ではない。"),
        ("변전소", "Gridley", "グリッドリー", "전압 올린다. 각오해.", "Raising the voltage. Brace yourself.", "電圧を上げる。覚悟しろ。"),
        ("폐역", "Terminus", "ターミナス", "마지막 열차는 이미 떠났어.", "The last train has already left.", "終電はもう出たよ。"),
    ),
    "kalos": (
        ("펜싱", "Foil", "フォイル", "찌르는 건 한 번이면 돼.", "One thrust is all I need.", "突きは一度でいい。"),
        ("시인", "Verse", "ヴァース", "다음 구절은 네 패배야.", "The next verse is your defeat.", "次の一節は君の敗北だ。"),
        ("복면", "Masque", "マスク", "얼굴을 가린 쪽이 더 솔직한 법.", "The masked are the honest ones.", "仮面の方が正直なものよ。"),
        ("초상화", "Mirelle", "ミレル", "그림 속에서 널 기다릴게.", "I'll wait for you in the painting.", "絵の中で待っているわ。"),
    ),
    "alola": (
        ("섬의 수호자", "Kaleo", "カレオ", "섬이 나를 단련시켰다.", "The island forged me.", "島が私を鍛えた。"),
        ("앨버트로스", "Manu", "マヌ", "섬 위의 하늘은 전부 내 거야.", "The sky above the islands is all mine.", "島の上の空はぜんぶ私のものよ。"),
        ("화산암", "Basalt", "バサルト", "내 단단함은 용암에서 났다.", "My hardness came from lava.", "俺の固さは溶岩生まれだ。"),
        ("닻", "Tane", "ターネ", "가라앉지도 흔들리지도 않아.", "I neither sink nor sway.", "沈みも揺れもしない。"),
    ),
    "galar": (
        ("잔디관리사", "Turf", "ターフ", "발밑 잔디를 얕보지 마.", "Don't underestimate the turf.", "足元の芝をなめるなよ。"),
        ("채집가", "Wick", "ウィック", "표본 상자에 한 자리 남았어.", "There's one slot left in my specimen box.", "標本箱にあと一つ空きがある。"),
        ("채석장", "Boyd", "ボイド", "발파 들어간다!", "Blasting now!", "発破いくぞ！"),
        ("코치", "Tamsin", "タムシン", "한 세트 더! 포기는 없다!", "One more set! No giving up!", "もう一セット！諦めるな！"),
    ),
    "paldea": (
        ("송신탑", "Relay", "リレー", "내 신호는 못 끊어.", "You can't cut my signal.", "私の信号は切れないわ。"),
        ("공대생", "Gauge", "ゲージ", "오차 범위는 0이야.", "Margin of error: zero.", "誤差の範囲はゼロよ。"),
        ("요리부", "Marlo", "マーロ", "화력은 전부 쏟는다!", "Full firepower!", "火力は全開だ！"),
        ("미술부", "Pastel", "パステル", "내 그림 속에서 길을 잃어 봐.", "Get lost in my painting.", "私の絵の中で迷ってみて。"),
    ),
}

CHAMPIONS = {
    "kanto": ("여울", "Idris", "イドリス", "여기까지 온 건 인정하지. 이제 진짜를 보여 줘.", "You made it here. Now show me the real thing.", "ここまで来たことは認めよう。本物を見せてくれ。"),
    "johto": ("한울", "Orlan", "オルラン", "오래된 종이 울린다. 이제 네 차례다.", "The old bell rings. It's your turn.", "古い鐘が鳴る。君の番だ。"),
    "hoenn": ("마파람", "Zephra", "ゼフラ", "내 바람을 타고 올라와 봐.", "Climb up on my wind.", "私の風に乗って上がってきなさい。"),
    "sinnoh": ("이랑", "Halvard", "ハルヴァルド", "정상까지 왔군. 나머지는 내가 맡지.", "You reached the summit. I'll take it from here.", "頂上まで来たか。あとは私が相手だ。"),
    "unova": ("마천루", "Aurelian", "アウレリアン", "이 도시의 꼭대기에 온 걸 환영한다.", "Welcome to the top of this city.", "この街の頂上へようこそ。"),
    "kalos": ("샹들리에", "Lustre", "ラスター", "화려한 무대의 끝에서 기다렸어.", "I've waited at the end of the grand stage.", "華やかな舞台の果てで待っていたわ。"),
    "alola": ("한낮", "Meridian", "メリディアン", "이 섬의 해가 가장 높이 뜬 곳에서 보자.", "Meet me where this island's sun is highest.", "この島の太陽が一番高い場所で会おう。"),
    "galar": ("트로피", "Laurel", "ローレル", "결승전에서 최고의 상대를 기다렸어.", "I waited in the final for the best opponent.", "決勝で最高の相手を待っていた。"),
    "paldea": ("졸업생", "Thessaly", "テッサリー", "마지막 시험이야. 만점을 노려 봐.", "Final exam. Go for a perfect score.", "最後の試験よ。満点を狙ってみて。"),
}

# The legendaries a region's champion fields, the first one as its finale.
CHAMPION_LEGENDARIES = {
    "kanto": (150, 145, 146),
    "johto": (250, 249, 245),
    "hoenn": (383, 382, 384),
    "sinnoh": (483, 484, 487),
    "unova": (643, 644, 646),
    "kalos": (716, 717, 718),
    "alola": (791, 792, 800),
    "galar": (888, 889, 890),
    "paldea": (1007, 1008, 1024),
}
PSEUDO_LEGENDARIES = {
    "kanto": (149,), "johto": (248,), "hoenn": (373, 376), "sinnoh": (445,), "unova": (635,), "kalos": (706,),
    "alola": (784,), "galar": (887,), "paldea": (998,),
}
FINALE_LINE = {
    "ko": "챔피언이 끝까지 숨겨 둔 마지막 파트너를 부른다!",
    "en": "The champion calls the last partner they kept hidden!",
    "ja": "チャンピオンが 最後まで 隠していた パートナーを 呼んだ！",
}

# (species id, held item, move ids) in battle order. Entries after the sixth are the finale: hidden from the preview,
# sent out once the first six have fainted.
CHAMPION_TEAMS = {
    "kanto": (
        (145, "focus-sash", (85, 413, 257, 851)),  # 썬더: 10만볼트, 브레이브버드, 열풍, 테라버스트
        (146, "life-orb", (315, 413, 815, 38)),  # 파이어: 오버히트, 브레이브버드, 열사의대지, 이판사판태클
        (149, "dragoninite", (200, 245, 89, 442)),  # 망나뇽: 역린, 신속, 지진, 아이언헤드
        (6, "charcoal", (315, 542, 89, 200)),  # 리자몽: 오버히트, 폭풍, 지진, 역린
        (94, "black-belt", (247, 482, 411, 412)),  # 팬텀: 섀도볼, 오물웨이브, 기합구슬, 에너지볼
        (130, "choice-band", (127, 242, 89, 200)),  # 갸라도스: 폭포오르기, 깨물어부수기, 지진, 역린
        (150, "choice-specs", (540, 126, 411, 58)),  # 뮤츠: 사이코브레이크, 불대문자, 기합구슬, 냉동빔
    ),
    "johto": (
        (249, "assault-vest", (94, 413, 89, 38)),  # 루기아: 사이코키네시스, 브레이브버드, 지진, 이판사판태클
        (245, "sitrus-berry", (57, 58, 247, 326)),  # 스이쿤: 파도타기, 냉동빔, 섀도볼, 신통력
        (248, "tyranitarite", (444, 492, 89, 200)),  # 마기라스: 스톤에지, 속임수, 지진, 역린
        (157, "focus-sash", (315, 89, 528, 583)),  # 블레이범: 오버히트, 지진, 와일드볼트, 치근거리기
        (212, "black-belt", (404, 442, 370, 814)),  # 핫삼: 시저크로스, 아이언헤드, 인파이트, 더블윙
        (181, "life-orb", (85, 411, 605, 408)),  # 전룡: 10만볼트, 기합구슬, 매지컬샤인, 파워젬
        (250, "choice-band", (221, 413, 89, 38)),  # 칠색조: 성스러운불꽃, 브레이브버드, 지진, 이판사판태클
    ),
    "hoenn": (
        (382, "choice-specs", (618, 58, 85, 38)),  # 가이오가: 근원의파동, 냉동빔, 10만볼트, 이판사판태클
        (384, "choice-band", (200, 620, 245, 89)),  # 레쿠쟈: 역린, 화룡점정, 신속, 지진
        (373, "salamencite", (200, 814, 89, 442)),  # 보만다: 역린, 더블윙, 지진, 아이언헤드
        (376, "soft-sand", (309, 706, 89, 359)),  # 메타그로스: 코멧펀치, 사이코팽, 지진, 암해머
        (257, "focus-sash", (394, 370, 413, 89)),  # 번치코: 플레어드라이브, 인파이트, 브레이브버드, 지진
        (282, "black-belt", (94, 585, 411, 412)),  # 가디안: 사이코키네시스, 문포스, 기합구슬, 에너지볼
        (383, "life-orb", (619, 444, 359, 315)),  # 그란돈: 단애의칼, 스톤에지, 암해머, 오버히트
    ),
    "sinnoh": (
        (484, "choice-specs", (57, 434, 126, 85)),  # 펄기아: 파도타기, 용성군, 불대문자, 10만볼트
        (487, "leftovers", (247, 200, 89, 442)),  # 기라티나: 섀도볼, 역린, 지진, 아이언헤드
        (445, "garchompite", (200, 89, 398, 38)),  # 한카리아스: 역린, 지진, 독찌르기, 이판사판태클
        (448, "black-belt", (370, 430, 89, 247)),  # 루카리오: 인파이트, 러스터캐논, 지진, 섀도볼
        (392, "focus-sash", (394, 370, 89, 441)),  # 초염몽: 플레어드라이브, 인파이트, 지진, 더스트슈트
        (468, "spell-tag", (605, 403, 396, 247)),  # 토게키스: 매지컬샤인, 에어슬래시, 파동탄, 섀도볼
        (483, "life-orb", (430, 434, 315, 414)),  # 디아루가: 러스터캐논, 용성군, 오버히트, 대지의힘
    ),
    "unova": (
        (644, "choice-band", (200, 550, 38, 242)),  # 제크로무: 역린, 뇌격, 이판사판태클, 깨물어부수기
        (646, "life-orb", (200, 58, 414, 430)),  # 큐레무: 역린, 냉동빔, 대지의힘, 러스터캐논
        (635, "focus-sash", (399, 434, 126, 430)),  # 삼삼드래: 악의파동, 용성군, 불대문자, 러스터캐논
        (609, "chandelurite", (247, 315, 412, 94)),  # 샹델라: 섀도볼, 오버히트, 에너지볼, 사이코키네시스
        (637, "charcoal", (405, 315, 202, 94)),  # 불카모스: 벌레의야단법석, 오버히트, 기가드레인, 사이코키네시스
        (530, "soft-sand", (89, 442, 404, 350)),  # 몰드류: 지진, 아이언헤드, 시저크로스, 록블라스트
        (643, "choice-specs", (434, 315, 414, 94)),  # 레시라무: 용성군, 오버히트, 대지의힘, 사이코키네시스
    ),
    "kalos": (
        (717, "choice-band", (492, 613, 411, 94)),  # 이벨타르: 속임수, 데스윙, 기합구슬, 사이코키네시스
        (718, "dragon-fang", (200, 89, 276, 482)),  # 지가르데: 역린, 지진, 엄청난힘, 오물웨이브
        (706, "choice-specs", (434, 126, 482, 438)),  # 미끄래곤: 용성군, 불대문자, 오물웨이브, 파워휩
        (658, "greninjite", (57, 399, 58, 482)),  # 개굴닌자: 파도타기, 악의파동, 냉동빔, 오물웨이브
        (663, "focus-sash", (394, 413, 211, 38)),  # 파이어로: 플레어드라이브, 브레이브버드, 강철날개, 이판사판태클
        (681, "assault-vest", (430, 247, 370, 457)),  # 킬가르도: 러스터캐논, 섀도볼, 인파이트, 양날박치기
        (716, "life-orb", (585, 370, 224, 94)),  # 제르네아스: 문포스, 인파이트, 메가혼, 사이코키네시스
    ),
    "alola": (
        (792, "choice-specs", (94, 714, 411, 58)),  # 루나아라: 사이코키네시스, 섀도레이, 기합구슬, 냉동빔
        (800, "life-orb", (722, 414, 404, 257)),  # 네크로즈마: 포톤가이저, 대지의힘, 시저크로스, 열풍
        (784, "dragon-fang", (200, 370, 89, 398)),  # 짜랑고우거: 역린, 인파이트, 지진, 독찌르기
        (727, "focus-sash", (394, 663, 370, 200)),  # 어흥염: 플레어드라이브, DD래리어트, 인파이트, 역린
        (730, "fairy-feather", (57, 585, 58, 94)),  # 누리레느: 파도타기, 문포스, 냉동빔, 사이코키네시스
        (778, "focus-band", (421, 583, 452, 409)),  # 따라큐: 섀도클로, 치근거리기, 우드해머, 드레인펀치
        (791, "choice-band", (706, 713, 370, 394)),  # 솔가레오: 사이코팽, 메테오드라이브, 인파이트, 플레어드라이브
    ),
    "galar": (
        (889, "choice-band", (370, 242, 444, 706)),  # 자마젠타: 인파이트, 깨물어부수기, 스톤에지, 사이코팽
        (890, "choice-specs", (482, 434, 126, 247)),  # 무한다이노: 오물웨이브, 용성군, 불대문자, 섀도볼
        (887, "focus-sash", (200, 247, 126, 38)),  # 드래펄트: 역린, 섀도볼, 불대문자, 이판사판태클
        (815, "silk-scarf", (394, 38, 442, 441)),  # 에이스번: 플레어드라이브, 이판사판태클, 아이언헤드, 더스트슈트
        (823, "assault-vest", (413, 442, 776, 38)),  # 아머까오: 브레이브버드, 아이언헤드, 바디프레스, 이판사판태클
        (849, "expert-belt", (85, 482, 586, 917)),  # 스트린더: 10만볼트, 오물웨이브, 폭음파, 사이코노이즈
        (888, "life-orb", (583, 370, 528, 706)),  # 자시안: 치근거리기, 인파이트, 와일드볼트, 사이코팽
    ),
    "paldea": (
        (1008, "choice-specs", (879, 434, 315, 430)),  # 미라이돈: 라이트닝드라이브, 용성군, 오버히트, 러스터캐논
        (1024, "focus-band", (906, 394, 89, 242)),  # 테라파고스: 테라클러스터, 플레어드라이브, 지진, 깨물어부수기
        (998, "baxcalibrite", (200, 333, 89, 442)),  # 드닐레이브: 역린, 고드름침, 지진, 아이언헤드
        (908, "life-orb", (572, 492, 583, 280)),  # 마스카나: 꽃보라, 속임수, 치근거리기, 깨뜨리다
        (911, "charcoal", (315, 247, 414, 200)),  # 라우드본: 오버히트, 섀도볼, 대지의힘, 역린
        (1000, "focus-sash", (874, 247, 85, 411)),  # 타부자고: 골드러시, 섀도볼, 10만볼트, 기합구슬
        (1007, "choice-band", (878, 200, 394, 442)),  # 코라이돈: 엑셀브레이크, 역린, 플레어드라이브, 아이언헤드
    ),
}

ORGS = {
    "kanto": (
        ("어둠전선", "The Dim Circuit", "ディム・サーキット", "불 꺼지면 우리 세상이야!", "Lights out is our time!", "明かりが消えたら俺たちの時間だ！"),
        ("퓨즈", "Fuse", "ヒューズ", "여기서부터는 정전이다.", "Power's out from here on.", "ここから先は停電だ。"),
        ("어스름", "Umbra Vex", "アンブラ・ヴェクス", "세상 불을 다 꺼 주마.", "I'll put out every light in the world.", "世界中の明かりを消してやる。"),
    ),
    "johto": (
        ("붉은 녹", "Red Rust", "レッドラスト", "녹슬 때까지 쓰고 버린다!", "Use it till it rusts, then toss it!", "錆びるまで使って捨てるのさ！"),
        ("녹청", "Patina", "パティナ", "여기서 끝이야. 반짝이는 건 다 낡아.", "End of the line. All that shines wears out.", "ここまでよ。光るものは皆すり減る。"),
        ("슬래그", "Orrick Slag", "オーリック・スラグ", "세상을 녹여 새로 부어 주지.", "I'll melt the world and pour it anew.", "世界を溶かして鋳直してやる。"),
    ),
    "hoenn": (
        ("단조회", "The Wrought Hand", "ロート・ハンド", "불꽃이 있는 곳에 돈이 있다!", "Where there's fire, there's money!", "炎のあるところに金がある！"),
        ("풀무", "Bellow", "ベロウ", "달궈진 쇠는 식기 전에 쳐야지.", "Strike while the iron is hot.", "熱いうちに打たねばな。"),
        ("불뫼", "Cinder Vael", "シンダー・ヴェイル", "내 손에 들어오면 뭐든 칼이 돼.", "In my hands, everything becomes a blade.", "私の手にかかれば何でも刃になる。"),
    ),
    "sinnoh": (
        ("캐내는 손", "The Deep Claim", "ディープ・クレイム", "이 땅 밑은 전부 우리 몫이다!", "Everything under this ground is ours!", "この地面の下は全部俺たちのものだ！"),
        ("갱도", "Adit", "アディット", "더 깊이 내려오면 못 올라가.", "Go deeper and you won't climb out.", "もっと深く降りたら上がれないぞ。"),
        ("광맥", "Brenn Lode", "ブレン・ロード", "이 산의 핏줄은 내가 쥐고 있다.", "I hold this mountain's veins.", "この山の血脈は私が握っている。"),
    ),
    "unova": (
        ("기초공사파", "Groundwork Crew", "グラウンドワーク一家", "허물고 다시 세우면 다 우리 돈이다!", "Tear it down, rebuild it, and it's all ours!", "壊して建て直せば全部俺たちの金だ！"),
        ("철근", "Rebar", "リバー", "서명했지? 이제 못 물러.", "You signed. No backing out now.", "署名したろ？もう引き返せないぜ。"),
        ("말뚝", "Piles Hardwick", "パイルズ・ハードウィック", "이 도시는 내 설계도 위에 서 있다.", "This city stands on my blueprint.", "この街は私の設計図の上に建っている。"),
    ),
    "kalos": (
        ("톱니불꽃회", "The Cogspark Club", "コグスパーク倶楽部", "발명품 시험대가 되어 줘!", "Be our test subject!", "発明品の実験台になってくれ！"),
        ("태엽", "Mainspring", "メインスプリング", "분해해서 어떻게 움직이는지 볼까?", "Shall I take you apart to see how you work?", "分解して仕組みを調べようか？"),
        ("공리", "Axiom Vane", "アクシオム・ヴェイン", "세상도 결국 거대한 기계일 뿐.", "The world is just one huge machine.", "世界もしょせん巨大な機械だ。"),
    ),
    "alola": (
        ("그을린 돛단", "Pitch Sail Company", "ピッチ・セイル商会", "배에 실린 건 다 우리 거야!", "Whatever's on the ship is ours!", "船に積んであるものは全部俺たちのものだ！"),
        ("타륜", "Helm", "ヘルム", "닻 올려라. 도망칠 곳은 없어.", "Anchors up. Nowhere to run.", "錨を上げろ。逃げ場はないぞ。"),
        ("갈고리", "Gaff Morrow", "ガフ・モロウ", "바다 위에선 내가 법이다.", "At sea, I am the law.", "海の上では俺が法だ。"),
    ),
    "galar": (
        ("폐철연합", "Scrapheap Union", "スクラップ・ユニオン", "버려진 건 줍는 사람이 임자!", "Finders keepers of anything thrown away!", "捨てられたものは拾った者のもんだ！"),
        ("집게", "Tongs", "トングス", "쓸모없다는 건 네 생각이지.", "'Useless' is just your opinion.", "役に立たないってのは君の思い込みだ。"),
        ("황동", "Brass Ketterman", "ブラス・ケターマン", "버린 건 전부 내 자산이다.", "Everything thrown away is my asset.", "捨てたものはすべて私の資産だ。"),
    ),
    "paldea": (
        ("윙윙단", "Buzzline Mob", "バズライン一味", "윙윙! 다 같이 덮쳐!", "Bzzz! Swarm 'em all!", "ブンブン！みんなで襲え！"),
        ("말벌", "Vespa", "ヴェスパ", "벌집을 건드렸네.", "You poked the hive.", "巣をつついたわね。"),
        ("여왕", "Apis", "アピス", "내 군단은 하늘을 가득 채운다.", "My swarm fills the whole sky.", "私の軍団は空を埋め尽くす。"),
    ),
}
