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
    "on_entry_form": "item: a held-item form takes hold as its holder enters, after the hazards and Primal Reversion",
    "on_entry": "ability: acts as its holder enters, the faster entering Pokémon first, and as it Mega Evolves",
    "state_turns": "item: how long a field or side state its holder sets lasts",
    "on_update": "item: a one-use item reacts to its holder's state after an entry, an action or the end of a turn",
    "forces_move": "state: the move index its holder must pick (Encore)",
    "readied": "state: the move its holder charged last turn, used now with no PP whatever it picked (Solar Beam)",
    "wanted": "move: whether the move chooser picks this effect move now",
    "score_share": "move: the share of its damage the move chooser counts for a turn (half for a move that takes two)",
    "wasted": "move: the move chooser expects the move to fail this turn (Focus Punch against a foe that attacks)",
    "hp_paid": "move: the HP the move chooser expects its user to pay for it beyond recoil (Steel Beam, a crash on a "
               "miss)",
    "craves":"item: eating the berry now would help its holder",
    "burdens": "item: the item only hurts or hinders the given holder, so a move chooser hands it over",
    "bars_status_moves": "item: its holder only picks damaging moves",
    "modify_type": "move: the move as this weather, terrain or user changes it: its type, or its accuracy (Thunder in "
                   "sun)",
    "retypes": "ability: the type its holder's move takes after `modify_type` (Pixilate), None to keep it",
    "modify_priority": "ability, move: added to the move's priority",
    "moves_last": "ability: its holder moves last in its priority bracket with this move (Stall)",
    "moves_first": "item, then ability: a draw that puts its holder first in its priority bracket (holders only draw)",
    "swaps_stat": "state: the stat whose raw value stands in for another (Wonder Room)",
    "suppresses_items": "state: the held items of the Pokémon it covers do nothing (Magic Room, Embargo)",
    "modify_stat": "item, then ability: multiplies a stat after its stage (paralysis halves Speed in between)",
    "modify_foe_stat": "ability: multiplies a stat of the foe facing its holder, last (Sword of Ruin)",
    "modify_weight": "ability: multiplies its holder's weight (Heavy Metal)",
    "field_stat": "ability: multiplies a stat in a weather or terrain, after `modify_stat`",
    "side_stat": "state: multiplies a stat of the Pokémon on its side, last",
    "stage_factor": "ability: multiplies every stat stage change on its holder before the guards (Contrary's -1, Simple's 2)",
    "acts_asleep": "move: its user uses it while asleep (Sleep Talk); the sleep still counts down",
    "thaws_user": "move: a frozen user thaws to use it, and a frozen target it hits thaws (Scald)",
    "bans_move": "state: a move that cannot be used at all, after sleep and freeze and before confusion and PP",
    "bans_foe_move": "state: a move the foe facing its holder cannot use (Imprison), with `bans_move`",
    "skips_turn": "ability: its holder loafs around instead of acting this turn (Truant)",
    "pp_cost": "ability: the extra PP a foe's move aimed at its holder costs (Pressure)",
    "locks_move": "item, ability: its holder repeats the move it used",
    "breaks_abilities": "ability: its holder's move leaves the target's breakable ability out (Mold Breaker)",
    "suppresses_abilities": "ability: the foe's abilities do nothing while its holder is out (Neutralizing Gas)",
    "clears_weather": "ability: the weather does nothing while its holder is out (Air Lock)",
    "calls": "move: the move used in its place, after PP (Metronome); None when the call fails",
    "charges": "move: its user charges (Solar Beam) or hides (Fly) this turn and hits on the next; returns the "
                "`effect` it shows (\"\" to hit now) and the changes, or None to hit now",
    "retypes_move": "state: the type its holder's move takes, after the weather or terrain (Electrify)",
    "backfires": "state: a used move fails on its own user, after PP (Powder)",
    "fails": "move: the move fails once used, after PP and before the target's states (Burn Up from a non-Fire user)",
    "hits_later": "move: the hit lands on a later turn (Future Sight), so the user's Protean skips it",
    "before_move": "ability: acts as its holder uses a move that did not fail (Protean); returns an event",
    "targets_foe":"move: a status move aimed at the foe, which Protect stops",
    "never_misses": "move: a status move skips its accuracy draw for this user (Toxic from a Poison type)",
    "breaks_guard": "move, then the user's ability: the target's Protect or Quick Guard does not stop it (Feint, "
                    "Unseen Fist)",
    "stops_move": "state, then ability: a used move fails on a target on its side or on its holder, after PP",
    "fails_against": "ability: its holder's move fails on this target (Prankster on a Dark type)",
    "punishes": "state: acts on the user of a move it stopped (Spiky Shield)",
    "hides": "state: a move's power multiplier on its hiding holder (Earthquake on Dig), 0 when it cannot reach it",
    "reaches": "move: its power multiplier on a target hiding in the given place, 0 when it cannot reach it",
    "use": "move: a status or weather move acts instead of dealing damage; an attack fails or waits instead of its "
           "hit (Focus Punch, Bide), or returns None to deal it",
    "eaten": "item: a berry eaten on a move's order (Teatime, Stuff Cheeks) acts whatever its trigger and is used up",
    "heals": "move: a healing move, which Heal Block bans",
    "passes_substitute": "move: it passes a Substitute and hits the Pokémon behind it (Hyperspace Hole)",
    "shields": "state: a foe's status move fails on its holder (Substitute)",
    "reflects": "state, then ability: the state or ability that bounces a foe's status move back to its user (Magic "
                "Coat, Magic Bounce)",
    "snatches": "state: the state that makes the foe's self-targeting status move act for its holder (Snatch)",
    "weather_turns": "item: how long a weather its holder starts lasts",
    "ignores_ability": "move: the target's ability does nothing while the move acts, until its contact ability "
                       "(Sunsteel Strike)",
    "before_hit": "move: acts before the accuracy draw and the target's immunity",
    "crashes": "move: its user loses HP when the move meets Protect, misses or hits an immune target (High Jump Kick); "
               "returns the change",
    "own_accuracy": "move: its accuracy against this target, in place of the data's and unmoved by stages and items "
                    "(OHKO moves)",
    "skips_accuracy":"move: hits without an accuracy draw",
    "ignores_stages": "move: the target's Defense, Special Defense and evasion stages do nothing to it (Sacred Sword)",
    "hit_count": "move, then ability: how many times it hits this time, in place of the data's hit range (Beat Up, "
                 "Skill Link)",
    "expected_hits": "ability: the hits the move chooser counts on for its holder's move (Parental Bond)",
    "extra_hit_power": "ability: multiplies the power of the extra hits it gives a single-hit move (Parental Bond)",
    "skips_hit_rolls": "ability: its holder's later hits draw no accuracy (Skill Link on Triple Kick)",
    "rolls_each_hit": "move: each hit after the first draws for accuracy and a miss ends the move (Triple Kick)",
    "accuracy_as_user": "item, ability: multiplies the user's accuracy, before the target's",
    "accuracy_as_target": "item, ability: multiplies the accuracy of a move used on its holder",
    "modify_accuracy": "state: multiplies the accuracy of every move, after the items",
    "ignores_evasion": "ability: the target's evasion stage does nothing to its holder's moves (Keen Eye)",
    "ignores_foe_stages": "ability: the foe's stat stages do nothing against its holder (Unaware)",
    "sure_hits": "ability: every move its holder uses or is aimed at hits without an accuracy draw (No Guard)",
    "exposes": "state, then the foe's ability: the type of its holder whose immunity a move type ignores, and its "
               "raised evasion (Foresight, Scrappy)",
    "type_multiplier": "move: multiplies how well it hits these types, after the type chart (Freeze-Dry on Water, "
                       "Flying Press's added Flying)",
    "weakens": "state: multiplies how well a move type hits its holder (Tar Shot)",
    "sure_hit": "state: the moves of the given user hit its holder without an accuracy draw (Lock-On)",
    "grounds": "state: grounds every Pokémon, so Ground moves hit Flying types and Levitate",
    "hits_airborne": "move: a Ground move that hits a Flying type or a floating Pokémon (Thousand Arrows)",
    "lifts":"state: its holder floats over Ground moves and is not grounded (Magnet Rise)",
    "airborne": "ability: its holder is not grounded",
    "immune_to": "ability: a move that does nothing to its holder",
    "absorbs": "ability: acts on its holder when its `stops_move` stopped a foe's move (Volt Absorb); returns the "
               "changes",
    "crit_stage": "move, then item, then state, then ability: the move's critical-hit stage, then added to it",
    "always_crits": "ability: its holder's moves land a critical hit on this target (Merciless)",
    "guards_crit": "state, ability: no critical hit lands on its side or holder (the draw still happens)",
    "ignores_burn": "ability, move: a burn does not halve the user's Attack",
    "base_power": "move: the move's power in this battle state",
    "draws": "move: draws what its hits use once it lands, before `fixed_damage` and the hits (Magnitude)",
    "fixed_damage": "move: the damage each hit deals, with no roll, critical hit or modifier (Seismic Toss); the "
                    "mean when the rng is None",
    "stat_source": "move: the Pokémon whose attack stat it uses and the stats, in place of the user's and its class's "
                   "(Psyshock, Foul Play, Body Press)",
    "modify_power": "ability: multiplies the user's base power",
    "modify_foe_power": "ability: multiplies the base power of a foe's move on its holder (Dry Skin)",
    "breaks_aura": "ability: Dark Aura and Fairy Aura weaken their moves instead while its holder is out (Aura Break)",
    "field_power": "state: multiplies the base power, after the ability",
    "modify_stab": "ability: replaces the same-type bonus",
    "modify_weather_boost": "move: replaces the weather's multiplier",
    "modify_damage_taken": "ability: multiplies damage its holder takes from a foe, after the weather",
    "modify_damage_dealt": "ability: multiplies damage its holder deals a foe, with the target's ability",
    "modify_damage": "item: multiplies damage its holder deals, last",
    "screen": "state: multiplies damage to its side; the lowest one counts, and a critical hit passes it",
    "takes_more": "state: multiplies the damage a foe's move deals its holder, last (Glaive Rush)",
    "infiltrates": "ability: its holder's moves pass screens, Safeguard and Mist",
    "resists": "item: halves the first hit and is used up",
    "takes_hit": "state, then ability: takes a hit's damage in its holder's place (Substitute, Disguise)",
    "spares": "move: a hit that would knock its target out leaves it 1 HP (False Swipe)",
    "blocks_ohko": "ability: an OHKO move fails on its holder (Sturdy)",
    "endures":"state, then ability, then item: a hit that would knock its holder out leaves it 1 HP",
    "on_knocked_out": "state: acts as a foe's move knocks its holder out (Destiny Bond, Grudge)",
    "on_contact_hit": "item: hurts the user of each contact hit on its holder",
    "drops_contact": "ability, item: its holder's moves do not make contact (Long Reach, Punching Glove on punches, "
                     "Protective Pads)",
    "between_hits": "item: acts between the hits of a multi-hit move",
    "guards_ailment": "state: an ailment a Pokémon on its side cannot get, from anyone or only from a foe",
    "blocks_ailment": "ability: an ailment its holder cannot get now",
    "guards_stats": "state: a foe cannot lower the stats of a Pokémon on its side",
    "guards_stat": "ability: a foe cannot lower this stat of its holder (Clear Body, Hyper Cutter)",
    "reflects_drop": "ability: a foe's stat drop lands on the foe instead (Mirror Armor)",
    "on_stat_lowered": "ability: answers a foe lowering its holder's stat (Defiant); returns an event",
    "answers_intimidate": "ability: acts in place of Intimidate's drop (Guard Dog); returns an event",
    "after_intimidate": "ability: acts once Intimidate lowered its holder's Attack (Rattled); returns an event",
    "blocks_secondary": "ability: a foe's move's added effects do not land on its holder (Shield Dust)",
    "secondary_chance": "ability: multiplies the chance of its holder's move's added effects (Serene Grace)",
    "secondary": "move: acts on a target the hits left standing, after the ailment and stat changes, unless a "
                 "Substitute took them (flinch); returns the changes",
    "on_contact": "ability: may hit back at a contact move's user once the move is over",
    "modify_drain": "item: the HP a draining move gives back",
    "inverts_drain": "ability: a draining move on its holder hurts its user by what it would heal (Liquid Ooze)",
    "blocks_recoil": "ability: its holder takes no recoil (Rock Head)",
    "blocks_indirect": "ability: only moves' hits hurt its holder: no status, weather, hazard, recoil or item chip "
                       "(Magic Guard)",
    "after_hit": "ability: answers a damaging move that hit its holder once the move is over (Stamina); returns an "
                 "event",
    "after_hit_as_user": "ability: acts after its holder's damaging move hit (Magician); returns an event",
    "after_move_as_user": "item: acts after its holder's move dealt damage, after recoil and drain",
    "after_move_as_target": "item: acts after a move dealt damage to its holder",
    "after_move": "move: acts once the damage is dealt; may return more changes",
    "pays_hp": "move: its user pays HP once the move is used, hit or miss (Steel Beam); returns the change",
    "faints_user":"move: its user faints once it is used",
    "prevents_self_ko": "ability: a foe's move that faints its user does not (Damp)",
    "switches_user_out": "move: its user switches out after a hit",
    "remember": "move: the team notes an effect move that worked, so it is not picked again",
    "blocks_weather_chip": "ability: weather does not chip its holder",
    "cures_status": "ability: may cure its holder's status at the end of a turn, before the status hurts (Shed Skin); "
                    "returns the event",
    "end_of_turn": "state, then item, then ability: heals, hurts or inflicts at the end of a turn, after weather",
    "volatile_end": "state: a Pokémon's own state acts or counts down at the end of a turn, after the items",
    "tick_due": "state: the HP a Pokémon's own state takes from it at the next end of turn",
    "keeps_weather": "ability: the weather lasts only while a holder is out",
    "modify_status_damage": "ability: the poison or burn damage its holder takes at the end of a turn (Heatproof)",
    "status_damage": "ability: replaces its holder's poison or burn damage at the end of a turn (Poison Heal); returns "
                     "the event",
    "on_switch_out": "ability: acts as its holder leaves the field by its own move (Regenerator); returns an event",
    "idles_item": "ability: its holder's item does nothing (Klutz)",
    "unnerves": "ability: the foe facing its holder cannot eat berries (Unnerve)",
}


def ability(fighter, hook: str, *args, default=None):
    return call("abilities", fighter.ability, hook, *args, default=default)


def item(fighter, hook: str, *args, default=None):
    """A state that suppresses held items (Magic Room, Embargo) or the holder's ability (Klutz) leaves the holder's
    item idle, and a foe's ability can keep it from eating a berry (Unnerve)."""
    from ypoke import battle

    held = fighter.item
    if held is not None and (any(battle._field(fighter, "suppresses_items"))
                             or call("abilities", fighter.ability, "idles_item", default=False)
                             or battle._unnerved(fighter, held)):
        held = None
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
