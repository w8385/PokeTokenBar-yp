from dataclasses import replace

from test_battle import EMBER, FLAMETHROWER, SURF, TACKLE, actions, mon
from ypoke.battle import Action, SendOut, StatusDamage, _Fighter, _Weather, _weather_upkeep, simulate


def test_a_one_member_roster_plays_the_same_battle_as_the_bare_combatant():
    for seed in range(20):
        a, b = mon("A", ["fire"], moves=[FLAMETHROWER, EMBER]), mon("B", ["water"], moves=[SURF, TACKLE])
        assert simulate(((a,), [b]), seed) == simulate((a, b), seed)
        assert not send_outs(simulate((a, b), seed))


def test_three_strong_members_beat_one_sturdy_one_and_none_is_sent_out():
    result = simulate(((strong("A"), strong("B"), strong("C")), (sturdy("D"),)), seed=3)
    assert result.winner == 0
    assert not send_outs(result)


def test_a_lone_strong_member_beats_three_sturdy_ones_as_each_faint_sends_the_next():
    result = simulate(((strong("A"),), (sturdy("D"), sturdy("E"), sturdy("F"))), seed=3)
    assert result.winner == 0
    assert [(event.side, event.pokemon) for event in send_outs(result)] == [(1, "E"), (1, "F")]
    knockouts = [action for action in actions(result) if action.knockout]
    assert [action.defender for action in knockouts] == ["D", "E", "F"]
    assert [event.turn for event in send_outs(result)] == [action.turn for action in knockouts[:2]]


def test_a_knockout_ends_the_turn_for_the_fainted_side_and_the_successor_then_acts():
    result = simulate(((strong("A"),), (sturdy("D"), sturdy("E"))), seed=3)
    by_turn = {}
    for action in actions(result):
        by_turn.setdefault(action.turn, []).append(action)
    for turn_actions in by_turn.values():
        assert not any(action.knockout for action in turn_actions[:-1])
    assert "E" in {action.attacker for action in actions(result)}


def test_a_sent_out_member_fires_its_entry_ability_right_after_coming_in():
    intimidating = replace(sturdy("E"), ability="intimidate")
    result = simulate(((strong("A"),), (sturdy("D"), intimidating)), seed=3)
    index = next(i for i, event in enumerate(result.events) if isinstance(event, SendOut))
    trigger = result.events[index + 1]
    assert (trigger.side, trigger.pokemon, trigger.ability) == (1, "E", "intimidate")
    assert trigger.change.pokemon == "A" and trigger.change.stages == -1


def test_a_replacement_comes_in_without_the_status_of_the_one_before():
    flame = replace(TACKLE, type="fire", ailment="burn", ailment_chance=100)
    result = simulate(((mon("A", ["fire"], moves=[flame], speed=200, level=60),), (sturdy("D"), sturdy("E"))), seed=0)
    kinds = [
        ("burn-hit" if isinstance(event, Action) else "tick")
        for event in result.events
        if (isinstance(event, StatusDamage) and event.pokemon == "E")
        or (isinstance(event, Action) and event.defender == "E" and event.changes)
    ]
    assert kinds[:2] == ["burn-hit", "tick"]


def test_the_end_of_turn_weather_chips_both_actives_even_when_the_first_faints():
    fighters = tuple(_Fighter.enter(mon(name, ["normal"], level=5, hp=1)) for name in "AB")
    for fighter in fighters:
        fighter.hp = 1
    events = []
    assert _weather_upkeep(1, fighters, _Weather("sandstorm", 3), events) == 0
    assert [(event.side, event.fainted) for event in events] == [(0, True), (1, True)]


def test_at_the_turn_limit_more_members_left_wins(monkeypatch):
    monkeypatch.setattr("ypoke.battle.TURN_LIMIT", 1)
    assert simulate(((sturdy("A"), sturdy("B")), (sturdy("C"),)), seed=1).winner == 0
    assert simulate(((sturdy("A"),), (sturdy("B"), sturdy("C"))), seed=1).winner == 1


def strong(name):
    return mon(name, ["normal"], level=90, moves=[TACKLE], speed=200)


def sturdy(name):
    return mon(name, ["normal"], level=40, moves=[TACKLE], speed=10, hp=120, defense=120, special_defense=120)


def send_outs(result):
    return [event for event in result.events if isinstance(event, SendOut)]
