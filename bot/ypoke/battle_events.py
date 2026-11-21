"""What a battle reports: the events of its log, in the order they happened, and its result."""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Change:
    """An effect that landed: a status (`AILMENT_IMMUNE_TYPES` key), "thaw", or a `BATTLE_STATS` key with `stages`."""

    side: int
    pokemon: str
    kind: str
    stages: int = 0


@dataclass(frozen=True)
class Action:
    """One Pokémon's turn. `move` is "" when it could not act; `blocked` says why ("paralysis", "sleep", "freeze",
    "gravity" or "confusion", the last one meaning it hurt itself). A used move a state stopped keeps its `move`,
    with `failed` and the state in `blocked` ("psychic-terrain"). `attacker_hp` / `defender_hp` are HP shares after it.
    `recovered` lists what ended before it acted ("sleep", "freeze", "confusion"). `hits` counts a multi-hit
    move's hits; `drained` means the user healed from the damage. `attacker_item` / `defender_item` name the
    held item that triggered on that side during this action (Life Orb recoil, Focus Sash). `effect` is what an
    effect move did (its effect key, or "trick-room-off"); `pivoted` means the user switched out. `via` names the
    move that called `move` (Metronome), and `move_id` is always the slot the user picked."""

    turn: int
    side: int
    attacker: str
    defender: str
    move: str
    missed: bool = False
    multiplier: float = 1.0
    critical: bool = False
    changes: tuple[Change, ...] = ()
    recoil: bool = False
    defender_hp: int = 100
    knockout: bool = False
    attacker_fainted: bool = False
    weather: str | None = None
    failed: bool = False
    blocked: str = ""
    recovered: tuple[str, ...] = ()
    hits: int = 1
    drained: bool = False
    attacker_hp: int = 100
    ability: str | None = None
    attacker_item: str = ""
    defender_item: str = ""
    effect: str = ""
    pivoted: bool = False
    move_id: int = 0
    via: str = ""
    cleared_by: str = ""


@dataclass(frozen=True)
class AbilityTrigger:
    """An ability that took effect as the Pokémon entered: it lowered the foe's stat (`change`) or started `weather`,
    which the ability `cleared_by` (Air Lock) of a Pokémon out keeps from acting."""

    side: int
    pokemon: str
    ability: str
    change: Change | None = None
    weather: str | None = None
    cleared_by: str = ""


@dataclass(frozen=True)
class AbilityField(AbilityTrigger):
    """An entry ability that started a `terrain` or `cleared` field and side states (Screen Cleaner)."""

    terrain: str | None = None
    cleared: tuple[str, ...] = ()


@dataclass(frozen=True)
class AbilityTransform(AbilityTrigger):
    """Imposter: the Pokémon became the foe `into`. `form_id` is the `/pokemon` id of the form it now shows,
    `own_form_id` the one it shows again once it leaves."""

    into: str = ""
    form_id: int | None = None
    own_form_id: int | None = None


@dataclass(frozen=True)
class AbilityRetype(AbilityTrigger):
    """Protean, Libero: the Pokémon became the type `into` as it used a move; logged after the move."""

    into: str = ""


@dataclass(frozen=True)
class AbilityEntry(AbilityTrigger):
    """Any other entry ability: what it did (`effect`, a `narration.ABILITY_EFFECT_TEXT` key, about `detail`) and the
    `changes` it made."""

    effect: str = ""
    detail: str = ""
    changes: tuple[Change, ...] = ()


@dataclass(frozen=True)
class AbilityAct:
    """An ability acting during a turn: the `changes` it made, the HP share it left its holder (`hp`) or the foe
    (`foe_hp`) with, or what else it did (`effect`, a `narration.ABILITY_EFFECT_TEXT` key, about `detail`)."""

    turn: int
    side: int
    pokemon: str
    ability: str
    changes: tuple[Change, ...] = ()
    hp: int | None = None
    fainted: bool = False
    foe: str = ""
    foe_hp: int | None = None
    foe_fainted: bool = False
    effect: str = ""
    detail: str = ""


@dataclass(frozen=True)
class FieldStart:
    """An attack that set a hazard on `side` as it hit (Stone Axe, Ceaseless Edge)."""

    turn: int
    side: int
    kind: str


@dataclass(frozen=True)
class FieldEnd:
    """A field or side state that wore off, or that `move` cleared. `side` is -1 for a state of the whole field."""

    turn: int
    kind: str
    side: int = -1
    move: str = ""


@dataclass(frozen=True)
class HazardHit:
    """An entry hazard other than Stealth Rock acting on an entering Pokémon: Spikes (`hp` is the share left), Toxic
    Spikes (`change` is the poison; `cleared` means a Poison type absorbed them) or Sticky Web (`change`)."""

    turn: int
    side: int
    pokemon: str
    hazard: str
    hp: int = 100
    fainted: bool = False
    change: Change | None = None
    cleared: bool = False


@dataclass(frozen=True)
class TerrainHeal:
    turn: int
    side: int
    pokemon: str
    hp: int


@dataclass(frozen=True)
class StatusDamage:
    """End-of-turn damage from `kind` ("burn", "poison" or "toxic")."""

    turn: int
    side: int
    pokemon: str
    hp: int
    fainted: bool
    kind: str = "burn"


@dataclass(frozen=True)
class WeatherDamage:
    turn: int
    side: int
    pokemon: str
    hp: int
    fainted: bool
    weather: str


@dataclass(frozen=True)
class WeatherEnd:
    turn: int
    weather: str


@dataclass(frozen=True)
class TrickRoomEnd:
    turn: int


@dataclass(frozen=True)
class HazardDamage:
    """Stealth Rock hurt a Pokémon as it entered; `hp` is the share left."""

    turn: int
    side: int
    pokemon: str
    hp: int
    fainted: bool


@dataclass(frozen=True)
class YawnSleep:
    """The Pokémon Yawn made drowsy last turn fell asleep at the end of `turn`."""

    turn: int
    side: int
    pokemon: str


@dataclass(frozen=True)
class VolatileTick:
    """A state on one Pokémon acted at the end of a turn or as a move landed: `kind` is its key, `hp` the share left
    (Leech Seed, Wish, a Substitute taking a hit: then the doll's), `count` a countdown it showed (Perish Song)."""

    turn: int
    side: int
    pokemon: str
    kind: str
    hp: int = 100
    fainted: bool = False
    count: int | None = None


@dataclass(frozen=True)
class VolatileEnd:
    """A state on one Pokémon wore off, or broke (a Substitute)."""

    turn: int
    side: int
    pokemon: str
    kind: str


@dataclass(frozen=True)
class SendOut:
    """A member of `side` comes in during `turn`: after a faint at the end of the turn, or right after a pivot move.
    `member` is its index in the side's roster (-1: not given)."""

    turn: int
    side: int
    pokemon: str
    member: int = -1


@dataclass(frozen=True)
class ItemHeal:
    """An item that changed HP at the end of a turn or right after a hit; `hp` is the share left (Black Sludge hurts)."""

    turn: int
    side: int
    pokemon: str
    item: str
    hp: int
    fainted: bool = False


@dataclass(frozen=True)
class ItemEffect:
    """An item that acted without moving HP: `effect` is "cure" (Lum Berry), "restore" (White Herb), "first"
    (Quick Claw) or the status a Flame or Toxic Orb inflicted ("burn", "toxic"); `changes` are the stat stages it
    moved (Liechi Berry)."""

    turn: int
    side: int
    pokemon: str
    item: str
    effect: str
    changes: tuple[Change, ...] = ()


@dataclass(frozen=True)
class MegaEvolution:
    turn: int
    side: int
    pokemon: str
    ability: str | None
    form_id: int | None = None
    kind: str = "mega"


@dataclass(frozen=True)
class FormShift:
    """A form taking hold: `kind` is "mask" (Ogerpon's mask glowed, `change` is its +1), "terastal" or "stellar"
    (Terapagos), an `ITEM_FORMS` kind ("origin", "crowned-sword", "crowned-shield"), a drive or memory slug (Genesect,
    Silvally; no `form_id`) or an ability's form kind
    (`abilities.FORMS`; "base" is the form the Pokémon entered in).
    `form_id` is the `/pokemon` id of the form shown, if it has one."""

    turn: int
    side: int
    pokemon: str
    kind: str
    form_id: int | None = None
    change: Change | None = None


Event = (
    Action | AbilityTrigger | StatusDamage | WeatherDamage | WeatherEnd | SendOut | ItemHeal | ItemEffect | MegaEvolution
    | FormShift | TrickRoomEnd | HazardDamage | YawnSleep | FieldStart | FieldEnd | HazardHit | TerrainHeal
    | VolatileTick | VolatileEnd | AbilityAct
)


@dataclass
class BattleResult:
    """`remaining` is each side's HP share per roster member at the end (None: never sent out).
    `statuses` is the status each member ended with (None: none, or never sent out)."""

    winner: int
    turns: int
    events: list[Event] = field(default_factory=list)
    remaining: tuple[tuple[int | None, ...], tuple[int | None, ...]] = ((), ())
    statuses: tuple[tuple[str | None, ...], tuple[str | None, ...]] = ((), ())
