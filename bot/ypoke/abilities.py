"""Battle abilities by PokéAPI name ("huge-power"). An ability not listed here does nothing."""

LOW_HP_FRACTION = 3
LOW_HP_BOOSTED_TYPE = {"blaze": "fire", "torrent": "water", "overgrow": "grass", "swarm": "bug"}
LOW_HP_BOOST = 1.5
TECHNICIAN_MAX_POWER = 60
TECHNICIAN_BOOST = 1.5
ADAPTABILITY_STAB = 2.0
GUTS_BOOST = 1.5
ATTACK_DOUBLED = ("huge-power", "pure-power")
WEATHER_DOUBLES_SPEED = {"swift-swim": "rain", "chlorophyll": "sun", "sand-rush": "sandstorm"}
WEATHER_ON_ENTRY = {"drizzle": "rain", "drought": "sun", "sand-stream": "sandstorm", "snow-warning": "snow"}
RESISTED_TYPES = {"thick-fat": ("fire", "ice")}
IMMUNE_TYPE = {"levitate": "ground"}
AILMENT_BLOCKED = {
    "immunity": ("poison", "toxic"), "limber": ("paralysis",), "insomnia": ("sleep",), "water-veil": ("burn",),
}
CONTACT_AILMENT = {"static": "paralysis", "flame-body": "burn", "poison-point": "poison"}
CONTACT_CHANCE = 0.3

NAMES = {
    "blaze": "맹화", "torrent": "급류", "overgrow": "심록", "swarm": "벌레의알림", "intimidate": "위협",
    "levitate": "부유", "huge-power": "천하장사", "pure-power": "요가파워", "thick-fat": "두꺼운지방",
    "technician": "테크니션", "sturdy": "옹골참", "adaptability": "적응력", "guts": "근성",
    "swift-swim": "쓱쓱", "chlorophyll": "엽록소", "sand-rush": "모래헤치기", "drizzle": "잔비",
    "drought": "가뭄", "sand-stream": "모래날림", "snow-warning": "눈퍼뜨리기", "static": "정전기",
    "flame-body": "불꽃몸", "poison-point": "독가시", "immunity": "면역", "limber": "유연", "insomnia": "불면",
    "water-veil": "수의베일",
}


def entry_trigger(ability: str | None) -> bool:
    return ability == "intimidate" or ability in WEATHER_ON_ENTRY


def power_multiplier(ability: str | None, move_type: str | None, power: int, low_hp: bool) -> float:
    if ability == "technician" and power <= TECHNICIAN_MAX_POWER:
        return TECHNICIAN_BOOST
    if low_hp and move_type is not None and LOW_HP_BOOSTED_TYPE.get(ability) == move_type:
        return LOW_HP_BOOST
    return 1.0


def stat_multiplier(ability: str | None, stat: str, weather: str | None, statused: bool) -> float:
    if stat == "attack":
        if ability in ATTACK_DOUBLED:
            return 2.0
        if ability == "guts" and statused:
            return GUTS_BOOST
    if stat == "speed" and weather is not None and WEATHER_DOUBLES_SPEED.get(ability) == weather:
        return 2.0
    return 1.0


def stab(ability: str | None) -> float | None:
    return ADAPTABILITY_STAB if ability == "adaptability" else None


def damage_taken_multiplier(ability: str | None, move_type: str | None) -> float:
    return 0.5 if move_type in RESISTED_TYPES.get(ability, ()) else 1.0


def blocks_ailment(ability: str | None, ailment: str | None) -> bool:
    return ailment in AILMENT_BLOCKED.get(ability, ())


def grants_immunity(ability: str | None, move_type: str | None) -> bool:
    return move_type is not None and IMMUNE_TYPE.get(ability) == move_type
