#!/usr/bin/env python3
"""Generate Sources/PokeTokenBar/Core/ItemLoreTable.swift from PokéAPI.

Run once whenever the item list changes (add the slug to ITEMS) and commit the result; the app never
fetches item text at runtime.

    python3 -I scripts/generate-item-lore.py

Official text: `item/{slug}` flavor_text_entries, newest version group per language.
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

# language key in the table -> PokéAPI language codes (lowercased)
LANGS = {"ko": ["ko"], "en": ["en"], "ja": ["ja-hrkt", "ja"], "es": ["es"], "fr": ["fr"], "de": ["de"]}

ITEMS = [
    "rare-candy", "shiny-charm",
    "fire-stone", "water-stone", "thunder-stone", "leaf-stone", "moon-stone",
    "sun-stone", "shiny-stone", "dusk-stone", "dawn-stone", "ice-stone",
    "leftovers", "choice-scarf", "choice-band", "focus-sash", "life-orb", "expert-belt", "charcoal",
    "linking-cord",
    "tart-apple", "sweet-apple", "syrupy-apple", "cracked-pot", "chipped-pot", "auspicious-armor",
    "malicious-armor", "galarica-cuff", "galarica-wreath", "unremarkable-teacup", "masterpiece-teacup",
    "metal-alloy", "peat-block", "black-augurite", "scroll-of-darkness", "scroll-of-waters",
    "oval-stone", "razor-claw", "razor-fang", "strawberry-sweet",
    "metal-coat", "kings-rock", "dragon-scale", "up-grade", "dubious-disc", "electirizer", "magmarizer",
    "protector", "reaper-cloth", "deep-sea-tooth", "deep-sea-scale", "sachet", "whipped-dream", "prism-scale",
]

# Items that are not in the games: hand-written in the same in-game voice, all eight app languages.
APP_ORIGINAL = {
    "app-mint": {
        "ko": "상쾌한 향이 나는 민트. 먹이면 포켓몬의 성격이 무작위로 바뀐다.",
        "en": "A mint with a refreshing scent. It changes a Pokémon's nature to a random one.",
        "ja": "さわやかな　かおりの　ミント。　あたえるとポケモンの　せいかくが　ランダムに　かわる。",
        "es": "Una menta de aroma fresco. Cambia la naturaleza de un Pokémon por otra al azar.",
        "fr": "Une menthe au parfum frais. Elle change la nature d'un Pokémon au hasard.",
        "pt": "Uma menta de aroma refrescante. Muda a natureza de um Pokémon para outra aleatória.",
        "de": "Eine Minze mit frischem Duft. Sie ändert das Wesen eines Pokémon zufällig.",
        "ru": "Мята со свежим ароматом. Случайным образом меняет характер покемона.",
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
}


def main():
    groups = get("version-group?limit=200")["results"]
    order = {g["name"]: i for i, g in enumerate(groups)}
    slugs = ITEMS + mega_slugs()
    with ThreadPoolExecutor(max_workers=4) as pool:
        fetched = dict(zip(slugs, pool.map(lambda s: fetch(s, order), slugs)))

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


def fetch(slug, order):
    data = get(f"item/{slug}")
    names = {n["language"]["name"].lower(): n["name"].strip() for n in data["names"]}
    entry = {"appOriginal": False, "name": {}, "text": {}, "group": {}}
    for key, codes in LANGS.items():
        for code in codes:
            if code in names:
                entry["name"][key] = names[code]
                break
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
