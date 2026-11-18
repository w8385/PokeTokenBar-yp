"""Held-item handlers by effect key (`data/battle/items.json`). Their numbers and per-item arguments live in
`ypoke.items`; `fighter` is the holder, a `battle._Fighter`."""

from ypoke import battle, items, tera_forms
from ypoke.effects import Handler, elsewhere, hooks, register

CHOICE_STATS = {"choice-scarf": "speed", "choice-band": "attack", "choice-specs": "special_attack"}


@register("items", "form-item")
class FormItem(Handler):
    def on_entry_form(self, name, fighter, side, turn):
        form_id, kind = tera_forms.ITEM_FORMS[name][1:3]
        return battle.FormShift(turn, side, fighter.combatant.name, kind, form_id)


@register("items", "ogerpon-mask")
class OgerponMask(Handler):
    def on_entry_form(self, name, fighter, side, turn):
        form_id, stat = tera_forms.MASKS[name]
        change = None
        if fighter.stages[stat] < battle.MAX_STAGE:
            fighter.stages[stat] += 1
            change = battle.Change(side, fighter.combatant.name, stat, 1)
        return battle.FormShift(turn, side, fighter.combatant.name, "mask", form_id, change)

    def modify_damage(self, name, move_type, effectiveness, physical, punch):
        return items.BOOST_MULTIPLIER if move_type is not None else 1.0


@register("items", "sitrus-berry")
class SitrusBerry(Handler):
    def on_update(self, name, fighter, side, turn):
        if not self.between_hits(name, fighter):
            return None
        return battle.ItemHeal(turn, side, fighter.combatant.name, name, fighter.hp_percent)

    def between_hits(self, name, fighter):
        if fighter.hp * items.SITRUS_THRESHOLD_FRACTION > fighter.max_hp:
            return False
        self._eat(fighter)
        return True

    def eaten(self, name, fighter, side, turn):
        self._eat(fighter)
        return battle.ItemHeal(turn, side, fighter.combatant.name, name, fighter.hp_percent)

    def craves(self, name, fighter):
        return (fighter.max_hp - fighter.hp) * items.SITRUS_HEAL_FRACTION >= fighter.max_hp

    @staticmethod
    def _eat(fighter):
        fighter.hp = min(fighter.max_hp, fighter.hp + max(1, fighter.max_hp // items.SITRUS_HEAL_FRACTION))
        fighter.item = None


@register("items", "lum-berry")
class LumBerry(Handler):
    def on_update(self, name, fighter, side, turn):
        if not self.craves(name, fighter):
            return None
        return self.eaten(name, fighter, side, turn)

    def eaten(self, name, fighter, side, turn):
        cured = self.craves(name, fighter)
        fighter.status, fighter.confusion_left, fighter.sleep_left = None, 0, 0
        fighter.item = None
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "cure" if cured else "eaten")

    def craves(self, name, fighter):
        return fighter.status is not None or fighter.confusion_left > 0


@register("items", "white-herb")
class WhiteHerb(Handler):
    def on_update(self, name, fighter, side, turn):
        if all(stage >= 0 for stage in fighter.stages.values()):
            return None
        fighter.stages = {key: max(0, stage) for key, stage in fighter.stages.items()}
        fighter.item = None
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "restore")


@register("items", *CHOICE_STATS)
class ChoiceItem(Handler):
    def bars_status_moves(self, name):
        return True

    def burdens(self, name, holder):
        return any(not move.damaging for move in holder.combatant.moves)

    def modify_stat(self, name, stat, weather, statused, can_evolve):
        return items.CHOICE_MULTIPLIER if CHOICE_STATS[name] == stat else 1.0

    def locks_move(self, name):
        return True


@register("items", "assault-vest")
class AssaultVest(Handler):
    def bars_status_moves(self, name):
        return True

    def modify_stat(self, name, stat, weather, statused, can_evolve):
        return items.VEST_MULTIPLIER if stat == "special_defense" else 1.0


@register("items", "eviolite")
class Eviolite(Handler):
    def modify_stat(self, name, stat, weather, statused, can_evolve):
        return items.CHOICE_MULTIPLIER if can_evolve and stat in ("defense", "special_defense") else 1.0


@register("items", "quick-claw")
class QuickClaw(Handler):
    def moves_first(self, name, rng):
        return rng.random() < items.QUICK_CLAW_CHANCE


@register("items", "weather-rock")
class WeatherRock(Handler):
    def weather_turns(self, name, weather, turns):
        return items.ROCK_WEATHER_TURNS if weather in items.WEATHER_ROCKS[name] else turns


@register("items", "wide-lens")
class WideLens(Handler):
    def accuracy_as_user(self, name):
        return items.WIDE_LENS_ACCURACY


@register("items", "bright-powder")
class BrightPowder(Handler):
    def accuracy_as_target(self, name):
        return items.BRIGHT_POWDER_ACCURACY


@register("items", "scope-lens", "razor-claw")
class CritItem(Handler):
    def crit_stage(self, name):
        return 1


@register("items", "life-orb")
class LifeOrb(Handler):
    def modify_damage(self, name, move_type, effectiveness, physical, punch):
        return items.LIFE_ORB_MULTIPLIER

    def after_move_as_user(self, name, fighter, move, dealt, drained):
        fighter.hp = max(0, fighter.hp - max(1, fighter.max_hp // items.LIFE_ORB_RECOIL_FRACTION))
        return True


@register("items", "expert-belt")
class ExpertBelt(Handler):
    def modify_damage(self, name, move_type, effectiveness, physical, punch):
        return items.BOOST_MULTIPLIER if effectiveness > 1 else 1.0


@register("items", "type-boost", "plate")
class TypeBoost(Handler):
    def modify_damage(self, name, move_type, effectiveness, physical, punch):
        boosted_type = (items.PLATES if self.key == "plate" else items.TYPE_BOOST_ITEMS)[name]
        return items.BOOST_MULTIPLIER if move_type is not None and boosted_type == move_type else 1.0


@register("items", "origin-boost")
class OriginBoost(Handler):
    def modify_damage(self, name, move_type, effectiveness, physical, punch):
        boosted = move_type is not None and move_type in items.ORIGIN_BOOSTS[name]
        return items.BOOST_MULTIPLIER if boosted else 1.0


@register("items", "punching-glove")
class PunchingGlove(Handler):
    def modify_damage(self, name, move_type, effectiveness, physical, punch):
        return items.BAND_MULTIPLIER if punch else 1.0


@register("items", "muscle-band", "wise-glasses")
class Band(Handler):
    def modify_damage(self, name, move_type, effectiveness, physical, punch):
        boosted = move_type is not None and name == (items.MUSCLE_BAND if physical else items.WISE_GLASSES)
        return items.BAND_MULTIPLIER if boosted else 1.0


@register("items", "resist-berry")
class ResistBerry(Handler):
    def resists(self, name, move_type, effectiveness):
        kind = items.RESIST_BERRIES[name]
        return kind == move_type and (effectiveness > 1 or kind == "normal")

    def eaten(self, name, fighter, side, turn):
        fighter.item = None
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "eaten")


@register("items", "focus-sash")
class FocusSash(Handler):
    def endures(self, name, fighter, from_full, rng):
        if not from_full:
            return False
        fighter.item = None
        return True


@register("items", "focus-band")
class FocusBand(Handler):
    def endures(self, name, fighter, from_full, rng):
        return rng.random() < items.FOCUS_BAND_CHANCE


@register("items", "rocky-helmet")
class RockyHelmet(Handler):
    def on_contact_hit(self, name, user):
        return max(1, user.max_hp // items.ROCKY_HELMET_FRACTION)

    def after_move_as_target(self, name, fighter, move, multiplier, dealt):
        return move.physical and dealt > 0


@register("items", "big-root")
class BigRoot(Handler):
    def modify_drain(self, name, healed):
        return int(healed * items.BIG_ROOT_MULTIPLIER)

    def after_move_as_user(self, name, fighter, move, dealt, drained):
        return drained and fighter.hp > 0


@register("items", "shell-bell")
class ShellBell(Handler):
    def after_move_as_user(self, name, fighter, move, dealt, drained):
        if not 0 < fighter.hp < fighter.max_hp:
            return False
        fighter.hp = min(fighter.max_hp, fighter.hp + max(1, dealt // items.SHELL_BELL_FRACTION))
        return True


@register("items", "weakness-policy")
class WeaknessPolicy(Handler):
    def after_move_as_target(self, name, fighter, move, multiplier, dealt):
        if not (multiplier > 1 and dealt > 0 and fighter.hp > 0):
            return False
        for key in ("attack", "special_attack"):
            fighter.stages[key] = min(battle.MAX_STAGE, fighter.stages[key] + 2)
        fighter.item = None
        return True


@register("items", "leftovers")
class Leftovers(Handler):
    def end_of_turn(self, name, fighter, side, turn, rng):
        if fighter.hp >= fighter.max_hp:
            return None
        fighter.hp = min(fighter.max_hp, fighter.hp + max(1, fighter.max_hp // items.LEFTOVERS_FRACTION))
        return battle.ItemHeal(turn, side, fighter.combatant.name, name, fighter.hp_percent)


@register("items", "black-sludge")
class BlackSludge(Leftovers):
    def end_of_turn(self, name, fighter, side, turn, rng):
        if "poison" in fighter.combatant.types:
            return super().end_of_turn(name, fighter, side, turn, rng)
        fighter.hp = max(0, fighter.hp - max(1, fighter.max_hp // items.BLACK_SLUDGE_HURT_FRACTION))
        return battle.ItemHeal(turn, side, fighter.combatant.name, name, fighter.hp_percent, fighter.hp == 0)

    def burdens(self, name, holder):
        return "poison" not in holder.combatant.types


@register("items", "status-orb")
class StatusOrb(Handler):
    def end_of_turn(self, name, fighter, side, turn, rng):
        if not self.burdens(name, fighter):
            return None
        ailment = items.ORB_AILMENTS[name]
        battle._inflict(ailment, fighter, side, rng)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, ailment)

    def burdens(self, name, holder):
        ailment = items.ORB_AILMENTS[name]
        return battle._open_to(ailment, holder) and not hooks.ability(holder, "blocks_ailment", ailment, default=False)


elsewhere("items", "mega_stones: sets Combatant.mega, which battle._mega_evolve applies on entry",
          "mega-stone", "primal-orb", "ultra-burst")
elsewhere("items", "combatants and tera_forms: Terapagos' Stellar form, which shares the Mega Evolution slot",
          "stellar-crystal")
