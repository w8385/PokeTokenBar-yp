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
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


if __name__ == "__main__":
    main()
