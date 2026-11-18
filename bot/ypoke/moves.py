"""Which moves a Pokémon brings to a battle."""

from ypoke import pokeapi
from ypoke.battle import Move
from ypoke.move_effects import EFFECTS

MAX_MOVES = 4


def battle_moves(learnable: list[dict], chosen_ids: list[int] | None) -> tuple[Move, ...]:
    """The chosen moves that are still learnable, in the chosen order; the defaults if none are."""
    by_id = {move["id"]: move for move in learnable}
    picked = [by_id[move_id] for move_id in chosen_ids or [] if move_id in by_id][:MAX_MOVES]
    if not picked:
        picked = [by_id[move_id] for move_id in default_move_ids(learnable)]
    return tuple(_move(move) for move in picked)


def from_data(move_id: int) -> Move:
    """A move that no Pokémon in the battle knows, brought in mid-battle (Metronome, Nature Power)."""
    return _move(pokeapi.data_move(move_id))


def default_move_ids(learnable: list[dict]) -> list[int]:
    """The most recently learned level-up attacking moves; weather, status, egg and machine moves are never a default.
    `learnable` is oldest first."""
    return [move["id"] for move in [
        move for move in learnable
        if not move["weather"] and move.get("damage_class") != "status" and move.get("source") not in ("machine", "egg")
    ][-MAX_MOVES:]]


def _move(move: dict) -> Move:
    return Move(
        name=move["name"],
        type=move["type"],
        power=move["power"],
        physical=move["damage_class"] == "physical",
        accuracy=move["accuracy"],
        pp=move["pp"],
        crit_stage=move["crit_rate"],
        ailment=move["ailment"],
        ailment_chance=move["ailment_chance"],
        stat_changes=tuple((change["stat"], change["change"]) for change in move["stat_changes"]),
        stat_on_user=move["stat_target"] == "user",
        stat_chance=move["stat_chance"],
        priority=move["priority"],
        weather=move["weather"],
        always_hits_in=tuple(move["always_hits_in"]),
        drain=move["drain"],
        min_hits=move["min_hits"],
        max_hits=move["max_hits"],
        effect=EFFECTS.get(move["id"]),
        id=move["id"],
    )
