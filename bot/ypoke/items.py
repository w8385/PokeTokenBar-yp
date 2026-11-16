"""Held items: PokéAPI item slugs the battle simulation understands. Anything else is ignored."""

LEFTOVERS = "leftovers"
CHOICE_SCARF = "choice-scarf"
CHOICE_BAND = "choice-band"
CHOICE_SPECS = "choice-specs"
FOCUS_SASH = "focus-sash"
FOCUS_BAND = "focus-band"
LIFE_ORB = "life-orb"
EXPERT_BELT = "expert-belt"
ASSAULT_VEST = "assault-vest"
EVIOLITE = "eviolite"
ROCKY_HELMET = "rocky-helmet"
SITRUS_BERRY = "sitrus-berry"
LUM_BERRY = "lum-berry"
WHITE_HERB = "white-herb"
BLACK_SLUDGE = "black-sludge"
SHELL_BELL = "shell-bell"
BIG_ROOT = "big-root"
MUSCLE_BAND = "muscle-band"
WISE_GLASSES = "wise-glasses"
SCOPE_LENS = "scope-lens"
RAZOR_CLAW = "razor-claw"
QUICK_CLAW = "quick-claw"
BRIGHT_POWDER = "bright-powder"
WIDE_LENS = "wide-lens"
WEAKNESS_POLICY = "weakness-policy"
FLAME_ORB = "flame-orb"
TOXIC_ORB = "toxic-orb"
CHARCOAL = "charcoal"
STELLAR_CRYSTAL = "stellar-crystal"
OGERPON_MASKS = ("teal-mask", "wellspring-mask", "hearthflame-mask", "cornerstone-mask")

TYPE_BOOST_ITEMS = {
    CHARCOAL: "fire", "mystic-water": "water", "miracle-seed": "grass", "magnet": "electric",
    "never-melt-ice": "ice", "black-belt": "fighting", "poison-barb": "poison", "soft-sand": "ground",
    "sharp-beak": "flying", "twisted-spoon": "psychic", "silver-powder": "bug", "hard-stone": "rock",
    "spell-tag": "ghost", "dragon-fang": "dragon", "black-glasses": "dark", "metal-coat": "steel",
    "silk-scarf": "normal", "fairy-feather": "fairy",
}
WEATHER_ROCKS = {
    "heat-rock": ("sun",), "damp-rock": ("rain",), "smooth-rock": ("sandstorm",), "icy-rock": ("hail", "snow"),
}
ITEM_NAMES = {
    LEFTOVERS: "먹다남은음식", CHOICE_SCARF: "구애스카프", CHOICE_BAND: "구애머리띠", CHOICE_SPECS: "구애안경",
    FOCUS_SASH: "기합의띠", FOCUS_BAND: "기합의머리띠", LIFE_ORB: "생명의구슬", EXPERT_BELT: "달인의띠",
    ASSAULT_VEST: "돌격조끼", EVIOLITE: "진화의휘석", ROCKY_HELMET: "울퉁불퉁멧", SITRUS_BERRY: "자뭉열매",
    LUM_BERRY: "리샘열매", WHITE_HERB: "하양허브", BLACK_SLUDGE: "검은오물", SHELL_BELL: "조개껍질방울",
    BIG_ROOT: "큰뿌리", MUSCLE_BAND: "힘의머리띠", WISE_GLASSES: "박식안경", SCOPE_LENS: "초점렌즈",
    RAZOR_CLAW: "예리한손톱", QUICK_CLAW: "선제공격손톱", BRIGHT_POWDER: "반짝가루", WIDE_LENS: "광각렌즈",
    WEAKNESS_POLICY: "약점보험", FLAME_ORB: "화염구슬", TOXIC_ORB: "맹독구슬",
    CHARCOAL: "목탄", "mystic-water": "신비의물방울", "miracle-seed": "기적의씨", "magnet": "자석",
    "never-melt-ice": "녹지않는얼음", "black-belt": "검은띠", "poison-barb": "독바늘", "soft-sand": "부드러운모래",
    "sharp-beak": "예리한부리", "twisted-spoon": "휘어진스푼", "silver-powder": "은빛가루", "hard-stone": "딱딱한돌",
    "spell-tag": "저주의부적", "dragon-fang": "용의이빨", "black-glasses": "검은안경", "metal-coat": "금속코트",
    "silk-scarf": "실크스카프", "fairy-feather": "요정의깃털",
    "heat-rock": "뜨거운바위", "damp-rock": "축축한바위", "smooth-rock": "보송보송바위", "icy-rock": "차가운바위",
    "teal-mask": "벽록의가면", "wellspring-mask": "우물의가면", "hearthflame-mask": "화덕의가면",
    "cornerstone-mask": "주춧돌의가면", STELLAR_CRYSTAL: "별빛 결정",
}
CHOICE_ITEMS = frozenset({CHOICE_SCARF, CHOICE_BAND, CHOICE_SPECS})
LEFTOVERS_FRACTION = 16
BLACK_SLUDGE_HURT_FRACTION = 8
LIFE_ORB_RECOIL_FRACTION = 10
ROCKY_HELMET_FRACTION = 6
SITRUS_THRESHOLD_FRACTION = 2
SITRUS_HEAL_FRACTION = 4
SHELL_BELL_FRACTION = 8
FOCUS_BAND_CHANCE = 0.1
QUICK_CLAW_CHANCE = 0.2
CHOICE_MULTIPLIER = 1.5
VEST_MULTIPLIER = 1.5
LIFE_ORB_MULTIPLIER = 1.3
BOOST_MULTIPLIER = 1.2
BAND_MULTIPLIER = 1.1
BIG_ROOT_MULTIPLIER = 1.3
BRIGHT_POWDER_ACCURACY = 0.9
WIDE_LENS_ACCURACY = 1.1
ROCK_WEATHER_TURNS = 8
ORB_AILMENTS = {FLAME_ORB: "burn", TOXIC_ORB: "toxic"}


def known(item: str | None) -> str | None:
    return item if item in ITEM_NAMES else None


def stat_multiplier(item: str | None, key: str, can_evolve: bool = False) -> float:
    if item == CHOICE_SCARF and key == "speed" or item == CHOICE_BAND and key == "attack":
        return CHOICE_MULTIPLIER
    if item == CHOICE_SPECS and key == "special_attack" or item == ASSAULT_VEST and key == "special_defense":
        return CHOICE_MULTIPLIER
    if item == EVIOLITE and can_evolve and key in ("defense", "special_defense"):
        return CHOICE_MULTIPLIER
    return 1.0


def damage_multiplier(item: str | None, move_type: str | None, effectiveness: float, physical: bool = True) -> float:
    if item == LIFE_ORB:
        return LIFE_ORB_MULTIPLIER
    if item == EXPERT_BELT and effectiveness > 1:
        return BOOST_MULTIPLIER
    if move_type is not None and (TYPE_BOOST_ITEMS.get(item) == move_type or item in OGERPON_MASKS):
        return BOOST_MULTIPLIER
    if move_type is not None and item == (MUSCLE_BAND if physical else WISE_GLASSES):
        return BAND_MULTIPLIER
    return 1.0


def crit_stage_bonus(item: str | None) -> int:
    return 1 if item in (SCOPE_LENS, RAZOR_CLAW) else 0


def accuracy_multiplier(attacker_item: str | None, defender_item: str | None) -> float:
    return (WIDE_LENS_ACCURACY if attacker_item == WIDE_LENS else 1.0) * (
        BRIGHT_POWDER_ACCURACY if defender_item == BRIGHT_POWDER else 1.0
    )


def weather_turns(item: str | None, weather: str, default: int) -> int:
    return ROCK_WEATHER_TURNS if weather in WEATHER_ROCKS.get(item, ()) else default


def drain_heal(item: str | None, healed: int) -> int:
    return int(healed * BIG_ROOT_MULTIPLIER) if item == BIG_ROOT else healed
