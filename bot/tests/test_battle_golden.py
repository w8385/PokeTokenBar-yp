import hashlib
import json
import random
from pathlib import Path

import pytest

from ypoke import abilities, gyms, items, narration
from ypoke.battle import simulate
from ypoke.combatants import combatant
from ypoke.mega_stones import MEGA_STONES, PRIMAL_ORBS, ULTRA_BURSTS
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
            if move["weather"] or (move["power"] and move["damage_class"] != "status")
            or (status and move["id"] in STATUS_MOVES)
        ]

    def can_evolve(self, pokemon_id):
        return pokemon_id % 2 == 0


def _species_data(pokemon_id):
    first = TYPES[pokemon_id % len(TYPES)]
    second = TYPES[(pokemon_id * 7 + 3) % len(TYPES)]
    types = [first] if pokemon_id % 3 == 0 or second == first else [first, second]
    base = {stat: 50 + (pokemon_id * (index + 3) * 37) % 81 for index, stat in enumerate(STATS)}
    return {"name_ko": f"P{pokemon_id}", "types": types, "base": base}


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
