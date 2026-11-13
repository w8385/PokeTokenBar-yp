"""Which moves a Pokémon brings to a battle."""

from ypoke.battle import Move

MAX_MOVES = 4


def battle_moves(learnable: list[dict], chosen_ids: list[int] | None) -> tuple[Move, ...]:
    """The chosen moves that are still learnable, in the chosen order; the defaults if none are."""
    by_id = {move["id"]: move for move in learnable}
    picked = [by_id[move_id] for move_id in chosen_ids or [] if move_id in by_id][:MAX_MOVES]
    if not picked:
        picked = [by_id[move_id] for move_id in default_move_ids(learnable)]
    return tuple(_move(move) for move in picked)


def default_move_ids(learnable: list[dict]) -> list[int]:
    """The most recently learned moves; `learnable` is oldest first, as `PokeAPIService.attacking_moves` returns it."""
    return [move["id"] for move in learnable[-MAX_MOVES:]]


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
    )
