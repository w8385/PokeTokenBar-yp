import ast
import hashlib
import json
import math
import os
import random
from dataclasses import MISSING, fields
from functools import cache
from pathlib import Path
from unittest import mock

import pytest

from ypoke import abilities, battle_data, gym_battle, gyms, items, move_effects, narration, pokeapi
from ypoke.battle import simulate
from ypoke.combatants import combatant
from ypoke.gym_battle import GymBattles
from ypoke.mega_stones import MEGA_STONES, PRIMAL_ORBS, ULTRA_BURSTS
from ypoke.upload_server import validate_members
from ypoke.move_effects import STATUS_MOVES

GOLDEN = Path(__file__).with_name("battle_golden.json")
SCENARIOS = 48
TYPES = ("normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground", "flying", "psychic",
         "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy")
STATS = ("hp", "attack", "defense", "special_attack", "special_defense", "speed")


def _move(move_id, name, kind, power, damage_class, accuracy=100, **extra):
    return {
        "id": move_id, "name": name, "type": kind, "power": power, "damage_class": damage_class, "accuracy": accuracy,
        "priority": 0, "pp": 15, "crit_rate": 0, "ailment": None, "ailment_chance": 0, "stat_changes": [],
        "stat_target": "target", "stat_chance": 0, "weather": None, "always_hits_in": [], "drain": 0, "min_hits": 1,
        "max_hits": 1, **extra,
    }


MOVE_POOL = [
    _move(14, "칼춤", "normal", 0, "status", None),
    _move(86, "전기자석파", "electric", 0, "status", 90, ailment="paralysis", ailment_chance=0),
    _move(281, "하품", "normal", 0, "status", None),
    _move(433, "트릭룸", "psychic", 0, "status", None, priority=-7),
    _move(446, "스텔스록", "rock", 0, "status", None),
    _move(369, "유턴", "bug", 70, "physical"),
    _move(521, "볼트체인지", "electric", 70, "special"),
    _move(812, "퀵턴", "water", 60, "physical"),
    _move(120, "자폭", "normal", 200, "physical"),
    _move(153, "대폭발", "normal", 250, "physical"),
    _move(449, "심판의뭉치", "normal", 100, "special"),
    _move(904, "덩굴몽둥이", "grass", 100, "physical", crit_rate=1),
    _move(620, "화룡점정", "flying", 120, "physical", stat_changes=[{"stat": "defense", "change": -1},
                                                               {"stat": "special_defense", "change": -1}],
          stat_target="user", stat_chance=100),
    _move(7, "불꽃펀치", "fire", 75, "physical", ailment="burn", ailment_chance=10),
    _move(9, "번개펀치", "electric", 75, "physical", ailment="paralysis", ailment_chance=10),
    _move(183, "마하펀치", "fighting", 40, "physical", priority=1),
    _move(409, "드레인펀치", "fighting", 75, "physical", drain=50),
    _move(223, "폭발펀치", "fighting", 100, "physical", 50, ailment="confusion", ailment_chance=100),
    _move(76, "솔라빔", "grass", 120, "special"),
    _move(167, "트리플킥", "fighting", 10, "physical", 90, min_hits=3, max_hits=3),
    _move(263, "객기", "normal", 70, "physical"),
    _move(279, "리벤지", "fighting", 60, "physical", priority=-4),
    _move(282, "탁쳐서떨구기", "dark", 65, "physical"),
    _move(284, "분화", "fire", 150, "special"),
    _move(311, "웨더볼", "normal", 50, "special"),
    _move(323, "해수스파우팅", "water", 150, "special"),
    _move(362, "소금물", "water", 65, "special"),
    _move(371, "보복", "dark", 50, "physical"),
    _move(419, "눈사태", "ice", 60, "physical", priority=-4),
    _move(474, "베놈쇼크", "poison", 65, "special"),
    _move(500, "어시스트파워", "psychic", 20, "special"),
    _move(506, "병상첨병", "ghost", 65, "special"),
    _move(512, "애크러뱃", "flying", 55, "physical"),
    _move(514, "원수갚기", "normal", 70, "physical"),
    _move(669, "솔라블레이드", "grass", 125, "physical"),
    _move(681, "죄업", "dark", 20, "physical"),
    _move(707, "분함의발구르기", "ground", 75, "physical"),
    _move(754, "전해부리", "electric", 85, "physical"),
    _move(755, "아가미물기", "water", 85, "physical"),
    _move(808, "분풀이", "dark", 75, "physical"),
    _move(813, "트리플악셀", "ice", 20, "physical", 90, min_hits=3, max_hits=3),
    _move(820, "드래곤에너지", "dragon", 150, "special"),
    _move(839, "독침천침", "poison", 60, "physical", ailment="poison", ailment_chance=50),
    _move(854, "성묘", "ghost", 50, "physical"),
    _move(876, "하이드로스팀", "water", 80, "special"),
    _move(878, "액셀브레이크", "fighting", 100, "physical"),
    _move(879, "이나즈마드라이브", "electric", 100, "special"),
    _move(889, "분노의주먹", "ghost", 50, "physical"),
    _move(915, "생떼", "fire", 75, "physical"),
    _move(241, "쾌청", "fire", 0, "status", None, weather="sun"),
    _move(240, "비바라기", "water", 0, "status", None, weather="rain"),
    _move(201, "모래바람", "rock", 0, "status", None, weather="sandstorm"),
    _move(258, "싸라기눈", "ice", 0, "status", None, weather="hail"),
    _move(883, "설경", "ice", 0, "status", None, weather="snow"),
    _move(87, "번개", "electric", 110, "special", 70, ailment="paralysis", ailment_chance=30, always_hits_in=["rain"]),
    _move(59, "눈보라", "ice", 110, "special", 70, ailment="freeze", ailment_chance=10, always_hits_in=["hail", "snow"]),
    _move(542, "폭풍", "flying", 110, "special", 70, ailment="confusion", ailment_chance=30, always_hits_in=["rain"]),
    _move(89, "지진", "ground", 100, "physical"),
    _move(85, "10만볼트", "electric", 90, "special", ailment="paralysis", ailment_chance=10),
    _move(53, "화염방사", "fire", 90, "special", ailment="burn", ailment_chance=10),
    _move(57, "파도타기", "water", 90, "special"),
    _move(58, "냉동빔", "ice", 90, "special", ailment="freeze", ailment_chance=10),
    _move(94, "사이코키네시스", "psychic", 90, "special", stat_changes=[{"stat": "special_defense", "change": -1}],
          stat_chance=10),
    _move(247, "섀도볼", "ghost", 80, "special"),
    _move(188, "오물폭탄", "poison", 90, "special", ailment="poison", ailment_chance=30),
    _move(444, "스톤에지", "rock", 100, "physical", 80, crit_rate=1),
    _move(370, "인파이트", "fighting", 120, "physical", stat_changes=[{"stat": "defense", "change": -1},
                                                               {"stat": "special_defense", "change": -1}],
          stat_target="user", stat_chance=100),
    _move(394, "플레어드라이브", "fire", 120, "physical", drain=-33, ailment="burn", ailment_chance=10),
    _move(331, "기관총", "grass", 25, "physical", min_hits=2, max_hits=5),
    _move(202, "기가드레인", "grass", 75, "special", drain=50),
    _move(332, "제비반환", "flying", 60, "physical", None),
    _move(406, "용의파동", "dragon", 85, "special"),
    _move(442, "아이언헤드", "steel", 80, "physical"),
    _move(605, "매지컬샤인", "fairy", 80, "special"),
]
POOL_IDS = [move["id"] for move in MOVE_POOL]
BOUND_ITEMS = {
    **{slug: species for slug, (species, _) in {**MEGA_STONES, **PRIMAL_ORBS, **ULTRA_BURSTS}.items()},
    "flame-plate": 493, "draco-plate": 493, "pixie-plate": 493,
    "teal-mask": 1017, "wellspring-mask": 1017, "hearthflame-mask": 1017, "cornerstone-mask": 1017,
    "stellar-crystal": 1024, "adamant-crystal": 483, "lustrous-globe": 484, "griseous-core": 487,
    "rusted-sword": 888, "rusted-shield": 889,
}
FREE_ITEMS = sorted(items.ITEM_NAMES) + ["everstone", "booster-energy", None]
ABILITY_POOL = sorted(abilities.NAMES) + ["run-away", "pressure", None]


def test_fixed_seed_battles_and_gym_teams_match_the_golden_record():
    assert _digests() == json.loads(GOLDEN.read_text())


@pytest.mark.skip(reason="run by hand to rewrite the golden record when battle behavior is meant to change")
def test_write_golden():
    GOLDEN.write_text(json.dumps(_digests(), indent=1) + "\n")


def _digests():
    return {"battles": [_digest(_battle_text(scenario)) for scenario in range(SCENARIOS)],
            "catalog": _digest(_catalog_text())}


def _battle_text(scenario):
    rng = random.Random(scenario)
    api = FakePokeAPI()
    sides = tuple(tuple(combatant(api, _member(rng, slot)) for slot in range(6)) for _ in range(2))
    result = simulate(sides, seed=scenario)
    card = narration.battle_card(("A", "B"), sides, result)
    return repr((sides, result, narration.battle_log(result), card))


def _catalog_text():
    opponents = [opponent for region in gyms.regions()
                 for opponent in (*region.gyms, *region.elite, *region.hideout, region.hidden)]
    members = {opponent.id: gyms.foe_members(opponent) for opponent in opponents}
    return json.dumps({"catalog": gyms.catalog(), "members": members}, sort_keys=True, ensure_ascii=False)


def _digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


class FakePokeAPI:
    def pokemon(self, pokemon_id):
        return _species_data(pokemon_id)

    def mega_form(self, pokemon_id):
        ability = ABILITY_POOL[pokemon_id % len(ABILITY_POOL)]
        return {**_species_data(pokemon_id), "ability_id": ability, "ability": abilities.NAMES.get(ability, ability)}

    def attacking_moves(self, pokemon_id, level, machine_ids=(), status=False):
        return [
            {**move, "level": 1, "source": "level"} for move in MOVE_POOL
            if move["weather"] or _attacks(move)
            or (status and move["id"] in STATUS_MOVES)
        ]

    def can_evolve(self, pokemon_id):
        return pokemon_id % 2 == 0


def _species_data(pokemon_id):
    first = TYPES[pokemon_id % len(TYPES)]
    second = TYPES[(pokemon_id * 7 + 3) % len(TYPES)]
    types = [first] if pokemon_id % 3 == 0 or second == first else [first, second]
    base = {stat: 50 + (pokemon_id * (index + 3) * 37) % 81 for index, stat in enumerate(STATS)}
    return {"name_ko": f"P{pokemon_id}", "types": types, "base": base, "weight": 10 + pokemon_id * 53 % 3000}


def _member(rng, slot):
    item = rng.choice(sorted(BOUND_ITEMS)) if slot % 3 == 0 else rng.choice(FREE_ITEMS)
    pokemon_id = BOUND_ITEMS[item] if item in BOUND_ITEMS and rng.random() < 0.8 else rng.randrange(1, 1026)
    if rng.random() < 0.1:
        pokemon_id = 384
    moves = rng.sample(POOL_IDS, 4)
    if rng.random() < 0.3:
        moves[0] = 620
    return {
        "pokemon_id": pokemon_id, "level": rng.randrange(40, 71), "shiny": False, "moves": moves,
        "ivs": {stat: rng.randrange(0, 32) for stat in STATS}, "held_item": item, "ability": rng.choice(ABILITY_POOL),
        "nature": rng.choice(("adamant", "modest", "jolly", "timid", None)),
    }


GOLDEN_DIR = Path(__file__).with_name("golden")
PVP_SCENARIOS = 160
PVP_PER_FILE = 40
GYM_PARTIES = 2
FOCUS_SEEDS = 8
# (side 0, side 1) as (pokemon_id, item, ability, moves) per member, for effects the walk above rarely reaches.
FOCUS_CASES = {
    "quick-claw": (((25, "quick-claw", None, [33, 98]), (133, "quick-claw", None, [33, 34]), (52, "quick-claw", None, [33])),
                   ((150, None, None, [33]), (151, None, None, [6]), (149, None, None, [33]))),
    "ailment-block": (((26, None, None, [609, 398]), (78, None, None, [517, 34]), (82, None, None, [192, 398])),
                      ((68, None, "limber", [33]), (89, None, "immunity", [33]), (131, None, "water-veil", [33]),
                       (143, None, "insomnia", [33]))),
    "guts-orbs": (((68, "flame-orb", "guts", [33, 263]), (214, "toxic-orb", "guts", [33, 263]), (217, "flame-orb", "guts", [263])),
                  ((95, "lum-berry", "static", [34, 609]), (113, "leftovers", "flame-body", [53]),
                   (34, "black-sludge", "poison-point", [398]))),
    "winds": (((150, None, None, [369, 33]), (384, None, "delta-stream", [33, 240])),
              ((6, None, None, [240, 241, 53, 58]), (9, None, None, [240, 57]))),
    "thaw": (((131, None, None, [58, 369]), (6, None, None, [53, 517])),
             ((3, "leftovers", None, [33]), (143, "sitrus-berry", None, [33]))),
    "veil-mist": (((5, "light-clay", "snow-warning", [694, 58]), (23, None, None, [54, 57])),
                  ((2, None, "infiltrator", [196, 53]), (20, None, None, [196]))),
    "gravity-terrain": (((8, "terrain-extender", "misty-surge", [356, 89]), (11, None, None, [281, 89])),
                        ((9, None, None, [86, 65]), (17, None, "levitate", [86, 85]), (27, None, None, [281, 17]))),
    "terrain-moves": (((8, None, "electric-surge", [804, 875]), (17, None, "psychic-surge", [797, 857]),
                       (20, None, "misty-surge", [802, 805])),
                      ((5, None, "grassy-surge", [803, 89]), (23, None, "grass-pelt", [798, 830]),
                       (2, None, "hadron-engine", [805, 85]))),
    "sand-force": (((9, None, "sand-force", [89, 65]),), ((5, None, "sand-stream", [58]), (23, None, None, [57]))),
    "hazards": (((54, None, None, [191, 390, 564, 446]), (36, "light-clay", None, [115, 113, 280]),
                 (18, None, None, [366, 432, 89])),
                ((18, None, None, [89]), (7, None, None, [866, 89]), (54, "heavy-duty-boots", "screen-cleaner",
                                                                         [756, 89]))),
    "boost-rest": (((143, None, None, [74, 156, 34]), (3, None, None, [74, 156, 75])),
                   ((68, None, None, [2, 7]), (59, None, None, [53, 44]))),
    "thaw-moves": (((131, None, None, [58]), (87, None, None, [58]), (124, None, None, [58])),
                   ((9, None, None, [503]), (134, None, None, [503, 815]), (1013, None, None, [902]))),
    "false-swipe": (((68, None, None, [206]),), ((65, None, None, [33]),)),
    "syrup-bomb": (((25, None, None, [903]),), ((143, None, None, [33]),)),
    "rage": (((56, None, None, [99]),), ((143, None, None, [33]),)),
    "stone-axe": (((900, None, None, [830]),), ((143, None, None, [33]),)),
    "sappy-seed": (((1, None, None, [738]),), ((143, None, None, [33]),)),
    "assist": (((52, None, None, [274]), (25, None, None, [85])), ((143, None, None, [33]),)),
    "baton-pass": (((133, None, None, [14, 226, 33]), (143, None, None, [33])), ((143, None, None, [33]),)),
    "focus-energy": (((56, None, None, [116, 33]),), ((143, None, None, [33]),)),
    "stuff-cheeks": (((819, "sitrus-berry", None, [747, 33]),), ((143, None, None, [33]),)),
    "contact": (((25, None, None, [370]), (68, "protective-pads", None, [370]), (724, None, "long-reach", [370]),
                 (3, None, None, [447, 89])),
                ((143, "rocky-helmet", "static", [33]),)),
    "contact-sash": (((908, "focus-sash", None, [870]),), ((143, "rocky-helmet", None, [776]),)),
    "clear-smog": (((89, None, None, [499]),), ((143, None, None, [14, 33]),)),
    "mega-order": (((398, "staraptite", "intimidate", [370]),), ((6, "charizardite-y", "intimidate", [53, 33]),)),
    "contrary": (((213, None, "contrary", [14, 370]),), ((143, None, "intimidate", [45, 555]),)),
    "stockpile": (((80, None, None, [254, 255]), (79, None, None, [880]), (25, None, None, [33])),
                  ((143, None, None, [33]),)),
    "fell-stinger": (((212, None, None, [565]),), ((10, None, None, [33]),)),
    "switcheroo": (((94, None, None, [415, 33]),), ((143, "leftovers", None, [33]),)),
    "imposter": (((25, None, None, [85]), (132, None, "imposter", [144])), ((6, "charizardite-x", None, [53, 33]),)),
    "protean": (((908, None, "protean", [583, 870]),), ((484, None, None, [460]),)),
    "aqua-ring": (((18, None, None, [392, 33]),), ((36, None, None, [33]),)),
    "ingrain": (((18, None, None, [275, 33]),), ((36, None, None, [33]),)),
    "charge": (((18, None, None, [268, 85]),), ((36, None, None, [33]),)),
    "sandaconda": (((844, None, "sand-spit", [89, 203, 283]), (844, None, "sand-veil", [89, 201]),
                    (844, None, "shed-skin", [89, 34])),
                   ((36, None, None, [92, 33]), (143, None, None, [92, 34]))),
    "ability-damage": (((724, None, "long-reach", [413]), (717, None, "dark-aura", [399]),
                        (306, None, "rock-head", [38])),
                       ((760, None, "fluffy", [182, 34]), (437, "flame-orb", "heatproof", [182, 89]),
                        (718, None, "aura-break", [182, 392, 89]))),
    "unseen-fist": (((892, None, "unseen-fist", [370]),), ((718, None, None, [182]),)),
    "gastro-acid": (((18, None, None, [380, 33]),), ((36, None, "huge-power", [33]),)),
    "weight": (((306, None, "heavy-metal", [484]),), ((25, None, None, [33]),)),
    "scrappy": (((130, None, "intimidate", [33]), (306, None, "heavy-metal", [484])),
                ((115, None, "scrappy", [33]), (2, None, None, [275, 499]))),
    "serene-grace": (((18, None, "serene-grace", [52]),), ((36, None, None, [33]),)),
    "magic-bounce": (((101, None, None, [86, 33]),), ((79, None, "magic-bounce", [33]),)),
    "mirror-armor": (((130, None, "intimidate", [33]),), ((143, None, "mirror-armor", [33]),)),
    "mimic": (((122, None, None, [102, 33]),), ((143, None, None, [33]),)),
    "weather-rock": (((18, "damp-rock", "drizzle", [33]),), ((36, None, None, [33]),)),
    "adaptability": (((474, None, "adaptability", [370, 161]),), ((143, None, None, [33]),)),
    "leaf-guard": (((18, None, "leaf-guard", [33]),), ((36, None, "drought", [92, 33]),)),
    "no-guard": (((68, None, "no-guard", [223]),), ((143, None, None, [33]),)),
    "synchronize": (((65, None, "synchronize", [33]),), ((36, None, None, [92, 33]),)),
    "comatose": (((775, None, "comatose", [33]),), ((36, None, None, [92, 33]),)),
    "liquid-ooze": (((3, None, None, [202, 73, 254]), (248, None, "sand-stream", [33])),
                    ((72, None, "liquid-ooze", [33]), (1, None, "overcoat", [33]))),
    "guard-dog": (((130, None, "intimidate", [33]),), ((143, None, "guard-dog", [33]),)),
    "rattled": (((130, None, "intimidate", [33]),), ((128, None, "rattled", [33]),)),
    "opportunist": (((101, None, None, [14, 33]),), ((79, None, "opportunist", [33]),)),
    "steadfast": (((79, None, None, [442, 403]),), ((101, None, "steadfast", [33]),)),
    "wind-rider": (((101, None, "wind-rider", [366, 33]),), ((79, None, None, [33]),)),
    "wind-power": (((101, None, "wind-power", [366, 85]),), ((79, None, None, [33]),)),
    "dancer": (((101, None, None, [14, 33]),), ((79, None, "dancer", [33]),)),
    "simple": (((400, None, "simple", [14, 33]),), ((143, None, None, [33]),)),
    "shield-dust": (((101, None, None, [52]),), ((79, None, "shield-dust", [33]),)),
    "contrary-overheat": (((79, None, "contrary", [315]),), ((101, None, None, [33]),)),
    "corrosion": (((18, None, "corrosion", [92, 33]),), ((16, None, None, [33]),)),
    "natural-cure": (((18, None, "natural-cure", [369]), (36, None, None, [33])), ((6, None, "prankster", [92, 183]),)),
    "regenerator": (((18, None, "regenerator", [369]), (36, None, None, [33])), ((6, None, None, [183]),)),
    "poison-heal": (((18, "toxic-orb", "poison-heal", [33]),), ((101, None, None, [33]),)),
    "flower-veil": (((4, None, "flower-veil", [33]),), ((101, None, None, [45, 261]),)),
    "early-bird": (((101, None, None, [95, 33]),), ((79, None, "early-bird", [33]),)),
    "comatose-toxic": (((18, None, "comatose", [33]),), ((36, None, None, [92, 33]),)),
    "defiant": (((130, None, "intimidate", [33]),), ((18, None, "defiant", [33]),)),
    "rough-skin": (((18, None, None, [33, 88]),), ((36, None, "rough-skin", [33]),)),
    "aftermath": (((18, None, "damp", [33]), (36, None, None, [33])),
                  ((36, None, "aftermath", [33]), (18, None, "innards-out", [33]))),
    "item-theft": (((18, "leftovers", None, [33]), (36, None, "magician", [33])),
                   ((36, None, "pickpocket", [33]), (18, "sitrus-berry", None, [33]))),
    "ability-spread": (((18, None, "huge-power", [33]), (36, None, "guts", [33])),
                       ((36, None, "mummy", [33]), (18, None, "wandering-spirit", [33]))),
    "contact-curse": (((18, None, None, [33, 89]),), ((36, None, "cursed-body", [33]), (18, None, "perish-body", [33]))),
    "contact-ailment": (((18, None, None, [33]),), ((36, None, "effect-spore", [33]), (18, None, "gooey", [33]))),
    "hit-ailment": (((18, None, "poison-touch", [33]), (36, None, "poison-puppeteer", [398])),
                    ((36, None, "stench", [33]), (18, None, "spicy-spray", [33]))),
    "mold-breaker": (((18, None, "mold-breaker", [89, 33]),), ((36, None, "levitate", [33]),)),
    "neutralizing-gas": (((130, None, "intimidate", [33]),), ((36, None, "neutralizing-gas", [33]),)),
    "trace": (((18, None, "trace", [33]),), ((130, None, "intimidate", [33]),)),
    "imposter-entry": (((132, None, "imposter", [33]),), ((6, None, None, [370]),)),
    "dry-skin": (((18, None, None, [57]),), ((36, None, "dry-skin", [33]),)),
    "toxic-debris": (((18, None, None, [33]),), ((36, None, "toxic-debris", [33]), (36, None, None, [33]))),
    "hydration": (((18, None, "hydration", [33]),), ((36, None, "drizzle", [92, 33]),)),
    "mycelium-might": (((18, None, "mycelium-might", [92, 33]),), ((36, None, None, [33]),)),
    "unaware": (((18, None, None, [14, 33]),), ((36, None, "unaware", [33]),)),
    "unnerve": (((18, "sitrus-berry", None, [33]),), ((36, None, "unnerve", [33]),)),
    "zen-mode": (((555, None, "zen-mode", [33]),), ((36, None, None, [370]),)),
    "schooling": (((746, None, "schooling", [33]),), ((36, None, None, [370]),)),
    "stance-change": (((681, None, "stance-change", [588, 33]),), ((36, None, None, [33]),)),
    "shields-down": (((774, None, "shields-down", [33]),), ((36, None, "prankster", [92, 370]),)),
    "power-construct": (((718, None, "power-construct", [33]),), ((36, None, None, [370]),)),
    "disguise": (((778, None, "disguise", [33]),), ((36, None, None, [52]),)),
    "ice-face": (((875, None, "ice-face", [33]),), ((36, None, "snow-warning", [33]),)),
    "gulp-missile": (((845, None, "gulp-missile", [57]),), ((36, None, None, [33]),)),
    "hunger-switch": (((877, None, "hunger-switch", [783]),), ((36, None, None, [33]),)),
    "forecast": (((351, None, "forecast", [33]),), ((36, None, "drought", [33]),)),
    "flower-gift": (((421, None, "flower-gift", [33]),), ((36, None, "drought", [33]),)),
    "zero-to-hero": (((964, None, "zero-to-hero", [369]), (36, None, None, [33])), ((6, None, None, [33]),)),
    "mimicry": (((18, None, "mimicry", [33]),), ((36, None, "electric-surge", [33]),)),
    "protean-libero": (((18, None, "protean", [52, 57]),), ((36, None, "libero", [33]),)),
    "color-change": (((18, None, "color-change", [33]),), ((36, None, None, [52]),)),
    "rks-system": (((773, "fire-memory", "rks-system", [718]),), ((36, None, None, [33]),)),
    "tera-shell": (((36, None, "tera-shell", [33]),), ((6, None, None, [370]),)),
    "teraform-zero": (((36, None, None, [33]), (1024, "stellar-crystal", "tera-shift", [33])),
                      ((6, None, "drought", [370]),)),
    "battle-bond": (((658, None, "battle-bond", [370]),), ((36, None, None, [33]), (18, None, None, [33]))),
    "sturdy": (((10, None, "sturdy", [33]),), ((6, None, None, [370, 53]),)),
    "cloud-nine": (((18, None, "cloud-nine", [33]),), ((36, None, "drizzle", [33]),)),
    "shed-skin": (((18, None, "shed-skin", [33]),), ((36, None, None, [92, 33]),)),
    "ripen": (((18, None, None, [33]),), ((36, "sitrus-berry", "ripen", [33]),)),
    "sticky-hold": (((18, None, None, [282, 168]),), ((36, "leftovers", "sticky-hold", [33]),)),
    "pinch-berries": (((143, "liechi-berry", None, [33]), (143, "salac-berry", "gluttony", [33]),
                       (143, "starf-berry", None, [33]), (143, "lansat-berry", None, [33]),
                       (143, "micle-berry", None, [33]), (143, "custap-berry", None, [33])),
                      ((143, None, None, [33]), (143, None, None, [33]))),
    "flavor-berries": (((143, "figy-berry", "ripen", [33]), (143, "wiki-berry", None, [33]),
                        (143, "mago-berry", "cheek-pouch", [33]), (143, "aguav-berry", None, [33]),
                        (143, "iapapa-berry", "harvest", [33]), (143, "oran-berry", None, [33])),
                       ((143, None, None, [33]), (143, None, None, [33]))),
    "cure-berries": (((36, "cheri-berry", None, [33]), (36, "pecha-berry", None, [33]), (36, "rawst-berry", None, [33]),
                      (36, "chesto-berry", None, [33]), (36, "persim-berry", None, [33]), (36, "aspear-berry", None, [33])),
                     ((101, None, None, [86, 33]), (36, None, None, [92, 33]), (36, None, None, [261, 33]),
                      (36, None, None, [95, 33]), (36, None, None, [109, 33]), (36, None, None, [58]))),
    "hit-berries": (((143, None, None, [33, 52]), (143, None, None, [57, 33])),
                    ((6, "enigma-berry", None, [33]), (143, "jaboca-berry", None, [33]), (143, "rowap-berry", None, [33]),
                     (143, "kee-berry", None, [33]), (143, "maranga-berry", None, [33]),
                     (143, "leppa-berry", None, [33]))),
    "cheek-pouch": (((143, "sitrus-berry", "cheek-pouch", [33]),), ((143, None, None, [33]),)),
    "sheer-force": (((6, "life-orb", "sheer-force", [53, 58]),), ((143, None, None, [33]),)),
    "gems": (((143, "normal-gem", None, [33, 52]), (6, "fire-gem", None, [53, 33]), (130, "water-gem", None, [57])),
             ((143, None, None, [33]), (36, None, None, [33]), (36, None, None, [33]))),
    "soul-heart": (((801, "choice-specs", "soul-heart", [85, 53, 57, 94]),), ((129, None, None, [33]),
                                                                            (129, None, None, [33]))),
}
REPLAY_NAMES = [f"pvp-{start:03d}" for start in range(0, PVP_SCENARIOS, PVP_PER_FILE)] + ["focus"] + [
    f"gyms-{region.id}" for region in gyms.regions()]
REPLAY_ITEMS = sorted(items.ITEM_NAMES) + ["everstone", None]
REPLAY_ABILITIES = sorted(abilities.NAMES) + ["pressure", None]


@pytest.mark.parametrize("name", REPLAY_NAMES)
def test_fixed_seed_replays_match_the_golden_event_logs(name):
    expected = (GOLDEN_DIR / f"{name}.log").read_text().splitlines()
    actual = _replay_text(name).splitlines()
    first = next((index for index, (want, got) in enumerate(zip(expected, actual)) if want != got),
                 min(len(expected), len(actual)))
    assert actual == expected, f"{name}.log line {first + 1}: {actual[first:first + 1]} != {expected[first:first + 1]}"


def test_no_focus_case_name_repeats():
    tree = ast.parse(Path(__file__).read_text())
    cases = next(node.value for node in tree.body
                 if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", None) == "FOCUS_CASES")
    names = [key.value for key in cases.keys]
    assert sorted({name for name in names if names.count(name) > 1}) == []


@pytest.mark.parametrize("start", range(0, PVP_SCENARIOS, PVP_PER_FILE))
def test_every_replayed_battle_narrates(start):
    for scenario in range(start, start + PVP_PER_FILE):
        assert narration.battle_log(_pvp_battle(scenario)[1])


def test_a_move_read_from_the_data_matches_the_move_pokeapi_gives():
    assert {move_id: pokeapi.data_move(move_id) for move_id in _replay_moves()} == _replay_moves()


@pytest.mark.skipif(not os.environ.get("WRITE_GOLDEN"), reason="WRITE_GOLDEN=1 rewrites the golden event logs")
def test_write_golden_event_logs():
    GOLDEN_DIR.mkdir(exist_ok=True)
    for name in REPLAY_NAMES:
        (GOLDEN_DIR / f"{name}.log").write_text(_replay_text(name))


def _replay_text(name):
    kind, _, rest = name.partition("-")
    if kind == "pvp":
        start = int(rest)
        return "".join(_pvp_text(scenario) for scenario in range(start, start + PVP_PER_FILE))
    if kind == "focus":
        return "".join(_focus_text(case, seed) for case in FOCUS_CASES for seed in range(FOCUS_SEEDS))
    return _gyms_text(next(region for region in gyms.regions() if region.id == rest))


def _focus_text(case, seed):
    rng = random.Random(f"{case}-{seed}")
    api = ReplayAPI()
    sides = tuple(
        tuple(combatant(api, {"pokemon_id": pokemon_id, "level": 50, "shiny": False, "moves": moves,
                              "ivs": {stat: rng.randrange(0, 32) for stat in STATS}, "held_item": item,
                              "ability": ability, "nature": None})
              for pokemon_id, item, ability, moves in members)
        for members in FOCUS_CASES[case]
    )
    result = simulate(sides, seed=seed)
    lines = [f"## focus {case} {seed}", *(_combatant_line(side, member) for side in (0, 1) for member in sides[side])]
    return _lines(lines, result)


def _pvp_text(scenario):
    sides, result = _pvp_battle(scenario)
    lines = [f"## pvp {scenario}", *(_combatant_line(side, member) for side in (0, 1) for member in sides[side])]
    return _lines(lines, result)


def _pvp_battle(scenario):
    rng = random.Random(10_000 + scenario)
    api = ReplayAPI()
    sides = tuple(
        tuple(combatant(api, _replay_member(rng, scenario * 12 + side * 6 + slot)) for slot in range(rng.randint(3, 6)))
        for side in (0, 1)
    )
    return sides, simulate(sides, seed=scenario)


def _gyms_text(region):
    lines = []
    for party in range(GYM_PARTIES):
        rng = random.Random(f"{region.id}-{party}")
        team = validate_members([_replay_member(rng, rng.randrange(10_000), level=50) for _ in range(6)], "team")
        seeds = iter(range(1, 1000))
        engine = GymBattles(ReplayAPI(), lambda: next(seeds))
        for run in (region.gyms, region.elite, region.hideout, (region.hidden,)):
            carried = None
            for opponent in run:
                recorded = []

                def recording(*args, **kwargs):
                    recorded.append(simulate(*args, **kwargs))
                    return recorded[-1]

                with mock.patch.object(gym_battle, "simulate", recording):
                    body = engine.battle(opponent.id, team, carried)
                lines.append(f"## {opponent.id} party {party} carried {json.dumps(carried)}")
                lines.extend(_lines([], recorded[0]).splitlines())
                lines.append(f"won={body['won']} carry={json.dumps(body['carry'])} body={_digest(_json(body))}")
                carried = body["carry"] if opponent.run is not None and body["won"] else None
    return "".join(f"{line}\n" for line in lines)


def _json(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def _lines(lines, result):
    lines = [*lines, *(_event_line(event) for event in result.events),
             f"result winner={result.winner} turns={result.turns} remaining={result.remaining} "
             f"statuses={result.statuses}"]
    return "".join(f"{line}\n" for line in lines)


def _combatant_line(side, member):
    mega = member.mega and (member.mega.kind, member.mega.form_id, member.mega.ability_id)
    return (f"side={side} {member.name} Lv{member.level} {member.types} item={member.item} ability={member.ability} "
            f"nature={member.nature} moves={[move.id for move in member.moves]} mega={mega}")


def _event_line(event):
    parts = [type(event).__name__]
    for spec in fields(event):
        value = getattr(event, spec.name)
        default = spec.default if spec.default is not MISSING else (
            spec.default_factory() if spec.default_factory is not MISSING else MISSING)
        if default is MISSING or value != default:
            parts.append(f"{spec.name}={value!r}")
    return " ".join(parts)


class ReplayAPI(FakePokeAPI):
    def attacking_moves(self, pokemon_id, level, machine_ids=(), status=False):
        return [move for move in _learnable() if status or move["id"] not in STATUS_MOVES]


def _replay_member(rng, slot, level=None):
    """Member `slot` of a run of members that walks every known item and ability and the effect moves, with a bound
    item on its own species now and then."""
    item = REPLAY_ITEMS[slot % len(REPLAY_ITEMS)]
    pokemon_id = rng.randrange(1, 1026)
    if rng.random() < 0.2:
        item = rng.choice(sorted(BOUND_ITEMS))
        pokemon_id = BOUND_ITEMS[item]
    effect_ids, attack_ids = _effect_move_ids(), _attack_move_ids()
    count = len(effect_ids)
    moves = [effect_ids[(slot * _stride(count, 3)) % count], effect_ids[(slot * _stride(count, 7) + 1) % count],
             *rng.sample(attack_ids, 2)]
    if rng.random() < 0.05:
        pokemon_id, moves[0] = 384, move_effects.DRAGON_ASCENT
    return {
        "pokemon_id": pokemon_id, "level": level or rng.randrange(40, 71), "shiny": False,
        "moves": list(dict.fromkeys(moves)), "ivs": {stat: rng.randrange(0, 32) for stat in STATS},
        "held_item": item, "ability": REPLAY_ABILITIES[(slot * _stride(len(REPLAY_ABILITIES), 5)) % len(REPLAY_ABILITIES)],
        "nature": rng.choice(("adamant", "modest", "jolly", "timid", "brave", "quiet", None)),
    }


def _stride(count, start):
    """The first step from `start` up that shares no factor with `count`, so stepping by it reaches every index."""
    return next(step for step in range(start, start + count) if math.gcd(step, count) == 1)


@cache
def _effect_move_ids():
    learnable = {move["id"] for move in _learnable()}
    return sorted(int(move_id) for move_id, entry in battle_data.table("moves").items()
                  if int(move_id) in learnable and set(battle_data.keys(entry)) - {"damage"})


@cache
def _attack_move_ids():
    return sorted(move["id"] for move in _learnable() if _attacks(move))


@cache
def _learnable():
    return [{**move, "level": 1, "source": "level"} for move in _replay_moves().values()
            if move["weather"] or _attacks(move) or move["id"] in STATUS_MOVES]


def _attacks(move):
    return move_effects.attacks(move["id"], move["power"], move["damage_class"])


@cache
def _replay_moves():
    """Every move of `data/battle/moves.json` as `PokeAPIService.move` returns it."""
    stat_names = {key: name for name, key in pokeapi._STAT_KEYS.items()}
    moves = {}
    for move_id, entry in battle_data.table("moves").items():
        meta = pokeapi.merged_meta(entry)
        raw = {
            "id": int(move_id), "name": entry["slug"],
            "names": [{"language": {"name": language}, "name": name} for language, name in entry["names"].items()],
            "type": {"name": entry["type"]}, "power": entry["power"], "damage_class": {"name": entry["class"]},
            "accuracy": entry["accuracy"], "priority": entry["priority"], "pp": entry["pp"],
            "meta": {**meta, "ailment": {"name": meta["ailment"]}, "category": {"name": meta["category"]}},
            "stat_changes": [{"stat": {"name": stat_names[stat]}, "change": change}
                             for stat, change in meta["stat_changes"]],
        }
        moves[int(move_id)] = pokeapi.move_from(raw)
    return moves
