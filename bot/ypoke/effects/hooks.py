"""The hook points of a battle in the order a turn reaches them, and the calls that run an entry's handler at one.

A Pokémon's ability and held item are read at call time: a berry, a Focus Sash or Knock Off can take the item away
mid-turn. One entry runs at most one handler per hook (`effects.problems` checks it), so a hook returns that handler's
answer, or `default` when the entry runs none. The end of a turn runs `battle.END_OF_TURN` in order.
"""

from functools import cache

from ypoke import battle_data
from ypoke.effects import hook_names, loaded

HOOKS = {
    "hazard": "state: an entry hazard acts on a Pokémon entering its side, in the order the hazards were set",
    "ignores_hazards": "item: the hazards that hurt, poison or slow do nothing to its holder",
    "on_entry_form": "item: a held-item form takes hold as its holder enters, after the hazards and Mega Evolution",
    "on_entry": "ability: acts as its holder enters, the faster entering Pokémon first",
    "state_turns": "item: how long a field or side state its holder sets lasts",
    "on_update": "item: a one-use item reacts to its holder's state after an entry, an action or the end of a turn",
    "forces_move": "state: the move index its holder must pick (Encore)",
    "wanted": "move: whether the move chooser picks this effect move now",
    "bars_status_moves": "item: its holder only picks damaging moves",
    "modify_type": "move: the move's type in this weather or terrain",
    "modify_priority": "ability, move: added to the move's priority",
    "moves_first": "item: a draw that puts its holder first in its priority bracket (holders only draw)",
    "swaps_stat": "state: the stat whose raw value stands in for another (Wonder Room)",
    "suppresses_items": "state: the held items of the Pokémon it covers do nothing (Magic Room, Embargo)",
    "modify_stat": "item, then ability: multiplies a stat after its stage (paralysis halves Speed in between)",
    "field_stat": "ability: multiplies a stat in a weather or terrain, after `modify_stat`",
    "side_stat": "state: multiplies a stat of the Pokémon on its side, last",
    "bans_move": "state: a move that cannot be used at all, after sleep and freeze and before confusion and PP",
    "bans_foe_move": "state: a move the foe facing its holder cannot use (Imprison), with `bans_move`",
    "locks_move": "item: its holder repeats the move it used",
    "retypes_move": "state: the type its holder's move takes, after the weather or terrain (Electrify)",
    "backfires": "state: a used move fails on its own user, after PP (Powder)",
    "targets_foe": "move: a status move aimed at the foe, which Protect stops",
    "stops_move": "state: a used move fails on a target on its side, after PP",
    "punishes": "state: acts on the user of a move it stopped (Spiky Shield)",
    "use": "move: a status or weather move acts instead of dealing damage",
    "heals": "move: a healing move, which Heal Block bans",
    "shields": "state: a foe's status move fails on its holder (Substitute)",
    "reflects": "state: a foe's status move bounces back to its user (Magic Coat)",
    "snatches": "state: the foe's self-targeting status move acts for its holder instead (Snatch)",
    "weather_turns": "item: how long a weather its holder starts lasts",
    "before_hit": "move: acts before the accuracy draw and the target's immunity",
    "skips_accuracy": "move: hits without an accuracy draw",
    "accuracy_as_user": "item: multiplies the user's accuracy, before the target's item",
    "accuracy_as_target": "item: multiplies the accuracy of a move used on its holder",
    "modify_accuracy": "state: multiplies the accuracy of every move, after the items",
    "exposes": "state: the type of its holder whose immunity a move type ignores, and its raised evasion (Foresight)",
    "sure_hit": "state: the moves of the given user hit its holder without an accuracy draw (Lock-On)",
    "grounds": "state: grounds every Pokémon, so Ground moves hit Flying types and Levitate",
    "lifts": "state: its holder floats over Ground moves and is not grounded (Magnet Rise)",
    "airborne": "ability: its holder is not grounded",
    "immune_to": "ability: a move type that does nothing to its holder",
    "crit_stage": "move, then item, then state: the move's critical-hit stage, then added to it",
    "guards_crit": "state: no critical hit lands on its side (the draw still happens)",
    "ignores_burn": "ability, move: a burn does not halve the user's Attack",
    "base_power": "move: the move's power in this battle state",
    "modify_power": "ability: multiplies the user's base power",
    "field_power": "state: multiplies the base power, after the ability",
    "modify_stab": "ability: replaces the same-type bonus",
    "modify_weather_boost": "move: replaces the weather's multiplier",
    "modify_damage_taken": "ability: multiplies damage its holder takes, after the weather",
    "modify_damage": "item: multiplies damage its holder deals, last",
    "screen": "state: multiplies damage to its side; the lowest one counts, and a critical hit passes it",
    "infiltrates": "ability: its holder's moves pass screens, Safeguard and Mist",
    "resists": "item: halves the first hit and is used up",
    "takes_hit": "state: takes a hit's damage in its holder's place (Substitute)",
    "endures": "state, then ability, then item: a hit that would knock its holder out leaves it 1 HP",
    "on_knocked_out": "state: acts as a foe's move knocks its holder out (Destiny Bond, Grudge)",
    "on_contact_hit": "item: hurts the user of each physical hit on its holder",
    "between_hits": "item: acts between the hits of a multi-hit move",
    "guards_ailment": "state: an ailment a Pokémon on its side cannot get, from anyone or only from a foe",
    "blocks_ailment": "ability: an ailment its holder cannot get",
    "guards_stats": "state: a foe cannot lower the stats of a Pokémon on its side",
    "on_contact": "ability: may hit back at a physical move's user once the move is over",
    "modify_drain": "item: the HP a draining move gives back",
    "after_move_as_user": "item: acts after its holder's move dealt damage, after recoil and drain",
    "after_move_as_target": "item: acts after a move dealt damage to its holder",
    "after_move": "move: acts once the damage is dealt; may return more changes",
    "faints_user": "move: its user faints once it is used",
    "switches_user_out": "move: its user switches out after a hit",
    "remember": "move: the team notes an effect move that worked, so it is not picked again",
    "blocks_weather_chip": "ability: weather does not chip its holder",
    "end_of_turn": "state, then item: heals, hurts or inflicts at the end of a turn, after weather",
    "volatile_end": "state: a Pokémon's own state acts or counts down at the end of a turn, after the items",
    "keeps_weather": "ability: the weather lasts only while a holder is out",
}


def ability(fighter, hook: str, *args, default=None):
    return call("abilities", fighter.ability, hook, *args, default=default)


def item(fighter, hook: str, *args, default=None):
    """A state that suppresses held items (Magic Room, Embargo) leaves the holder's item idle."""
    from ypoke import battle

    held = None if fighter.item is None or any(battle._field(fighter, "suppresses_items")) else fighter.item
    return call("items", held, hook, *args, default=default)


def call(kind: str, name: str | None, hook: str, *args, default=None):
    handler = _handler(kind, name, hook)
    return default if handler is None else getattr(handler, hook)(name, *args)


def has(kind: str, name: str | None, hook: str) -> bool:
    return _handler(kind, name, hook) is not None


def move(used, hook: str, *args, default=None):
    """`used` is a `battle.Move`: its `effect`, `weather` and `always_hits_in` fields name its keys, and so does its
    id for the `by_id` keys, so a hand-built move with id 0 still runs its field keys."""
    handler = _move_handler(used.effect, bool(used.weather), bool(used.always_hits_in), used.id, hook)
    return default if handler is None else getattr(handler, hook)(used, *args)


def key(kind: str, name: str, hook: str, *args, default=None):
    """Runs the handler of effect key `name` itself, if it has the hook."""
    handler = _key_handler(kind, name, hook)
    return default if handler is None else getattr(handler, hook)(name, *args)


@cache
def _key_handler(kind: str, name: str, hook: str):
    return _only((name,), kind, hook)


@cache
def _handler(kind: str, name: str | None, hook: str):
    entry = battle_data.table(kind).get(name) if name is not None else None
    return _only(battle_data.keys(entry) if entry else (), kind, hook)


@cache
def _move_handler(effect: str | None, weather: bool, always_hits: bool, move_id: int, hook: str):
    entry = battle_data.table("moves").get(str(move_id))
    handlers = loaded()["moves"]
    by_id = [key for key in battle_data.keys(entry) if key in handlers and handlers[key].by_id] if entry else []
    fields = [effect] * bool(effect) + ["weather"] * weather + ["always-hits-in"] * always_hits
    fields = [key for key in fields if key in handlers and not handlers[key].by_id]
    return _only((*fields, *by_id), "moves", hook)


def _only(keys, kind: str, hook: str):
    registry = loaded()[kind]
    found = [registry[key] for key in dict.fromkeys(keys) if key in registry]
    found = [handler for handler in found if hook in hook_names(handler)]
    if len(found) > 1:
        raise ValueError(f"{kind} keys {[handler.key for handler in found]} all run {hook}")
    return found[0] if found else None
