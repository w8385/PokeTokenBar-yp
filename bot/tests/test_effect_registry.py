import random
from dataclasses import replace

from test_battle import TACKLE, mon
from test_battle_golden import REPLAY_NAMES, _replay_text

from ypoke import battle, effects
from ypoke.battle import Move, WeatherDamage, _Arena, _Fighter, _Team, _Weather
from ypoke.effects import hooks

GIGA_DRAIN = Move("기가드레인", "grass", 75, physical=False, accuracy=None, drain=50)


def test_every_effect_key_has_one_handler_and_every_handler_a_key():
    assert effects.problems() == []


def test_a_key_without_a_handler_and_a_handler_without_a_key_are_both_reported():
    data = {"items": {"odd-stone": {"effect": "made-up"}}}
    found = effects.problems(data)
    assert "items: effect key made-up has no handler" in found
    assert "items: handler leftovers is named by no entry" in found


def test_two_keys_of_one_entry_on_the_same_hook_are_reported():
    data = {"items": {"odd-orb": {"effect": ["life-orb", "expert-belt"]}}}
    assert "items odd-orb: two keys run modify_damage" in effects.problems(data)


def test_every_handler_method_is_a_named_hook():
    registry = effects.loaded()
    names = {hook for kind in registry.values() for handler in kind.values() for hook in effects.hook_names(handler)}
    assert names <= set(hooks.HOOKS)


def test_weather_chip_comes_before_leftovers_at_the_end_of_a_turn():
    holder, foe = _Team((mon("먹보", ("normal",), moves=(TACKLE,)),)), _Team((mon("바위", ("rock",)),))
    fighter = holder.active
    fighter.item, fighter.hp = "leftovers", fighter.max_hp // battle.WEATHER_CHIP_FRACTION
    events = []
    loser = battle._end_of_turn(1, (holder, foe), _Weather("sandstorm", 5), _Arena(), random.Random(0), events)
    assert loser == 0
    assert [type(event) for event in events] == [WeatherDamage]


def test_life_orb_recoil_comes_after_the_drain_heal():
    user = _Fighter.enter(mon("구슬", ("grass",), moves=(GIGA_DRAIN,)))
    user.item = "life-orb"
    target = _Fighter.enter(mon("상대", ("water",), hp=255, defense=255))
    action = battle._resolve(1, 0, (user, target), 0, _Weather(), random.Random(0))
    assert action.drained and action.attacker_item == "life-orb"
    assert user.hp == user.max_hp - user.max_hp // 10


def test_the_faster_weather_setter_enters_first_so_the_slower_ones_weather_stays():
    fast = _Fighter.enter(replace(mon("빠름", ("water",), speed=120), ability="drizzle"))
    slow = _Fighter.enter(replace(mon("느림", ("fire",), speed=40), ability="drought"))
    weather = _Weather()
    triggers = battle._enter_battle((fast, slow), weather, random.Random(0))
    assert [trigger.ability for trigger in triggers] == ["drizzle", "drought"]
    assert weather.kind == "sun"


def test_every_handler_with_a_hook_runs_in_the_golden_replays(monkeypatch):
    ran = set()
    for kind, registry in effects.loaded().items():
        for key, handler in registry.items():
            for hook in effects.hook_names(handler):
                monkeypatch.setattr(handler, hook, _recorder(ran, (kind, key), getattr(handler, hook)))
    for name in REPLAY_NAMES:
        _replay_text(name)
    hooked = {(kind, key) for kind, registry in effects.loaded().items() for key, handler in registry.items()
              if effects.hook_names(handler)}
    assert sorted(hooked - ran) == []


def _recorder(ran, entry, method):
    def run(*args):
        ran.add(entry)
        return method(*args)
    return run
