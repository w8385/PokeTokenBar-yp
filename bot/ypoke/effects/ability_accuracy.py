"""Abilities that change whether a move lands. `holder` is a `battle._Fighter`; the numbers live in
`ypoke.abilities`."""

from ypoke import abilities, battle
from ypoke.effects import Handler, register


@register("abilities", "weather-evasion")
class WeatherEvasion(Handler):
    """Sand Veil, Snow Cloak: moves aimed at the holder land less often in `args.weather`."""

    def accuracy_as_target(self, name, move, holder):
        hidden = abilities.in_weather(battle._weather_of(holder), abilities.EVASION_WEATHER[name])
        return abilities.WEATHER_EVASION_ACCURACY if hidden else 1.0
