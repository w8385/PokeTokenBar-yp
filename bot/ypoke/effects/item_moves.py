"""Status moves that move, bring back, remove or eat held items. They change the battle copy (`battle._Fighter.item`
and its `combatant`), never the saved Pokémon. `user`, `foe` and `fighter` are `battle._Fighter`s."""

from dataclasses import replace

from ypoke import battle, items, move_power
from ypoke.effects import hooks, register
from ypoke.effects.conditions import reaches
from ypoke.effects.moves import StatusMove
from ypoke.effects.stats import boost_wanted, shift

CHEEKS_BOOST = (("defense", 2),)


@register("moves", "trick", "switcheroo")
class Trick(StatusMove):
    """The user and the foe swap held items; fails when neither holds one or either holds one the battle cannot move.
    Picked to hand the foe an item that burdens it, or to take the foe's while the user holds nothing, never to take
    one that would burden the user."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        if not swappable(user, foe) or not reaches(move, user, foe) or burdens(foe.item, user):
            return False
        return burdens(user.item, foe) or user.item is None

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if not swappable(user, foe):
            return "", ()
        mine, theirs = user.item, foe.item
        hold(user, theirs)
        hold(foe, mine)
        arena.log.extend((*received(user, side, turn), *received(foe, 1 - side, turn)))
        return self.key, ()


def swappable(user, foe) -> bool:
    return (user.item is not None or foe.item is not None) and movable(user) and yields(foe)


def yields(fighter) -> bool:
    """A foe can take what it holds: it is `movable` and not `kept`."""
    return movable(fighter) and not move_power.kept(fighter)


def movable(fighter) -> bool:
    """It holds nothing, or an item the battle knows that is not bound to its form."""
    if not move_power.holds_item(fighter):
        return True
    return fighter.item is not None and move_power.holds_removable_item(fighter)


def burdens(item: str | None, holder) -> bool:
    return hooks.call("items", item, "burdens", holder, default=False)


def hold(fighter, item: str | None) -> None:
    """The item stays with the fighter through a switch; a Choice lock ends with the item that set it."""
    fighter.item, fighter.item_lost, fighter.locked = item, item is None, None
    fighter.combatant = replace(fighter.combatant, item=item)
    if fighter.entered_as is not None:
        fighter.entered_as = replace(fighter.entered_as, item=item)


def received(fighter, side: int, turn: int) -> tuple:
    if fighter.item is None:
        return ()
    return (battle.ItemEffect(turn, side, fighter.combatant.name, fighter.item, "got"),)


@register("moves", "bestow")
class Bestow(StatusMove):
    """The user gives its held item to a foe that holds none, through a Substitute. Picked to hand over an item that
    burdens the foe."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return self._gives(user, foe) and burdens(user.item, foe)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if not self._gives(user, foe):
            return "", ()
        item = user.item
        hold(user, None)
        hold(foe, item)
        arena.log.extend(received(foe, 1 - side, turn))
        return self.key, ()

    @staticmethod
    def _gives(user, foe) -> bool:
        return user.item is not None and movable(user) and not move_power.holds_item(foe)


@register("moves", "recycle")
class Recycle(StatusMove):
    """The user gets back the item it used up; one taken or given away is gone. Picked when that item would help now:
    a berry only when eating it would."""

    snatchable = True

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        item = self._restorable(user)
        return item is not None and hooks.call("items", item, "craves", user, default=True)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        item = self._restorable(user)
        if item is None:
            return "", ()
        user.item = item
        arena.log.extend(received(user, side, turn))
        return self.key, ()

    @staticmethod
    def _restorable(user) -> str | None:
        return None if user.item is not None or user.item_lost else items.known(user.combatant.item)


@register("moves", "corrosive-gas")
class CorrosiveGas(StatusMove):
    """Melts away the foe's held item, any Knock Off could take. Picked when the foe holds an item that helps it."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return (foe.item is not None and self._melts(foe) and not burdens(foe.item, foe)
                and reaches(move, user, foe))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if not self._melts(foe):
            return "", ()
        if foe.item is not None:
            arena.log.append(battle.ItemEffect(turn, 1 - side, foe.combatant.name, foe.item, "lost"))
        hold(foe, None)
        return self.key, ()

    @staticmethod
    def _melts(foe) -> bool:
        return move_power.holds_removable_item(foe) and not move_power.kept(foe)


@register("moves", "teatime")
class Teatime(StatusMove):
    """Every Pokémon in battle eats its berry, whatever the berry waits for; fails when none holds one. Picked when
    the user's berry would help it and the foe's would not help the foe."""

    def wanted(self, move, team, foes, side, arena, weather):
        return craves(team.active) and not craves(foes.active)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        eaten = [event for event in (eat(user, side, turn), eat(foe, 1 - side, turn)) if event is not None]
        arena.log.extend(eaten)
        return (self.key if eaten else ""), ()


def craves(fighter) -> bool:
    return hooks.item(fighter, "craves", fighter, default=False)


def eat(fighter, side: int, turn: int):
    return hooks.item(fighter, "eaten", fighter, side, turn)


@register("moves", "stuff-cheeks")
class StuffCheeks(StatusMove):
    """The user eats its berry, whatever the berry waits for, then raises its Defense by 2; fails without a berry.
    Picked while it holds a berry that it wants to eat or its Defense can still rise usefully."""

    snatchable = True

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        edible = hooks.has("items", user.item, "eaten") and not any(battle._field(user, "suppresses_items"))
        return edible and (craves(user) or boost_wanted(CHEEKS_BOOST, user, foes.active, weather))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        event = eat(user, side, turn)
        if event is None:
            return "", ()
        arena.log.append(event)
        changes = tuple(change for key, stages in CHEEKS_BOOST if (change := shift(user, side, key, stages)))
        return self.key, changes
