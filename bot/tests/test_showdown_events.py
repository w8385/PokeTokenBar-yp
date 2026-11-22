import json

from tools import generate_battle_data

from ypoke import battle_data, moves
from ypoke.effects import hooks
from ypoke.effects.ability_damage import sheer_forced

TABLE = json.loads((battle_data.DATA_DIR / "showdown-events.json").read_text())

# The bot hooks that stand for a Showdown event today. "condition:" is a handler of the state the entry sets.
EVENT_HOOKS = {
    "moves": {
        "onAfterSubDamage": {"after_substitute_hit"},
        "onDamage": {"spares"},
        "onAfterHit": {"after_move"},
        "onAfterMoveSecondarySelf": {"after_move"},
        "onAfterMove": {"after_move"},
        "condition:onTryPrimaryHit": {"takes_hit"},
        "condition:onDamage": {"endures"},
        "condition:onDamagingHit": set(),
        "condition:onAfterMove": set(),
    },
    "items": {
        "onAfterSubDamage": set(),
        "onDamage": {"endures"},
        "onDamagingHit": {"on_contact_hit", "after_move_as_target"},
        "onAfterMoveSecondary": {"after_move_as_target"},
        "onAfterMoveSecondarySelf": {"after_move_as_user", "after_use"},
    },
    "abilities": {
        "onDamage": {"takes_hit", "endures"},
        "onDamagingHit": {"on_contact_hit", "on_contact", "after_hit", "on_fainted_by"},
        "onSourceDamagingHit": {"after_hit_as_user"},
        "onAfterMoveSecondary": {"after_hit"},
        "onAfterMoveSecondarySelf": {"after_hit_as_user"},
    },
}

KNOWN_GAPS = {
    ("items", "air-balloon", "onAfterSubDamage"): "defect 6: a hit on a Substitute pops the balloon",
    ("moves", "core-enforcer", "onAfterSubDamage"): "defect 7: a hit on a Substitute still suppresses the ability",
    ("moves", "charge", "condition:onAfterMove"): "defect 13: Charge lasts until its user's next Electric move, the "
                                                  "bot counts two turn ends",
}

NO_HOOK_NEEDED = {
    ("moves", "flame-burst", "onAfterSubDamage"): "splashes the target's allies: doubles only",
    ("moves", "shell-side-arm", "onAfterSubDamage"): "only a hint line in Showdown's log",
    ("moves", "relic-song", "onAfterMoveSecondarySelf"): "Meloetta does not change form here (entry note)",
    ("moves", "order-up", "onAfterMoveSecondarySelf"): "no Commander in this format (entry note)",
    ("moves", "sparkling-aria", "onAfterMove"): "the cure rides Showdown's secondary; the bot cures in `secondary`",
    ("moves", "bide", "condition:onDamage"): "Bide's `use` counts the HP its user lost",
    ("moves", "counter", "condition:onDamagingHit"): "`retaliate` reads the last hit its user took",
    ("moves", "mirror-coat", "condition:onDamagingHit"): "`retaliate` reads the last hit its user took",
    ("abilities", "anger-shell", "onDamage"): "notes the hit for its onAfterMoveSecondary",
    ("abilities", "berserk", "onDamage"): "notes the hit for its onAfterMoveSecondary",
    ("abilities", "gluttony", "onDamage"): "marks the holder for its berries: `pinch_fraction`",
    ("abilities", "heatproof", "onDamage"): "burn damage at the end of a turn: `modify_status_damage`",
    ("abilities", "magic-guard", "onDamage"): "indirect damage: `blocks_indirect`",
    ("abilities", "poison-heal", "onDamage"): "poison damage at the end of a turn: `status_damage`",
    ("abilities", "rock-head", "onDamage"): "recoil: `blocks_recoil`",
}

SHEER_FORCE_GAPS = {
    "scale-shot": "defect 9: Showdown's selfBoost is no secondary, so Sheer Force does not boost it",
    **{slug: "defect 9: Showdown's secondary, so Sheer Force boosts it and drops the effect" for slug in (
        "alluring-voice", "anchor-shot", "barb-barrage", "burning-jealousy", "dire-claw", "eerie-spell",
        "psychic-noise", "salt-cure", "secret-power", "sparkling-aria", "spirit-shackle", "syrup-bomb",
        "throat-chop", "tri-attack", "zippy-zap",
    )},
}

NOT_IN_SHOWDOWN = {
    ("items", "stellar-crystal"), ("items", "teal-mask"), ("abilities", "embody-aspect"),
}


def test_the_table_is_read_at_the_commit_the_contact_flags_come_from():
    assert TABLE["commit"] == generate_battle_data.SHOWDOWN_COMMIT


def test_every_entry_the_bot_runs_is_in_the_table_or_known_to_be_missing_in_showdown():
    missing = {(kind, name) for kind in battle_data.KINDS for name, entry in battle_data.table(kind).items()
               if not battle_data.is_inert(entry) and name not in TABLE[kind]}
    assert missing == NOT_IN_SHOWDOWN


def test_every_showdown_event_of_an_entry_has_a_handler_on_its_bot_hook():
    unhandled = {
        (kind, _label(kind, name, found), event)
        for kind, name, found, event in _events()
        if not EVENT_HOOKS[kind][event] & _bot_hooks(kind, name)
    }
    assert unhandled == set(KNOWN_GAPS) | set(NO_HOOK_NEEDED)


def test_every_showdown_event_on_a_bot_entry_is_mapped_to_a_hook():
    assert {(kind, event) for kind, _, _, event in _events()} <= {
        (kind, event) for kind, events in EVENT_HOOKS.items() for event in events}


def test_sheer_force_boosts_the_moves_with_showdown_secondaries():
    bot, showdown = set(), set()
    for move_id, found in TABLE["moves"].items():
        entry = battle_data.table("moves")[move_id]
        if battle_data.is_inert(entry) or entry["class"] == "status":
            continue
        if sheer_forced(moves.from_data(int(move_id))):
            bot.add(found["slug"])
        if found["secondaries"]:
            showdown.add(found["slug"])
    assert bot ^ showdown == set(SHEER_FORCE_GAPS)


def _events():
    for kind in battle_data.KINDS:
        for name, found in TABLE[kind].items():
            if battle_data.keys(battle_data.table(kind)[name]):
                yield from ((kind, name, found, event) for event in found["events"])
                yield from ((kind, name, found, f"condition:{event}") for event in found["condition"])


def _label(kind, name, found):
    return found["slug"] if kind == "moves" else name


def _bot_hooks(kind, name):
    if kind != "moves":
        return {hook for hook in hooks.HOOKS if hooks.has(kind, name, hook)}
    move = moves.from_data(int(name))
    return {hook for hook in hooks.HOOKS if hooks._move_handler(
        move.effect, bool(move.weather), bool(move.always_hits_in), move.id, hook) is not None}
