#!/usr/bin/env python3
"""Generate Sources/PokeTokenBar/Core/ItemLoreTable.swift from PokéAPI.

Run once whenever the item list changes (add the slug to ITEMS) and commit the result; the app never
fetches item text at runtime.

    python3 -I scripts/generate-item-lore.py

Official names come from `data/battle/items.json`; official text from `item/{slug}` flavor_text_entries, newest
version group per language.
PokéAPI has no pt or ru text, so those languages fall back to the English entry in the app.
APP_ORIGINAL holds the items that do not exist in the games, and MEGA_FALLBACK stands in for a Mega Stone
PokéAPI has no text for yet; both are flagged `appOriginal`.
"""
import json
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

API = "https://pokeapi.co/api/v2"
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources/PokeTokenBar/Core/ItemLoreTable.swift"
MEGA_SOURCE = ROOT / "Sources/PokeTokenBar/Core/MegaStones.swift"
BATTLE_ITEMS = ROOT / "data/battle/items.json"

# language key in the table -> PokéAPI language codes (lowercased)
LANGS = {"ko": ["ko"], "en": ["en"], "ja": ["ja-hrkt", "ja"], "es": ["es"], "fr": ["fr"], "de": ["de"]}

ITEMS = [
    "rare-candy", "shiny-charm", "exp-share",
    "fire-stone", "water-stone", "thunder-stone", "leaf-stone", "moon-stone",
    "sun-stone", "shiny-stone", "dusk-stone", "dawn-stone", "ice-stone",
    "leftovers", "choice-scarf", "choice-band", "focus-sash", "life-orb", "expert-belt", "charcoal",
    "everstone", "choice-specs", "assault-vest", "eviolite", "rocky-helmet", "sitrus-berry", "lum-berry",
    "white-herb", "black-sludge", "shell-bell", "big-root", "muscle-band", "wise-glasses", "scope-lens",
    "quick-claw", "bright-powder", "wide-lens", "weakness-policy", "focus-band", "flame-orb", "toxic-orb",
    "mystic-water", "miracle-seed", "magnet", "never-melt-ice", "black-belt", "poison-barb", "soft-sand",
    "sharp-beak", "twisted-spoon", "silver-powder", "hard-stone", "spell-tag", "dragon-fang", "black-glasses",
    "silk-scarf", "fairy-feather", "heat-rock", "damp-rock", "smooth-rock", "icy-rock",
    "teal-mask", "wellspring-mask", "hearthflame-mask", "cornerstone-mask",
    "linking-cord",
    "tart-apple", "sweet-apple", "syrupy-apple", "cracked-pot", "chipped-pot", "auspicious-armor",
    "malicious-armor", "galarica-cuff", "galarica-wreath", "unremarkable-teacup", "masterpiece-teacup",
    "metal-alloy", "peat-block", "black-augurite", "scroll-of-darkness", "scroll-of-waters",
    "oval-stone", "razor-claw", "razor-fang", "strawberry-sweet",
    "metal-coat", "kings-rock", "dragon-scale", "up-grade", "dubious-disc", "electirizer", "magmarizer",
    "protector", "reaper-cloth", "deep-sea-tooth", "deep-sea-scale", "sachet", "whipped-dream", "prism-scale",
    "red-orb", "blue-orb", "adamant-crystal", "lustrous-globe", "griseous-core", "punching-glove",
    "rusted-sword", "rusted-shield", "ultranecrozium-z--held",
    "occa-berry", "passho-berry", "wacan-berry", "rindo-berry", "yache-berry", "chople-berry", "kebia-berry",
    "shuca-berry", "coba-berry", "payapa-berry", "tanga-berry", "charti-berry", "kasib-berry", "haban-berry",
    "colbur-berry", "babiri-berry", "chilan-berry", "roseli-berry",
    "flame-plate", "splash-plate", "zap-plate", "meadow-plate", "icicle-plate", "fist-plate", "toxic-plate",
    "earth-plate", "sky-plate", "mind-plate", "insect-plate", "stone-plate", "spooky-plate", "draco-plate",
    "dread-plate", "iron-plate", "pixie-plate",
    "ability-capsule", "ability-patch", "bottle-cap", "gold-bottle-cap",
    "reveal-glass", "dna-splicers", "reins-of-unity", "mirror-herb",
]

# Items that are not in the games: hand-written in the same in-game voice, all eight app languages.
APP_ORIGINAL = {
    "app-mint": {
        "ko": "상쾌한 향이 나는 민트. 먹이면 포켓몬의 성격이 고른 성격으로 바뀐다.",
        "en": "A mint with a refreshing scent. It changes a Pokémon's nature to the one you choose.",
        "ja": "さわやかな　かおりの　ミント。　あたえるとポケモンの　せいかくが　えらんだ　せいかくに　かわる。",
        "es": "Una menta de aroma fresco. Cambia la naturaleza de un Pokémon por la que elijas.",
        "fr": "Une menthe au parfum frais. Elle change la nature d'un Pokémon pour celle de ton choix.",
        "pt": "Uma menta de aroma refrescante. Muda a natureza de um Pokémon para a que você escolher.",
        "de": "Eine Minze mit frischem Duft. Sie ändert das Wesen eines Pokémon in das gewählte.",
        "ru": "Мята со свежим ароматом. Меняет характер покемона на выбранный.",
    },
    # {pool} is replaced with the region name (or "National") when the text is looked up.
    "app-scout-ticket": {
        "ko": "{pool} 포켓몬 10마리를 보여 주는 스카우트 티켓. 마음에 드는 알 하나를 고를 수 있다.",
        "en": "A ticket for scouting. It shows 10 random {pool} Pokémon, and you pick the Egg you want.",
        "ja": "{pool}の　ポケモンを　10ぴき　みせてくれる　スカウトチケット。　ほしい　タマゴを　ひとつ　えらべる。",
        "es": "Un boleto de exploración. Muestra 10 Pokémon al azar de {pool} y permite elegir el huevo que quieras.",
        "fr": "Un ticket de recrutement. Il présente 10 Pokémon au hasard de {pool} et permet de choisir l'œuf voulu.",
        "pt": "Um bilhete de recrutamento. Mostra 10 Pokémon aleatórios de {pool} e permite escolher o ovo que quiser.",
        "de": "Ein Scouting-Ticket. Es zeigt 10 zufällige Pokémon aus {pool}, und man wählt das gewünschte Ei aus.",
        "ru": "Билет разведки. Показывает 10 случайных покемонов ({pool}), и можно выбрать нужное яйцо.",
    },
    "stellar-crystal": {
        "ko": "별이 총총한 밤하늘처럼 빛나는 결정. 테라파고스에게 지니게 하면 스텔라폼의 모습이 된다.",
        "en": "A crystal that glitters like a starry night sky. A Terapagos holding it takes its Stellar Form.",
        "ja": "ほしぞらのように　かがやく　けっしょう。　テラパゴスに　もたせると　ステラフォルムの　すがたになる。",
        "es": "Un cristal que centellea como un cielo estrellado. Un Terapagos que lo lleve adopta su Forma Astral.",
        "fr": "Un cristal qui scintille comme un ciel étoilé. Un Terapagos qui le tient prend sa Forme Stellaire.",
        "pt": "Um cristal que cintila como um céu estrelado. Um Terapagos que o segure assume a Forma Estelar.",
        "de": "Ein Kristall, der wie ein Sternenhimmel funkelt. Ein Terapagos, das ihn trägt, nimmt die Stellar-Form an.",
        "ru": "Кристалл, мерцающий, как звёздное небо. Терапагос, который его держит, принимает Звёздную форму.",
    },
}

# Mega Stones in the games that PokéAPI has no text for yet: the official wording, minus the species name.
MEGA_FALLBACK = {
    "ko": "대응하는 포켓몬에게 지니게 하면 배틀할 때 메가진화할 수 있는 신비한 메가스톤의 일종.",
    "en": "One of a variety of mysterious Mega Stones. Have the matching Pokémon hold it, and this stone will enable it to Mega Evolve during battle.",
    "ja": "たいおうする　ポケモンに　もたせておくと　たたかいのとき　メガシンカが　できる　ふしぎな　メガストーンの　いっしゅ。",
    "es": "Una de las misteriosas Megapiedras. Permite megaevolucionar en combate al Pokémon que corresponde si la lleva equipada.",
    "fr": "Une variété de Méga-Gemme. Tenue par le Pokémon concerné, elle lui permet de méga-évoluer durant un combat.",
    "pt": "Uma das misteriosas Mega Pedras. Se o Pokémon correspondente a segurar, ele poderá Mega Evoluir em batalha.",
    "de": "Einer der mysteriösen Mega-Steine. Wird er vom passenden Pokémon getragen, kann es im Kampf eine Mega-Entwicklung durchführen.",
    "ru": "Один из загадочных мега-камней. Подходящий покемон, который держит его, может мега-эволюционировать в бою.",
}


# Official text PokéAPI lacks, copied from a source that quotes the in-game text. Only the listed
# languages are official; the others come from NO_TEXT_YET and are flagged app-original.
OFFICIAL_MANUAL = {
    "linking-cord": {
        "source": "https://pokemondb.net/item/linking-cord (Legends: Arceus and Scarlet/Violet, identical text)",
        "texts": {
            "en": "A string exuding a mysterious energy that makes you feel a strange sense of connection. It’s loved by certain Pokémon.",
        },
    },
}

# Non-Mega items that exist in the games but have no flavor text in PokéAPI yet.
NO_TEXT_YET = {
    "linking-cord": {
        "ko": "신비한 끈. 사용하면 통신 교환으로 진화하는 포켓몬이 그 자리에서 진화한다.",
        "ja": "ふしぎな　ヒモ。　つかうと　つうしんこうかんで　しんかする　ポケモンが　その　ばで　しんかする。",
        "es": "Un cordón misterioso. Al usarlo, un Pokémon que evoluciona por intercambio evoluciona al instante.",
        "fr": "Un fil mystérieux. Utilisé, il fait évoluer aussitôt un Pokémon qui évolue par échange.",
        "pt": "Um cordão misterioso. Ao usá-lo, um Pokémon que evolui por troca evolui na hora.",
        "de": "Eine geheimnisvolle Schnur. Verwendet entwickelt sie ein Pokémon sofort, das sich durch Tausch entwickelt.",
        "ru": "Таинственный шнур. Если его применить, покемон, эволюционирующий обменом, эволюционирует сразу.",
    },
}

# Evolution items PokéAPI has names for but no flavor text yet: hand-written in the in-game voice, all eight
# languages, with the official name from PokéAPI. They are not flagged appOriginal because the item is real.
ITEM_FALLBACK = {
    "mirror-herb": {
        "ko": "흉내 내기를 돕는 신기한 허브. 먹은 포켓몬은 알에서만 배우는 기술을 익힐 수 있게 된다.",
        "en": "A curious herb that helps a Pokémon mimic others. One that eats it becomes able to learn the moves its kind learns only as an Egg.",
        "ja": "まねを　たすける　ふしぎな　ハーブ。たべた　ポケモンは　タマゴでしか　おぼえない　わざを　おぼえられるように　なる。",
        "es": "Una hierba curiosa que ayuda a imitar. El Pokémon que la come puede aprender los movimientos que su especie solo aprende como Huevo.",
        "fr": "Une herbe étrange qui aide à imiter. Le Pokémon qui la mange peut apprendre les capacités que son espèce n'apprend que dans l'Œuf.",
        "pt": "Uma erva curiosa que ajuda a imitar. O Pokémon que a come passa a aprender os golpes que sua espécie só aprende como Ovo.",
        "de": "Ein seltsames Kraut, das beim Nachahmen hilft. Ein Pokémon, das es frisst, kann Attacken erlernen, die seine Art nur als Ei lernt.",
        "ru": "Странная трава, помогающая подражать. Съевший её покемон может учить приёмы, которые его вид учит только в яйце.",
    },
    "fairy-feather": {
        "ko": "지니게 하면 페어리타입 기술의 위력이 올라가는 깃털.",
        "en": "An item to be held by a Pokémon. It is a feather that boosts the power of Fairy-type moves.",
        "ja": "もたせると　フェアリータイプの　わざの　いりょくが　あがる　ハネ。",
        "es": "Una pluma que potencia los movimientos de tipo Hada del Pokémon que la lleve.",
        "fr": "Une plume qui renforce la puissance des attaques de type Fée du Pokémon qui la tient.",
        "pt": "Uma pena que aumenta o poder dos golpes do tipo Fada do Pokémon que a segurar.",
        "de": "Eine Feder, die die Stärke von Feen-Attacken des Trägers erhöht.",
        "ru": "Перо, повышающее силу атак типа «Фея» у покемона, который его держит.",
    },
    "syrupy-apple": {
        "ko": "시럽이 가득 배어든 사과. 어떤 포켓몬에게 주면 진화한다.",
        "en": "A very syrupy apple. A certain Pokémon evolves when it is given this apple.",
        "ja": "シロップが　たっぷり　しみこんだ　リンゴ。あるポケモンに　あたえると　しんかする。",
        "es": "Una manzana empapada de sirope. Cierto Pokémon evoluciona si se le da esta manzana.",
        "fr": "Une pomme gorgée de sirop. Un certain Pokémon évolue si on la lui donne.",
        "pt": "Uma maçã encharcada de xarope. Certo Pokémon evolui ao receber esta maçã.",
        "de": "Ein Apfel, der vor Sirup trieft. Ein bestimmtes Pokémon entwickelt sich, wenn es ihn bekommt.",
        "ru": "Яблоко, пропитанное сиропом. Некоторый покемон эволюционирует, если ему его дать.",
    },
    "auspicious-armor": {
        "ko": "상서로운 기운이 감도는 갑옷. 어떤 포켓몬에게 주면 진화한다.",
        "en": "Armor brimming with an auspicious aura. A certain Pokémon evolves when it is given this armor.",
        "ja": "めでたい　オーラが　ただよう　よろい。あるポケモンに　あたえると　しんかする。",
        "es": "Una armadura que rebosa un aura de buen augurio. Cierto Pokémon evoluciona si se le da esta armadura.",
        "fr": "Une armure qui déborde d'une aura de bon augure. Un certain Pokémon évolue si on la lui donne.",
        "pt": "Uma armadura repleta de uma aura auspiciosa. Certo Pokémon evolui ao receber esta armadura.",
        "de": "Eine Rüstung voller glückverheißender Aura. Ein bestimmtes Pokémon entwickelt sich, wenn es sie bekommt.",
        "ru": "Доспехи, наполненные благоприятной аурой. Некоторый покемон эволюционирует, если ему их дать.",
    },
    "malicious-armor": {
        "ko": "악의가 감도는 갑옷. 어떤 포켓몬에게 주면 진화한다.",
        "en": "Armor brimming with a malicious aura. A certain Pokémon evolves when it is given this armor.",
        "ja": "あくいが　ただよう　よろい。あるポケモンに　あたえると　しんかする。",
        "es": "Una armadura que rebosa un aura maliciosa. Cierto Pokémon evoluciona si se le da esta armadura.",
        "fr": "Une armure qui déborde d'une aura malveillante. Un certain Pokémon évolue si on la lui donne.",
        "pt": "Uma armadura repleta de uma aura maliciosa. Certo Pokémon evolui ao receber esta armadura.",
        "de": "Eine Rüstung voller böser Aura. Ein bestimmtes Pokémon entwickelt sich, wenn es sie bekommt.",
        "ru": "Доспехи, наполненные злой аурой. Некоторый покемон эволюционирует, если ему их дать.",
    },
    "unremarkable-teacup": {
        "ko": "별다를 것 없는 평범한 찻잔. 어떤 포켓몬이 깃들면 진화한다.",
        "en": "An unremarkable, ordinary-looking teacup. A certain Pokémon evolves when it takes up residence in it.",
        "ja": "とくに　かわったところの　ない　ふつうの　ちゃわん。あるポケモンが　やどると　しんかする。",
        "es": "Una taza de té corriente y sin nada especial. Cierto Pokémon evoluciona si se instala en ella.",
        "fr": "Une tasse à thé ordinaire, sans rien de remarquable. Un certain Pokémon évolue s'il s'y installe.",
        "pt": "Uma xícara de chá comum, sem nada de especial. Certo Pokémon evolui ao se instalar nela.",
        "de": "Eine gewöhnliche, unscheinbare Teetasse. Ein bestimmtes Pokémon entwickelt sich, wenn es sich darin einnistet.",
        "ru": "Обычная, ничем не примечательная чайная чашка. Некоторый покемон эволюционирует, если поселится в ней.",
    },
    "masterpiece-teacup": {
        "ko": "정교하게 만들어진 걸작 찻잔. 어떤 포켓몬이 깃들면 진화한다.",
        "en": "A masterpiece of a teacup, exquisitely made. A certain Pokémon evolves when it takes up residence in it.",
        "ja": "せいこうに　つくられた　けっさくの　ちゃわん。あるポケモンが　やどると　しんかする。",
        "es": "Una taza de té que es una obra maestra, de factura exquisita. Cierto Pokémon evoluciona si se instala en ella.",
        "fr": "Une tasse à thé qui est un chef-d'œuvre, d'une facture exquise. Un certain Pokémon évolue s'il s'y installe.",
        "pt": "Uma xícara de chá que é uma obra-prima, feita com requinte. Certo Pokémon evolui ao se instalar nela.",
        "de": "Eine meisterhaft gefertigte Teetasse. Ein bestimmtes Pokémon entwickelt sich, wenn es sich darin einnistet.",
        "ru": "Чайная чашка-шедевр, изысканной работы. Некоторый покемон эволюционирует, если поселится в ней.",
    },
    "metal-alloy": {
        "ko": "신기한 금속 합금. 어떤 포켓몬이 이 합금에 닿으면 진화한다.",
        "en": "A peculiar metal alloy. A certain Pokémon evolves when it is exposed to this alloy.",
        "ja": "ふしぎな　きんぞくの　ごうきん。あるポケモンが　ふれると　しんかする。",
        "es": "Una extraña aleación de metales. Cierto Pokémon evoluciona si se expone a esta aleación.",
        "fr": "Un étrange alliage métallique. Un certain Pokémon évolue s'il y est exposé.",
        "pt": "Uma estranha liga metálica. Certo Pokémon evolui ao ser exposto a esta liga.",
        "de": "Eine seltsame Metalllegierung. Ein bestimmtes Pokémon entwickelt sich, wenn es ihr ausgesetzt wird.",
        "ru": "Необычный металлический сплав. Некоторый покемон эволюционирует, если подвергнется его воздействию.",
    },
    "peat-block": {
        "ko": "신비한 에너지가 가득한 이탄 덩어리. 어떤 포켓몬이 이 덩어리에 닿으면 진화한다.",
        "en": "A block of peat brimming with mysterious energy. A certain Pokémon evolves when it is exposed to this block.",
        "ja": "ふしぎな　エネルギーに　みちた　でいたんの　かたまり。あるポケモンが　ふれると　しんかする。",
        "es": "Un bloque de turba lleno de energía misteriosa. Cierto Pokémon evoluciona si se expone a este bloque.",
        "fr": "Un bloc de tourbe plein d'énergie mystérieuse. Un certain Pokémon évolue s'il y est exposé.",
        "pt": "Um bloco de turfa repleto de energia misteriosa. Certo Pokémon evolui ao ser exposto a este bloco.",
        "de": "Ein Torfblock voll geheimnisvoller Energie. Ein bestimmtes Pokémon entwickelt sich, wenn es ihm ausgesetzt wird.",
        "ru": "Брикет торфа, полный таинственной энергии. Некоторый покемон эволюционирует, если подвергнется его воздействию.",
    },
    "black-augurite": {
        "ko": "검게 빛나는 신기한 광물. 어떤 포켓몬이 이 광물에 닿으면 진화한다.",
        "en": "A peculiar black mineral that gleams. A certain Pokémon evolves when it is exposed to this mineral.",
        "ja": "くろく　かがやく　ふしぎな　こうぶつ。あるポケモンが　ふれると　しんかする。",
        "es": "Un extraño mineral negro y brillante. Cierto Pokémon evoluciona si se expone a este mineral.",
        "fr": "Un étrange minéral noir et brillant. Un certain Pokémon évolue s'il y est exposé.",
        "pt": "Um estranho mineral preto e reluzente. Certo Pokémon evolui ao ser exposto a este mineral.",
        "de": "Ein seltsames, schwarz glänzendes Mineral. Ein bestimmtes Pokémon entwickelt sich, wenn es ihm ausgesetzt wird.",
        "ru": "Необычный блестящий чёрный минерал. Некоторый покемон эволюционирует, если подвергнется его воздействию.",
    },
    "scroll-of-darkness": {
        "ko": "악의 탑의 가르침이 적힌 두루마리. 어떤 포켓몬이 읽으면 진화한다.",
        "en": "A scroll that records the teachings of the Tower of Darkness. A certain Pokémon evolves when it studies it.",
        "ja": "あくのとうの　おしえが　かかれた　まきもの。あるポケモンが　よむと　しんかする。",
        "es": "Un pergamino con las enseñanzas de la Torre Oscura. Cierto Pokémon evoluciona si lo estudia.",
        "fr": "Un parchemin consignant les enseignements de la Tour Obscure. Un certain Pokémon évolue s'il l'étudie.",
        "pt": "Um pergaminho com os ensinamentos da Torre da Escuridão. Certo Pokémon evolui ao estudá-lo.",
        "de": "Eine Schriftrolle mit den Lehren des Turms der Finsternis. Ein bestimmtes Pokémon entwickelt sich, wenn es sie studiert.",
        "ru": "Свиток с учением Башни Тьмы. Некоторый покемон эволюционирует, если изучит его.",
    },
    "scroll-of-waters": {
        "ko": "물의 탑의 가르침이 적힌 두루마리. 어떤 포켓몬이 읽으면 진화한다.",
        "en": "A scroll that records the teachings of the Tower of Waters. A certain Pokémon evolves when it studies it.",
        "ja": "みずのとうの　おしえが　かかれた　まきもの。あるポケモンが　よむと　しんかする。",
        "es": "Un pergamino con las enseñanzas de la Torre Agua. Cierto Pokémon evoluciona si lo estudia.",
        "fr": "Un parchemin consignant les enseignements de la Tour d'Eau. Un certain Pokémon évolue s'il l'étudie.",
        "pt": "Um pergaminho com os ensinamentos da Torre da Água. Certo Pokémon evolui ao estudá-lo.",
        "de": "Eine Schriftrolle mit den Lehren des Wasserturms. Ein bestimmtes Pokémon entwickelt sich, wenn es sie studiert.",
        "ru": "Свиток с учением Башни Воды. Некоторый покемон эволюционирует, если изучит его.",
    },
    "teal-mask": {
        "ko": "오거폰이 쓰는 벽록색 가면. 지니게 하면 모습이 풀타입 그대로 빛난다.",
        "en": "A teal mask that Ogerpon wears. When held by Ogerpon, it shines in its pure Grass-type form.",
        "ja": "オーガポンが　つける　みどりいろの　おめん。　もたせると　くさタイプの　すがたで　かがやく。",
        "es": "Una máscara turquesa que lleva Ogerpon. Si la lleva Ogerpon, brilla en su forma de tipo Planta.",
        "fr": "Un masque turquoise que porte Ogerpon. Tenu par Ogerpon, il brille sous sa forme de type Plante.",
        "pt": "Uma máscara verde-azulada usada por Ogerpon. Quando Ogerpon a segura, brilha em sua forma do tipo Planta.",
        "de": "Eine türkisfarbene Maske, die Ogerpon trägt. Hält Ogerpon sie, strahlt es in seiner reinen Pflanze-Form.",
        "ru": "Бирюзовая маска, которую носит Огерпон. Если её держит Огерпон, он сияет в форме типа «Трава».",
    },
    "wellspring-mask": {
        "ko": "오거폰이 쓰는 우물색 가면. 지니게 하면 풀과 물타입의 모습으로 빛난다.",
        "en": "A mask in the colors of a wellspring that Ogerpon wears. When held by Ogerpon, it shines in a Grass- and Water-type form.",
        "ja": "オーガポンが　つける　いどいろの　おめん。　もたせると　くさと　みずタイプの　すがたで　かがやく。",
        "es": "Una máscara con los colores de un manantial que lleva Ogerpon. Si la lleva Ogerpon, brilla en una forma de tipo Planta y Agua.",
        "fr": "Un masque aux couleurs d'une source que porte Ogerpon. Tenu par Ogerpon, il brille sous une forme de type Plante et Eau.",
        "pt": "Uma máscara nas cores de uma nascente usada por Ogerpon. Quando Ogerpon a segura, brilha em uma forma dos tipos Planta e Água.",
        "de": "Eine Maske in den Farben einer Quelle, die Ogerpon trägt. Hält Ogerpon sie, strahlt es in einer Pflanze-Wasser-Form.",
        "ru": "Маска цветов родника, которую носит Огерпон. Если её держит Огерпон, он сияет в форме типов «Трава» и «Вода».",
    },
    "hearthflame-mask": {
        "ko": "오거폰이 쓰는 화덕색 가면. 지니게 하면 풀과 불꽃타입의 모습으로 빛난다.",
        "en": "A mask in the colors of a hearth fire that Ogerpon wears. When held by Ogerpon, it shines in a Grass- and Fire-type form.",
        "ja": "オーガポンが　つける　かまどいろの　おめん。　もたせると　くさと　ほのおタイプの　すがたで　かがやく。",
        "es": "Una máscara con los colores de un hogar encendido que lleva Ogerpon. Si la lleva Ogerpon, brilla en una forma de tipo Planta y Fuego.",
        "fr": "Un masque aux couleurs d'un foyer que porte Ogerpon. Tenu par Ogerpon, il brille sous une forme de type Plante et Feu.",
        "pt": "Uma máscara nas cores de uma lareira usada por Ogerpon. Quando Ogerpon a segura, brilha em uma forma dos tipos Planta e Fogo.",
        "de": "Eine Maske in den Farben eines Herdfeuers, die Ogerpon trägt. Hält Ogerpon sie, strahlt es in einer Pflanze-Feuer-Form.",
        "ru": "Маска цветов очага, которую носит Огерпон. Если её держит Огерпон, он сияет в форме типов «Трава» и «Огонь».",
    },
    "cornerstone-mask": {
        "ko": "오거폰이 쓰는 주춧돌색 가면. 지니게 하면 풀과 바위타입의 모습으로 빛난다.",
        "en": "A mask in the colors of a cornerstone that Ogerpon wears. When held by Ogerpon, it shines in a Grass- and Rock-type form.",
        "ja": "オーガポンが　つける　いしずえいろの　おめん。　もたせると　くさと　いわタイプの　すがたで　かがやく。",
        "es": "Una máscara con los colores de una piedra angular que lleva Ogerpon. Si la lleva Ogerpon, brilla en una forma de tipo Planta y Roca.",
        "fr": "Un masque aux couleurs d'une pierre angulaire que porte Ogerpon. Tenu par Ogerpon, il brille sous une forme de type Plante et Roche.",
        "pt": "Uma máscara nas cores de uma pedra angular usada por Ogerpon. Quando Ogerpon a segura, brilha em uma forma dos tipos Planta e Pedra.",
        "de": "Eine Maske in den Farben eines Grundsteins, die Ogerpon trägt. Hält Ogerpon sie, strahlt es in einer Pflanze-Gestein-Form.",
        "ru": "Маска цветов краеугольного камня, которую носит Огерпон. Если её держит Огерпон, он сияет в форме типов «Трава» и «Камень».",
    },
    "adamant-crystal": {
        "ko": "디아루가가 지니면 오리진폼의 모습이 되는 크게 빛나는 옥. 강철과 드래곤타입 기술의 위력이 올라간다.",
        "en": "A large, glowing gem that lets Dialga change form when held. It boosts the power of Dialga’s Dragon- and Steel-type moves.",
        "ja": "ディアルガに　もたせると　オリジンフォルムの　すがたになる　おおきく　かがやく　たま。　はがねと　ドラゴンタイプの　わざの　いりょくが　あがる。",
        "es": "Una gran gema resplandeciente que permite a Dialga cambiar de forma si la lleva. Potencia sus movimientos de tipo Dragón y Acero.",
        "fr": "Un gros joyau brillant qui permet à Dialga de changer de forme s'il le tient. Augmente la puissance de ses capacités de type Dragon et Acier.",
        "pt": "Uma grande gema brilhante que faz Dialga mudar de forma ao segurá-la. Aumenta o poder dos golpes dos tipos Dragão e Aço de Dialga.",
        "de": "Ein großer, leuchtender Edelstein, der Dialga die Form wechseln lässt, wenn es ihn trägt. Verstärkt seine Drache- und Stahl-Attacken.",
        "ru": "Большой сияющий камень. Если его держит Диалга, он меняет форму, а его атаки типов «Дракон» и «Сталь» становятся сильнее.",
    },
    "lustrous-globe": {
        "ko": "펄기아가 지니면 오리진폼의 모습이 되는 크게 빛나는 옥. 물과 드래곤타입 기술의 위력이 올라간다.",
        "en": "A large, glowing gem that lets Palkia change form when held. It boosts the power of Palkia’s Dragon- and Water-type moves.",
        "ja": "パルキアに　もたせると　オリジンフォルムの　すがたになる　おおきく　かがやく　たま。　みずと　ドラゴンタイプの　わざの　いりょくが　あがる。",
        "es": "Una gran gema resplandeciente que permite a Palkia cambiar de forma si la lleva. Potencia sus movimientos de tipo Dragón y Agua.",
        "fr": "Un gros joyau brillant qui permet à Palkia de changer de forme s'il le tient. Augmente la puissance de ses capacités de type Dragon et Eau.",
        "pt": "Uma grande gema brilhante que faz Palkia mudar de forma ao segurá-la. Aumenta o poder dos golpes dos tipos Dragão e Água de Palkia.",
        "de": "Ein großer, leuchtender Edelstein, der Palkia die Form wechseln lässt, wenn es ihn trägt. Verstärkt seine Drache- und Wasser-Attacken.",
        "ru": "Большой сияющий камень. Если его держит Палкия, она меняет форму, а её атаки типов «Дракон» и «Вода» становятся сильнее.",
    },
    "griseous-core": {
        "ko": "기라티나가 지니면 오리진폼의 모습이 되는 크게 빛나는 옥. 고스트와 드래곤타입 기술의 위력이 올라간다.",
        "en": "A large, glowing gem that lets Giratina change form when held. It boosts the power of Giratina’s Dragon- and Ghost-type moves.",
        "ja": "ギラティナに　もたせると　オリジンフォルムの　すがたになる　おおきく　かがやく　たま。　ゴーストと　ドラゴンタイプの　わざの　いりょくが　あがる。",
        "es": "Una gran gema resplandeciente que permite a Giratina cambiar de forma si la lleva. Potencia sus movimientos de tipo Dragón y Fantasma.",
        "fr": "Un gros joyau brillant qui permet à Giratina de changer de forme s'il le tient. Augmente la puissance de ses capacités de type Dragon et Spectre.",
        "pt": "Uma grande gema brilhante que faz Giratina mudar de forma ao segurá-la. Aumenta o poder dos golpes dos tipos Dragão e Fantasma de Giratina.",
        "de": "Ein großer, leuchtender Edelstein, der Giratina die Form wechseln lässt, wenn es ihn trägt. Verstärkt seine Drache- und Geist-Attacken.",
        "ru": "Большой сияющий камень. Если его держит Гиратина, она меняет форму, а её атаки типов «Дракон» и «Призрак» становятся сильнее.",
    },
    "punching-glove": {
        "ko": "펀치를 보호하는 글러브. 지니게 하면 펀치 기술의 위력이 올라간다.",
        "en": "A protective glove. It boosts the power of the holder’s punching moves.",
        "ja": "パンチを　まもる　グローブ。　もたせると　パンチわざの　いりょくが　あがる。",
        "es": "Un guante protector. Potencia los movimientos de puño del portador.",
        "fr": "Un gant protecteur. Augmente la puissance des capacités de poing du porteur.",
        "pt": "Uma luva protetora. Aumenta o poder dos golpes de soco do portador.",
        "de": "Ein Schutzhandschuh. Verstärkt die Schlag-Attacken des Trägers.",
        "ru": "Защитная перчатка. Усиливает удары кулаком у того, кто её держит.",
    },
}


def main():
    groups = get("version-group?limit=200")["results"]
    order = {g["name"]: i for i, g in enumerate(groups)}
    slugs = ITEMS + mega_slugs()
    names = battle_names()
    unknown = [slug for slug in slugs if slug not in names]
    if unknown:
        sys.exit(f"not in {BATTLE_ITEMS.relative_to(ROOT)}, add it to the bot's generator: {', '.join(unknown)}")
    with ThreadPoolExecutor(max_workers=4) as pool:
        fetched = dict(zip(slugs, pool.map(lambda s: fetch(s, order, names[s]), slugs)))

    lines = [
        "// Generated by scripts/generate-item-lore.py from PokéAPI. Do not edit by hand.",
        "// Official text is the newest version group per language. pt and ru are absent and fall back to English.",
        "enum ItemLoreTable {",
        "    struct Entry {",
        "        /// Languages whose text is written for the app, not copied from the games.",
        "        let appOriginalLanguages: [String]",
        "        var appOriginal: Bool { !appOriginalLanguages.isEmpty }",
        "        /// Official item names, keyed by AppLanguage.rawValue. Empty for app-original items.",
        "        let names: [String: String]",
        "        let texts: [String: String]",
        "    }",
        "",
        "    static let entries: [String: Entry] = [",
    ]
    flagged = []
    for slug in slugs:
        e = fetched[slug]
        handwritten = []
        if not e["text"]:
            e["text"], handwritten = fill_missing(slug)
            flagged.append(slug)
        append_entry(lines, slug, handwritten, e["name"], e["text"])
    for slug, texts in APP_ORIGINAL.items():
        append_entry(lines, slug, list(texts), {}, texts)
    lines += ["    ]", "}", ""]
    OUT.write_text("\n".join(lines))
    print(f"wrote {OUT.relative_to(ROOT)} ({len(slugs) - len(flagged)} official, {len(flagged) + len(APP_ORIGINAL)} app-original)")
    if flagged:
        print("no PokéAPI text yet, using NO_TEXT_YET / MEGA_FALLBACK:", ", ".join(flagged), file=sys.stderr)


def fill_missing(slug):
    if slug in ITEM_FALLBACK:
        return ITEM_FALLBACK[slug], list(ITEM_FALLBACK[slug])
    if slug in OFFICIAL_MANUAL:
        official = OFFICIAL_MANUAL[slug]["texts"]
        texts = {**NO_TEXT_YET[slug], **official}
        return texts, [k for k in texts if k not in official]
    texts = NO_TEXT_YET.get(slug, MEGA_FALLBACK)
    return texts, list(texts)


def append_entry(lines, slug, app_languages, names, texts):
    listed = ", ".join(swift(k) for k in app_languages)
    lines.append(f"        {swift(slug)}: Entry(appOriginalLanguages: [{listed}],")
    lines.append("            names: [" + (", ".join(f"{swift(k)}: {swift(v)}" for k, v in names.items()) or ":") + "],")
    lines.append("            texts: [")
    for key, text in texts.items():
        lines.append(f"                {swift(key)}: {swift(text)},")
    lines.append("            ]),")


def fetch(slug, order, names):
    data = get(f"item/{slug}")
    entry = {"appOriginal": False, "name": {k: names[k] for k in LANGS if k in names}, "text": {}, "group": {}}
    for key, codes in LANGS.items():
        best = None
        for f in data["flavor_text_entries"]:
            code = f["language"]["name"].lower()
            if code not in codes:
                continue
            rank = (order[f["version_group"]["name"]], -codes.index(code))
            if best is None or rank > best[0]:
                best = (rank, clean(f["text"], key), f["version_group"]["name"])
        if best:
            entry["text"][key] = best[1]
            entry["group"][key] = best[2]
    return entry


def battle_names():
    """Item names by PokéAPI slug, from the bot's battle data."""
    entries = json.loads(BATTLE_ITEMS.read_text())
    return {entry.get("pokeapi", slug): entry["names"] for slug, entry in entries.items() if entry.get("pokeapi", slug)}


def mega_slugs():
    return re.findall(r'\.init\("([a-z0-9-]+)", \d+, \d+', MEGA_SOURCE.read_text())


def swift(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def clean(text, lang):
    text = text.replace("­", "").replace("\f", "\n")
    text = re.sub(r"[ \t]*\n[ \t]*", "　" if lang == "ja" else " ", text.strip())
    return re.sub(r" {2,}", " ", text)


def get(path):
    req = urllib.request.Request(f"{API}/{path}", headers={"User-Agent": "item-lore-generator"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except TimeoutError:
            if attempt == 3:
                raise


if __name__ == "__main__":
    main()
