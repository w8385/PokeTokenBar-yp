from dataclasses import replace

import pytest
from attacks import attack

from ypoke import pokeapi
from ypoke.battle import (
    AbilityTrigger, Action, BaseStats, BattleResult, Change, Combatant, MegaEvolution, MegaForm, Move, SendOut, simulate,
)
from ypoke.commands import Reply, log_messages
from ypoke.mega_stones import MEGA_STONES, mega_form_id
from ypoke.narration import battle_card, battle_log
from ypoke.pokeapi import PokeAPIService
from ypoke.store import Store

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100)
MEGA = MegaForm(types=("fire", "dragon"), base=BaseStats(78, 130, 111, 130, 85, 100), ability="단단한발톱")
CLOSE_COMBAT = attack(370)


def mon(name, mega=None, types=("normal",), speed=80):
    return Combatant(
        name=name, level=50, types=types, base=BaseStats(60, 60, 60, 60, 60, speed), ivs=IVS, moves=(TACKLE,), mega=mega,
    )


def test_stone_only_works_on_its_own_pokemon():
    assert mega_form_id("charizardite-x", 6) == 10034
    assert mega_form_id("charizardite-x", 3) is None
    assert mega_form_id("leftovers", 6) is None
    assert mega_form_id(None, 6) is None


def test_every_stone_points_at_a_distinct_mega_form():
    assert len(MEGA_STONES) == 92
    assert len({form for _, form in MEGA_STONES.values()}) == 92


def test_mega_holder_evolves_before_turn_one_and_fights_with_mega_stats():
    holder, plain = mon("리자몽", MEGA), mon("상대")
    result = simulate((holder, plain), seed=3)
    assert result.events[0] == MegaEvolution(1, 0, "리자몽", "단단한발톱")
    assert sum(isinstance(event, MegaEvolution) for event in result.events) == 1
    assert result.winner == 0


def test_a_holder_further_back_evolves_at_the_start_of_the_turn_after_it_is_sent_out():
    strong = replace(mon("강함", speed=200), base=BaseStats(100, 255, 100, 255, 100, 200))
    team = (replace(mon("첫째"), level=5), mon("둘째", MEGA))
    events = simulate((team, (strong,)), seed=3).events
    evolutions = [index for index, event in enumerate(events) if isinstance(event, MegaEvolution)]
    assert len(evolutions) == 1
    evolution = events[evolutions[0]]
    assert (evolution.side, evolution.pokemon) == (0, "둘째")
    sent = events[evolutions[0] - 1]
    assert isinstance(sent, SendOut) and evolution.turn == sent.turn + 1


def test_only_the_first_holder_of_a_side_evolves():
    strong = replace(mon("강함", speed=200), base=BaseStats(100, 255, 100, 255, 100, 200))
    team = (mon("첫째", MEGA), mon("둘째", MEGA), mon("셋째", MEGA))
    events = simulate((team, (strong,)), seed=3).events
    assert [event.pokemon for event in events if isinstance(event, MegaEvolution)] == ["첫째"]


def test_each_side_gets_its_own_mega_evolution():
    events = simulate(((mon("가", MEGA),), (mon("나", MEGA),)), seed=3).events
    assert sorted((event.side, event.pokemon) for event in events if isinstance(event, MegaEvolution)) == [
        (0, "가"), (1, "나")]


def test_a_mega_ability_fires_when_a_holder_sent_out_mid_battle_mega_evolves():
    drought = replace(MEGA, ability="가뭄", ability_id="drought")
    strong = replace(mon("강함", speed=200), base=BaseStats(100, 255, 100, 255, 100, 200))
    team = (replace(mon("첫째"), level=5), mon("둘째", drought))
    events = simulate((team, (strong,)), seed=3).events
    triggers = [event for event in events if isinstance(event, AbilityTrigger)]
    assert [(trigger.pokemon, trigger.ability) for trigger in triggers] == [("둘째", "drought")]


def test_mega_swaps_in_the_mega_speed_and_types():
    slow_base = mon("느림", MegaForm(types=("fire",), base=BaseStats(60, 60, 60, 60, 60, 200)), speed=10)
    fast = mon("빠름", speed=100)
    first_mover = next(event for event in simulate((slow_base, fast), seed=1).events if isinstance(event, Action))
    assert first_mover.side == 0
    without = next(event for event in simulate((replace(slow_base, mega=None), fast), seed=1).events if isinstance(event, Action))
    assert without.side == 1


def test_a_mega_ability_with_an_entry_effect_acts_as_its_holder_mega_evolves():
    drought = replace(MEGA, ability="가뭄", ability_id="drought")
    holder = replace(mon("리자몽", drought), ability="blaze")
    events = simulate((holder, mon("상대")), seed=3).events
    triggers = [event for event in events if isinstance(event, AbilityTrigger)]
    assert [(trigger.ability, trigger.weather) for trigger in triggers] == [("drought", "sun")]
    assert isinstance(events[events.index(triggers[0]) - 1], MegaEvolution)


def test_the_base_ability_acts_on_entry_and_an_unknown_mega_ability_does_nothing_after():
    tough_claws = replace(MEGA, ability_id="tough-claws")
    holder = replace(mon("리자몽", tough_claws), ability="intimidate")
    events = simulate((holder, mon("상대")), seed=3).events
    triggers = [index for index, event in enumerate(events) if isinstance(event, AbilityTrigger)]
    evolution = next(index for index, event in enumerate(events) if isinstance(event, MegaEvolution))
    assert [events[index].ability for index in triggers] == ["intimidate"]
    assert triggers[0] < evolution


def test_a_mega_staraptor_lead_intimidates_on_entry_then_mega_evolves_and_close_combat_raises_its_defenses():
    contrary = MegaForm(types=("fighting", "flying"), base=BaseStats(85, 140, 100, 60, 90, 110), ability="심술꾸러기",
                        ability_id="contrary", form_id=10308)
    holder = replace(mon("찌르호크", contrary, types=("normal", "flying")), ability="intimidate", moves=(CLOSE_COMBAT,))
    sturdy = replace(mon("딩루", types=("dark", "ground")), base=BaseStats(255, 125, 255, 55, 255, 45))
    result = simulate((holder, sturdy), seed=3)
    events = result.events
    intimidate = next(event for event in events if isinstance(event, AbilityTrigger))
    assert (intimidate.ability, intimidate.change) == ("intimidate", Change(1, "딩루", "attack", -1))
    assert events.index(intimidate) < next(index for index, event in enumerate(events) if isinstance(event, MegaEvolution))
    close_combat = next(event for event in events if isinstance(event, Action) and event.side == 0)
    assert [(change.kind, change.stages) for change in close_combat.changes] == [("defense", 1), ("special_defense", 1)]
    lines = battle_log(result)[0].splitlines()
    assert lines[1:3] == ["🔵 찌르호크 [위협] 공격↓", "🔵 찌르호크 메가진화 [심술꾸러기]"]
    assert lines[3].startswith("🔵 찌르호크 › 인파이트 → 딩루") and lines[3].endswith("효과 굉장 자신 방어↑")


def test_missing_mega_ability_data_keeps_the_base_ability():
    holder = replace(mon("리자몽", replace(MEGA, ability=None)), ability="intimidate")
    events = simulate((holder, mon("상대")), seed=3).events
    assert any(isinstance(event, AbilityTrigger) and event.ability == "intimidate" for event in events)


def test_without_a_stone_the_battle_is_unchanged():
    sides = (mon("가"), mon("나"))
    assert not any(isinstance(event, MegaEvolution) for event in simulate(sides, seed=9).events)


def test_narration_announces_the_mega_evolution():
    holder, plain = mon("리자몽", MEGA), mon("상대")
    result = simulate((holder, plain), seed=3)
    assert battle_log(result)[0].splitlines()[1] == "🔵 리자몽 메가진화 [단단한발톱]"
    assert battle_card(("<@UA>", "<@UB>"), ((holder,), (plain,)), result).columns[0].splitlines()[1].startswith("리자몽(메가)")
    no_ability = replace(MEGA, ability=None)
    assert battle_log(simulate((replace(holder, mega=no_ability), plain), seed=3))[0].splitlines()[1] == "🔵 리자몽 메가진화"


MEGA_ART = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/10034.png"
SHINY_MEGA_ART = MEGA_ART.replace("/10034.png", "/shiny/10034.png")


def drawn(card):
    return [(matchup.left.form_id, matchup.right.form_id) if matchup else None for matchup in card.log_matchups]


def test_the_opening_mega_is_the_first_matchup_picture_in_its_shiny_art():
    form = replace(MEGA, form_id=10034)
    holder, plain = replace(mon("리자몽", form), shiny=True, pokemon_id=6), replace(mon("상대"), pokemon_id=7)
    card = battle_card(("<@UA>", "<@UB>"), ((holder,), (plain,)), simulate((holder, plain), seed=3))
    assert drawn(card)[0] == (10034, 7)
    assert card.log_matchups[0].left.url == SHINY_MEGA_ART
    assert "리자몽 메가진화 [단단한발톱]" in card.log[0]
    assert all(matchup is None for matchup in card.log_matchups[1:])


def test_a_mega_sent_out_mid_battle_is_drawn_above_the_turn_it_evolved_in():
    sides = ((replace(mon("첫째"), pokemon_id=1), replace(mon("둘째", replace(MEGA, form_id=10034)), pokemon_id=6)),
             (replace(mon("상대"), pokemon_id=7),))
    events = [Action(1, 0, "첫째", "상대", "몸통박치기", defender_hp=90),
              Action(4, 1, "상대", "첫째", "몸통박치기", knockout=True, defender_hp=0), SendOut(4, 0, "둘째", 1),
              MegaEvolution(5, 0, "둘째", None, 10034), Action(5, 0, "둘째", "상대", "몸통박치기", defender_hp=50)]
    card = battle_card(("<@UA>", "<@UB>"), sides, BattleResult(0, 5, events, remaining=((0, 80), (50,))))
    assert [text.splitlines()[0] for text in card.log] == ["*1턴*", "*4턴*", "*5턴*"]
    assert drawn(card) == [(1, 7), None, (10034, 7)]
    assert card.log_matchups[2].left.url == MEGA_ART


def test_a_mega_without_a_form_id_or_a_stone_keeps_the_base_art():
    plain = replace(mon("상대"), pokemon_id=7)
    for holder in (replace(mon("리자몽", MEGA), pokemon_id=6), replace(mon("리자몽"), pokemon_id=6)):
        card = battle_card(("<@UA>", "<@UB>"), ((holder,), (plain,)), simulate((holder, plain), seed=3))
        assert [pair for pair in drawn(card) if pair] == [(6, 7)]


def test_both_sides_megas_in_a_long_battle_stay_one_thread_reply():
    form = replace(MEGA, form_id=10034)
    sides = ((replace(mon("가", form), pokemon_id=6),) * 3, (replace(mon("나", form), pokemon_id=6),) * 3)
    events = [Action(turn, turn % 2, "가", "나", "몸통박치기", defender_hp=99) for turn in range(1, 301)]
    events[:0] = [MegaEvolution(1, 0, "가", None, 10034), MegaEvolution(1, 1, "나", None, 10034)]
    for turn in (40, 120, 200, 260):
        events.insert(turn, SendOut(turn, 1, "나"))
    result = BattleResult(0, 300, events, remaining=((50, None, None), (0, 0, 70)))
    card = battle_card(("<@UA>", "<@UB>"), sides, result)
    assert drawn(card)[0] == (10034, 10034)
    [message] = log_messages(Reply("h", summary="h", card=card, rematch="UA:UB:3"))
    assert len(message.blocks) <= 50


@pytest.fixture
def service(tmp_path, monkeypatch):
    fetched = []
    body = {
        "name": "charizard-mega-x", "species": {"url": "https://pokeapi.co/api/v2/pokemon-species/6/"},
        "types": [{"slot": 2, "type": {"name": "dragon"}}, {"slot": 1, "type": {"name": "fire"}}], "weight": 1105,
        "stats": [{"stat": {"name": name}, "base_stat": value} for name, value in
                  (("hp", 78), ("attack", 130), ("defense", 111), ("special-attack", 130), ("special-defense", 85), ("speed", 100))],
        "abilities": [{"is_hidden": True, "ability": {"name": "hidden", "url": "https://pokeapi.co/api/v2/ability/1/"}},
                      {"is_hidden": False, "ability": {"name": "tough-claws", "url": "https://pokeapi.co/api/v2/ability/181/"}}],
    }

    def get_json(url):
        fetched.append(url)
        if "pokemon-species" in url:
            return {"names": [{"language": {"name": "ko"}, "name": "리자몽"}]}
        if "/ability/" in url:
            return {"name": "tough-claws", "names": [{"language": {"name": "ko"}, "name": "단단한발톱"}]}
        return body

    monkeypatch.setattr(pokeapi, "_get_json", get_json)
    return PokeAPIService(Store(str(tmp_path / "ypoke.db"))), fetched


def test_mega_form_reads_stats_types_and_the_visible_ability_once(service):
    api, fetched = service
    form = api.mega_form(10034)
    assert form["types"] == ["fire", "dragon"]
    assert form["base"]["attack"] == 130
    assert form["ability"] == "단단한발톱"
    assert form["ability_id"] == "tough-claws"
    calls = len(fetched)
    assert api.mega_form(10034) == form
    assert len(fetched) == calls


def test_a_battle_with_a_stone_holder_carries_the_mega_form_image(tmp_path):
    from test_commands import FakePokeAPI, handler, member

    class MegaAPI(FakePokeAPI):
        def mega_form(self, pokemon_id):
            return {**self.pokemon(pokemon_id), "ability": None, "ability_id": None}

    store = Store(str(tmp_path / "bot.sqlite3"))
    for user, party in (("UA", [{**member(6, 60), "held_item": "charizardite-x"}]), ("UB", [member(7, 20)])):
        store.issue_token(user)
        store.save_party(user, party)
    reply = handler(store, pokeapi=MegaAPI()).handle("UA", "<@UB>")
    [lead] = [matchup for matchup in reply.card.log_matchups if matchup]
    assert (lead.left.url, lead.left.name) == (MEGA_ART, "야생몬")
