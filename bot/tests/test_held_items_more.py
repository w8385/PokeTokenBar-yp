import random
from dataclasses import replace

import pytest

from ypoke import items
from ypoke.battle import (
    CRITICAL_CHANCES, WEATHER_TURNS, Action, BaseStats, Combatant, ItemEffect, ItemHeal, Move, _act, _best_move,
    _enter_battle, _Fighter, _item_triggers, _item_upkeep, _quick_claws, _turn_order, _unrolled_damage, _Weather,
    simulate,
)
from ypoke.narration import battle_log
from ypoke.pokeapi import PokeAPIService, _evolves_further
from ypoke.store import Store

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100, id=33)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)
RAIN_DANCE = Move("비바라기", None, 0, physical=False, weather="rain")
SUNNY_DAY = Move("쾌청", None, 0, physical=False, weather="sun")
SURF = Move("파도타기", "water", 90, physical=False, accuracy=100)
DRAIN = Move("흡수", "grass", 40, physical=False, accuracy=100, drain=50)
FEEBLE = Move("약한공격", "normal", 40, physical=True, accuracy=90)


def mon(name, item=None, types=("normal",), level=50, moves=(TACKLE,), hp=80, attack=80, defense=80,
        special_attack=80, special_defense=80, speed=80, ability=None, can_evolve=False):
    return Combatant(
        name=name, level=level, types=tuple(types), base=BaseStats(hp, attack, defense, special_attack, special_defense, speed),
        ivs=IVS, moves=tuple(moves), item=item, ability=ability, can_evolve=can_evolve,
    )


class FixedRng(random.Random):
    """`random()` answers `value`; everything else follows seed 0."""

    def __init__(self, value):
        super().__init__(0)
        self.value = value

    def random(self):
        return self.value


def damage(attacker, defender, move, multiplier=1.0):
    return _unrolled_damage(_Fighter.enter(attacker), _Fighter.enter(defender), move, multiplier, None)


def duel(attacker, defender, move_index=0, rng=None):
    fighters = (_Fighter.enter(attacker), _Fighter.enter(defender))
    action = _act(1, 0, fighters, move_index, _Weather(), rng or FixedRng(0.5))
    return action, fighters


@pytest.mark.parametrize("item,boosted", sorted(items.TYPE_BOOST_ITEMS.items()))
def test_a_type_boost_item_raises_only_its_own_types_moves(item, boosted):
    other = "water" if boosted != "water" else "fire"
    holder, plain, foe = mon("든", item), mon("맨몸"), mon("상대")
    assert damage(holder, foe, move_of(boosted)) == pytest.approx(damage(plain, foe, move_of(boosted)) * 1.2)
    assert damage(holder, foe, move_of(other)) == damage(plain, foe, move_of(other))


def test_every_type_has_exactly_one_boost_item():
    assert sorted(items.TYPE_BOOST_ITEMS.values()) == sorted(
        "normal fire water electric grass ice fighting poison ground flying psychic bug rock ghost dragon dark steel fairy".split()
    )


def test_every_known_item_slug_has_a_korean_name():
    slugs = {value for name, value in vars(items).items() if name.isupper() and isinstance(value, str)}
    assert slugs <= set(items.ITEM_NAMES)
    assert set(items.TYPE_BOOST_ITEMS) <= set(items.ITEM_NAMES)
    assert set(items.WEATHER_ROCKS) <= set(items.ITEM_NAMES)


def test_everstone_does_nothing_in_battle():
    sides = (mon("A", moves=(TACKLE, EMBER)), mon("B"))
    assert simulate((replace(sides[0], item="everstone"), sides[1]), seed=3) == simulate(sides, seed=3)


def test_choice_specs_raise_special_attack_and_lock_the_first_move():
    specs, plain, foe = mon("안경", items.CHOICE_SPECS), mon("맨몸"), mon("상대")
    assert damage(specs, foe, EMBER) == pytest.approx(damage(plain, foe, EMBER) * 1.5, rel=0.02)
    assert damage(specs, foe, TACKLE) == damage(plain, foe, TACKLE)
    wall = mon("벽", hp=255, defense=255, special_defense=255, speed=1)
    result = simulate((mon("안경", items.CHOICE_SPECS, moves=(EMBER, SURF), speed=100), wall), seed=2)
    assert len({action.move for action in actions(result) if action.attacker == "안경"}) == 1


def test_assault_vest_raises_special_defense_only_and_never_sets_weather():
    vest, plain, foe = mon("조끼", items.ASSAULT_VEST), mon("맨몸"), mon("상대")
    assert damage(foe, vest, EMBER) == pytest.approx(damage(foe, plain, EMBER) / 1.5, abs=1)
    assert damage(foe, vest, TACKLE) == damage(foe, plain, TACKLE)
    fire = mon("불", types=("fire",), hp=255, special_defense=150)
    setter = mon("물", items.ASSAULT_VEST, ("water",), moves=(RAIN_DANCE, SURF), special_attack=30)
    assert _best_move(_Fighter.enter(setter), _Fighter.enter(fire), None) == 1
    assert _best_move(_Fighter.enter(replace(setter, item=None)), _Fighter.enter(fire), None) == 0


def test_eviolite_raises_both_defenses_only_while_the_holder_can_still_evolve():
    young = _Fighter.enter(mon("애송이", items.EVIOLITE, can_evolve=True))
    final = _Fighter.enter(mon("최종", items.EVIOLITE, can_evolve=False))
    plain = _Fighter.enter(mon("맨몸"))
    for key in ("defense", "special_defense"):
        assert young.stat(key) == pytest.approx(plain.stat(key) * 1.5)
        assert final.stat(key) == plain.stat(key)
    assert young.stat("attack") == plain.stat("attack")


def test_rocky_helmet_hurts_a_contact_attacker_by_a_sixth_and_ignores_special_moves():
    helmet = mon("헬멧", items.ROCKY_HELMET, hp=255, defense=255, special_defense=255)
    action, (attacker, _) = duel(mon("공격수", hp=100), helmet)
    assert action.defender_item == items.ROCKY_HELMET
    assert attacker.hp == attacker.max_hp - attacker.max_hp // 6
    special, (attacker, _) = duel(mon("공격수", moves=(EMBER,)), helmet)
    assert special.defender_item == "" and attacker.hp == attacker.max_hp


def test_rocky_helmet_can_knock_out_the_attacker_even_when_it_wins_the_hit():
    helmet = mon("헬멧", items.ROCKY_HELMET, level=1, hp=1)
    frail = _Fighter.enter(mon("공격수", level=1, hp=1))
    frail.hp = 1
    foe = _Fighter.enter(helmet)
    action = _act(1, 0, (frail, foe), 0, _Weather(), FixedRng(0.5))
    assert action.knockout and action.attacker_fainted and action.defender_item == items.ROCKY_HELMET


def test_sitrus_berry_heals_a_quarter_once_when_half_hp_or_less():
    fighters = (_Fighter.enter(mon("열매", items.SITRUS_BERRY)), _Fighter.enter(mon("상대")))
    events = []
    fighters[0].hp = fighters[0].max_hp // 2 + 1
    _item_triggers(1, fighters, events)
    assert events == [] and fighters[0].item == items.SITRUS_BERRY
    fighters[0].hp = fighters[0].max_hp // 2
    before = fighters[0].hp
    _item_triggers(1, fighters, events)
    assert fighters[0].hp == before + fighters[0].max_hp // 4 and fighters[0].item is None
    assert events == [ItemHeal(1, 0, "열매", items.SITRUS_BERRY, fighters[0].hp_percent)]
    fighters[0].hp = 1
    _item_triggers(2, fighters, events)
    assert len(events) == 1


def test_sitrus_berry_is_eaten_in_a_real_battle_after_the_hit_that_halves_the_holder():
    strong = mon("강함", level=60, attack=120, speed=200)
    result = simulate((strong, mon("열매", items.SITRUS_BERRY, hp=200, defense=60, speed=1)), seed=1)
    eaten = [event for event in result.events if isinstance(event, ItemHeal) and event.item == items.SITRUS_BERRY]
    assert len(eaten) == 1 and eaten[0].side == 1


def test_black_sludge_heals_a_poison_holder_and_hurts_everyone_else():
    poison = _Fighter.enter(mon("독", items.BLACK_SLUDGE, ("poison",)))
    other = _Fighter.enter(mon("다른", items.BLACK_SLUDGE))
    poison.hp -= 40
    events = []
    _item_upkeep(1, (poison, other), events, random.Random(0))
    assert poison.hp == poison.max_hp - 40 + max(1, poison.max_hp // 16)
    assert other.hp == other.max_hp - max(1, other.max_hp // 8)
    assert [(event.side, event.hp < 100) for event in events] == [(0, True), (1, True)]


def test_black_sludge_can_faint_a_non_poison_holder_and_the_log_says_so():
    holder = _Fighter.enter(mon("다른", items.BLACK_SLUDGE))
    holder.hp = 1
    events = []
    _item_upkeep(2, (holder, _Fighter.enter(mon("상대"))), events, random.Random(0))
    assert events == [ItemHeal(2, 0, "다른", items.BLACK_SLUDGE, 0, True)]
    result = simulate((mon("강함", level=100, attack=255, speed=255), mon("다른", items.BLACK_SLUDGE, level=5)), seed=1)
    assert result.winner == 0


def test_shell_bell_heals_an_eighth_of_the_damage_dealt():
    attacker = mon("종", items.SHELL_BELL, hp=255)
    fighters = (_Fighter.enter(attacker), _Fighter.enter(mon("상대", hp=255, defense=100)))
    fighters[0].hp -= 40
    before = fighters[0].hp
    action = _act(1, 0, fighters, 0, _Weather(), FixedRng(0.5))
    dealt = fighters[1].max_hp - fighters[1].hp
    assert action.attacker_item == items.SHELL_BELL
    assert fighters[0].hp == before + max(1, dealt // 8)


def test_shell_bell_stays_quiet_at_full_hp():
    action, _ = duel(mon("종", items.SHELL_BELL), mon("상대"))
    assert action.attacker_item == ""


def test_big_root_raises_a_drain_move_heal_by_thirty_percent():
    foe = mon("상대", hp=255, defense=100)
    healed = {}
    for label, item in (("root", items.BIG_ROOT), ("plain", None)):
        fighters = (_Fighter.enter(mon("뿌리", item, moves=(DRAIN,), hp=255)), _Fighter.enter(foe))
        fighters[0].hp = 1
        action = _act(1, 0, fighters, 0, _Weather(), FixedRng(0.5))
        healed[label] = fighters[0].hp - 1
        assert action.attacker_item == (items.BIG_ROOT if item else "")
    assert healed["root"] == int(healed["plain"] * 1.3)


def test_muscle_band_and_wise_glasses_raise_physical_and_special_moves_a_tenth():
    band, glasses, plain, foe = mon("띠", items.MUSCLE_BAND), mon("안경", items.WISE_GLASSES), mon("맨몸"), mon("상대")
    assert damage(band, foe, TACKLE) == pytest.approx(damage(plain, foe, TACKLE) * 1.1)
    assert damage(band, foe, EMBER) == damage(plain, foe, EMBER)
    assert damage(glasses, foe, EMBER) == pytest.approx(damage(plain, foe, EMBER) * 1.1)
    assert damage(glasses, foe, TACKLE) == damage(plain, foe, TACKLE)


def test_a_confusion_self_hit_ignores_the_damage_items():
    from ypoke.battle import CONFUSION_HIT
    band, plain = _Fighter.enter(mon("띠", items.MUSCLE_BAND)), _Fighter.enter(mon("맨몸"))
    assert _unrolled_damage(band, band, CONFUSION_HIT, 1.0, None) == _unrolled_damage(plain, plain, CONFUSION_HIT, 1.0, None)


@pytest.mark.parametrize("item", [items.SCOPE_LENS, items.RAZOR_CLAW])
def test_scope_lens_and_razor_claw_raise_the_critical_stage_by_one(item, monkeypatch):
    monkeypatch.setattr("ypoke.battle.CRITICAL_CHANCES", (0.0, 1.0, 1.0, 1.0))
    assert CRITICAL_CHANCES[0] == pytest.approx(1 / 24)
    boosted, _ = duel(mon("렌즈", item), mon("상대"))
    plain, _ = duel(mon("맨몸"), mon("상대"))
    assert boosted.critical and not plain.critical


def test_quick_claw_may_put_a_slower_holder_first_and_logs_it_only_then():
    slow, fast = _Fighter.enter(mon("손톱", items.QUICK_CLAW, speed=10)), _Fighter.enter(mon("빠름", speed=200))
    events = []
    claws = _quick_claws(1, (slow, fast), (0, 0), None, FixedRng(0.1), events)
    assert claws == (True, False)
    assert events == [ItemEffect(1, 0, "손톱", items.QUICK_CLAW, "first")]
    assert _turn_order((slow, fast), (0, 0), random.Random(0), None, claws) == (0, 1)
    events.clear()
    assert _quick_claws(1, (slow, fast), (0, 0), None, FixedRng(0.5), events) == (False, False) and events == []
    fast_holder, slower = _Fighter.enter(mon("손톱", items.QUICK_CLAW, speed=200)), _Fighter.enter(mon("느림", speed=10))
    _quick_claws(1, (fast_holder, slower), (0, 0), None, FixedRng(0.1), events)
    assert events == []


def test_quick_claw_never_beats_a_higher_priority_move_and_draws_no_random_number_without_the_item():
    class NoDraw(random.Random):
        def random(self):
            raise AssertionError("drew a number")

    quick = Move("전광석화", "normal", 40, physical=True, accuracy=100, priority=1)
    slow = _Fighter.enter(mon("손톱", items.QUICK_CLAW, speed=10))
    fast = _Fighter.enter(mon("빠름", moves=(quick,), speed=200))
    claws = _quick_claws(1, (slow, fast), (0, 0), None, FixedRng(0.1), [])
    assert _turn_order((slow, fast), (0, 0), random.Random(0), None, claws) == (1, 0)
    assert _quick_claws(1, (fast, fast), (0, 0), None, NoDraw(0), []) == (False, False)


def test_bright_powder_and_wide_lens_move_a_ninety_percent_accuracy_by_a_tenth():
    foe = mon("상대", hp=255, defense=100)
    rng = FixedRng(0.95)
    plain, _ = duel(mon("A", moves=(FEEBLE,)), foe, rng=rng)
    assert plain.missed
    lens, _ = duel(mon("A", items.WIDE_LENS, moves=(FEEBLE,)), foe, rng=FixedRng(0.98))
    assert not lens.missed
    powdered, _ = duel(mon("A", moves=(TACKLE,)), mon("B", items.BRIGHT_POWDER), rng=FixedRng(0.95))
    assert powdered.missed
    clear, _ = duel(mon("A", moves=(TACKLE,)), mon("B"), rng=FixedRng(0.95))
    assert not clear.missed


def test_weakness_policy_is_spent_on_a_surviving_super_effective_hit():
    holder = mon("약점", items.WEAKNESS_POLICY, ("grass",), hp=255, special_defense=255)
    action, (_, defender) = duel(mon("불", moves=(EMBER,), special_attack=60), holder)
    assert action.defender_item == items.WEAKNESS_POLICY and defender.item is None
    assert (defender.stages["attack"], defender.stages["special_attack"]) == (2, 2)
    neutral, (_, kept) = duel(mon("불", moves=(TACKLE,)), mon("노말", items.WEAKNESS_POLICY, hp=255, defense=255))
    assert neutral.defender_item == "" and kept.item == items.WEAKNESS_POLICY
    frail = mon("약점", items.WEAKNESS_POLICY, ("grass",), level=1, hp=1)
    knocked, (_, gone) = duel(mon("불", level=100, moves=(EMBER,), special_attack=255), frail)
    assert knocked.knockout and knocked.defender_item == ""


def test_white_herb_undoes_an_intimidate_drop_once():
    intimidator = _Fighter.enter(mon("위협", ability="intimidate"))
    herb = _Fighter.enter(mon("허브", items.WHITE_HERB))
    _enter_battle((intimidator, herb), _Weather(), random.Random(0))
    assert herb.stages["attack"] == -1
    events = []
    _item_triggers(1, (intimidator, herb), events)
    assert herb.stages["attack"] == 0 and herb.item is None
    assert events == [ItemEffect(1, 1, "허브", items.WHITE_HERB, "restore")]
    herb.stages["attack"] = -2
    _item_triggers(2, (intimidator, herb), events)
    assert herb.stages["attack"] == -2


def test_white_herb_keeps_raised_stats_and_waits_for_a_drop():
    herb = _Fighter.enter(mon("허브", items.WHITE_HERB))
    herb.stages["speed"] = 2
    events = []
    _item_triggers(1, (herb, _Fighter.enter(mon("상대"))), events)
    assert events == [] and herb.item == items.WHITE_HERB


def test_lum_berry_cures_a_status_or_confusion_once():
    berry = _Fighter.enter(mon("리샘", items.LUM_BERRY))
    events = []
    _item_triggers(1, (berry, _Fighter.enter(mon("상대"))), events)
    assert events == []
    berry.status, berry.toxic_ticks = "toxic", 3
    _item_triggers(1, (berry, _Fighter.enter(mon("상대"))), events)
    assert (berry.status, berry.item) == (None, None)
    assert events == [ItemEffect(1, 0, "리샘", items.LUM_BERRY, "cure")]
    other = _Fighter.enter(mon("리샘", items.LUM_BERRY))
    other.confusion_left = 3
    _item_triggers(2, (other, berry), events)
    assert other.confusion_left == 0 and other.item is None


@pytest.mark.parametrize("item,ailment,types,immune", [
    (items.FLAME_ORB, "burn", ("normal",), ("fire",)),
    (items.TOXIC_ORB, "toxic", ("normal",), ("steel",)),
])
def test_an_orb_inflicts_its_status_at_end_of_turn_unless_the_holder_is_immune_or_already_ill(item, ailment, types, immune):
    holder, other = _Fighter.enter(mon("구슬", item, types)), _Fighter.enter(mon("상대"))
    events = []
    _item_upkeep(1, (holder, other), events, random.Random(0))
    assert holder.status == ailment and holder.item == item
    assert events == [ItemEffect(1, 0, "구슬", item, ailment)]
    immune_holder = _Fighter.enter(mon("면역", item, immune))
    _item_upkeep(1, (immune_holder, other), events, random.Random(0))
    assert immune_holder.status is None and len(events) == 1
    holder.status = "paralysis"
    _item_upkeep(2, (holder, other), events, random.Random(0))
    assert holder.status == "paralysis" and len(events) == 1


def test_a_flame_orb_holder_burns_in_a_real_battle_and_the_log_shows_it():
    result = simulate((mon("구슬", items.FLAME_ORB, hp=255, defense=255), mon("상대", hp=255, defense=255)), seed=2)
    assert events_of(result, ItemEffect)[0].effect == "burn"
    assert any("@화염구슬 🔥화상" in text for text in battle_log(result))


def test_focus_band_survives_a_lethal_hit_one_time_in_ten_and_is_kept():
    frail = mon("띠", items.FOCUS_BAND, level=1, hp=1)
    strong = mon("강함", level=100, attack=255)
    lucky, (_, kept) = duel(strong, frail, rng=FixedRng(0.05))
    assert lucky.defender_item == items.FOCUS_BAND and not lucky.knockout and kept.hp == 1
    assert kept.item == items.FOCUS_BAND
    unlucky, _ = duel(strong, frail, rng=FixedRng(0.5))
    assert unlucky.knockout and unlucky.defender_item == ""


def test_heat_rock_and_the_other_rocks_stretch_only_their_own_weather_to_eight_turns():
    def turns(item, move):
        fighters = (_Fighter.enter(mon("A", item, moves=(move,))), _Fighter.enter(mon("B")))
        weather = _Weather()
        _act(1, 0, fighters, 0, weather, FixedRng(0.5))
        return weather.turns_left

    assert turns("heat-rock", SUNNY_DAY) == 8
    assert turns("damp-rock", RAIN_DANCE) == 8
    assert turns("heat-rock", RAIN_DANCE) == WEATHER_TURNS
    assert turns(None, SUNNY_DAY) == WEATHER_TURNS
    assert items.weather_turns("icy-rock", "snow", 5) == items.weather_turns("icy-rock", "hail", 5) == 8
    assert items.weather_turns("smooth-rock", "sandstorm", 5) == 8


def test_a_rock_also_stretches_the_weather_an_entry_ability_sets():
    state = _Weather()
    _enter_battle((_Fighter.enter(mon("A", "heat-rock", ability="drought")), _Fighter.enter(mon("B"))), state, random.Random(0))
    assert (state.kind, state.turns_left) == ("sun", 8)


def test_the_log_always_shows_a_triggered_item_even_when_other_tags_fill_the_line():
    crowded = Action(
        1, 0, "공격", "방어", "기술", multiplier=2.0, critical=True, defender_hp=40, defender_item=items.WEAKNESS_POLICY,
        attacker_item=items.LIFE_ORB,
    )
    line = battle_log(replace(simulate((mon("A"), mon("B")), seed=0), events=[crowded], winner=0))[0]
    assert "급소" in line and "효과 굉장" in line and "@생명의구슬" in line and "@약점보험" in line


def test_narration_covers_every_item_event():
    from ypoke.narration import ITEM_EFFECT_TEXT
    result = simulate((mon("A"), mon("B")), seed=0)
    for effect in ITEM_EFFECT_TEXT:
        lines = battle_log(replace(result, events=[ItemEffect(1, 1, "꼬부기", items.QUICK_CLAW, effect)], winner=0))
        assert lines[0].splitlines()[1] == f"🔴 꼬부기 @선제공격손톱 {ITEM_EFFECT_TEXT[effect]}"
    sludge = ItemHeal(2, 0, "독", items.BLACK_SLUDGE, 0, True)
    assert battle_log(replace(result, events=[sludge], winner=1))[0].splitlines()[1:] == [
        "🔵 독 @검은오물 0%", "💥 독 쓰러짐",
    ]


@pytest.mark.parametrize("item", sorted(items.ITEM_NAMES))
def test_every_item_survives_full_battles_and_narrates_them(item):
    moves = (TACKLE, EMBER, DRAIN, RAIN_DANCE)
    for seed in range(6):
        holder = mon("든", item, ("normal",), level=40, moves=moves, hp=100, can_evolve=True)
        foe = mon("상대", types=("grass",), level=40, moves=(TACKLE, EMBER, SURF), hp=100, ability="intimidate")
        result = simulate(((holder, holder), (foe, foe)), seed)
        assert result.winner in (0, 1)
        assert battle_log(result)


class FakeStore:
    def __init__(self):
        self.data = {}

    def cached(self, key):
        return self.data.get(key)

    def cache(self, key, value):
        self.data[key] = value


def chain(*stages):
    node = {"species": {"name": stages[-1]}, "evolves_to": []}
    for name in reversed(stages[:-1]):
        node = {"species": {"name": name}, "evolves_to": [node]}
    return node


def test_a_species_can_evolve_when_it_has_an_evolution_below_it_in_the_chain():
    pikachu_line = chain("pichu", "pikachu", "raichu")
    assert _evolves_further(pikachu_line, "pichu") and _evolves_further(pikachu_line, "pikachu")
    assert not _evolves_further(pikachu_line, "raichu")
    assert not _evolves_further(chain("tauros"), "tauros")
    branching = {"species": {"name": "eevee"}, "evolves_to": [chain("vaporeon"), chain("jolteon")]}
    assert _evolves_further(branching, "eevee") and not _evolves_further(branching, "jolteon")


def test_can_evolve_reads_the_species_chain_once_and_caches_it(monkeypatch):
    calls = []

    def fake_get(url):
        calls.append(url)
        if url.endswith("/pokemon/10100"):
            return {"species": {"url": "https://x/pokemon-species/25/"}}
        if "pokemon-species" in url:
            return {"name": "pikachu", "evolution_chain": {"url": "https://x/evolution-chain/10/"}}
        return {"chain": chain("pichu", "pikachu", "raichu")}

    monkeypatch.setattr("ypoke.pokeapi._get_json", fake_get)
    service = PokeAPIService(FakeStore())
    assert service.can_evolve(10100) is True
    assert service.can_evolve(10100) is True
    assert len(calls) == 3


DOUBLE_HIT = Move("더블어택", "normal", 40, physical=True, accuracy=100, min_hits=2, max_hits=2, id=458)


def test_rocky_helmet_hurts_between_hits_and_a_fainted_attacker_stops_hitting():
    helmet = _Fighter.enter(mon("헬멧", items.ROCKY_HELMET, hp=255, defense=255))
    frail = _Fighter.enter(mon("공격수", moves=(DOUBLE_HIT,)))
    frail.hp = 1
    action = _act(1, 0, (frail, helmet), 0, _Weather(), FixedRng(0.5))
    assert action.hits == 1 and action.attacker_fainted and action.defender_item == items.ROCKY_HELMET


def test_rocky_helmet_hurts_once_per_hit_of_a_multi_hit_move():
    helmet = _Fighter.enter(mon("헬멧", items.ROCKY_HELMET, hp=255, defense=255))
    attacker = _Fighter.enter(mon("공격수", hp=255, moves=(DOUBLE_HIT,)))
    action = _act(1, 0, (attacker, helmet), 0, _Weather(), FixedRng(0.5))
    assert action.hits == 2 and attacker.hp == attacker.max_hp - 2 * (attacker.max_hp // 6)


def test_sitrus_berry_is_eaten_between_the_hits_of_a_multi_hit_move(monkeypatch):
    holder = _Fighter.enter(mon("열매", items.SITRUS_BERRY))
    attacker = _Fighter.enter(mon("공격수", moves=(DOUBLE_HIT,)))
    monkeypatch.setattr("ypoke.battle._damage", lambda *args: holder.max_hp * 55 // 100)
    action = _act(1, 0, (attacker, holder), 0, _Weather(), FixedRng(0.5))
    assert action.hits == 2 and not action.knockout and holder.item is None
    assert action.defender_item == items.SITRUS_BERRY


def test_the_battle_looks_up_evolution_only_for_an_eviolite_holder_and_survives_a_failed_lookup():
    from ypoke.combatants import _can_evolve

    class Fake:
        def __init__(self, fail=None):
            self.asked, self.fail = [], fail

        def can_evolve(self, pokemon_id):
            self.asked.append(pokemon_id)
            if self.fail:
                raise self.fail
            return True

    api = Fake()
    assert _can_evolve(api, {"pokemon_id": 25, "held_item": "eviolite"}) is True
    assert _can_evolve(api, {"pokemon_id": 26, "held_item": "leftovers"}) is False
    assert _can_evolve(api, {"pokemon_id": 26}) is False
    assert api.asked == [25]
    for failure in (OSError("offline"), ValueError("not json"), KeyError("evolution_chain"), TypeError("null chain")):
        assert _can_evolve(Fake(fail=failure), {"pokemon_id": 25, "held_item": "eviolite"}) is False


def actions(result):
    return [event for event in result.events if isinstance(event, Action)]


def events_of(result, kind):
    return [event for event in result.events if isinstance(event, kind)]


def move_of(move_type):
    return Move("기술", move_type, 40, physical=False, accuracy=100)
