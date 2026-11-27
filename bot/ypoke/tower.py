"""The battle tower: endless 3-on-3 streaks at Lv50, in sets of ten battles that grow stronger, with the tower owner
at battle 20 and battle 50. The trainers, the owner and their lines are our own characters.

Everything here is pure data. An opponent comes from the run's seed and the battle number, so the bot can rebuild any
battle it handed out; its moves and items come from `foe_moves.json` like a gym trainer's. Contract: bot/API.md.
"""

import random
from dataclasses import dataclass
from functools import cache

from ypoke import foe_items, foe_moves, items
from ypoke.battle import BATTLE_LEVEL
from ypoke.entry_rules import species_id
from ypoke.gyms import (
    LANGUAGES,
    QUASI_LEGENDARY,
    Species,
    Trainer,
    _ranked,
    _related,
    can_evolve,
    holder,
    species_table,
    usable_species,
)
from ypoke.upload_server import IV_KEYS

MODES = ("entry", "rental")
TEAM_SIZE = 3
SET_SIZE = 10
OFFER_SIZE = 6
# (base-stat total the species are picked around, IVs of every stat) per set; sets past the last keep its values.
TIERS = ((430, 12), (460, 16), (490, 20), (520, 24), (550, 28), (580, 31), (610, 31))
LEGEND_SET = 5
LEGEND_MIN_TOTAL = 570
OWNER_BATTLES = {20: "silver", 50: "gold"}
MODE_NAMES = {"entry": "내 엔트리", "rental": "대여"}
TROPHY_NAMES = {"silver": "은", "gold": "금"}
TROPHY_EMOJI = {"silver": "🥈", "gold": "🥇"}
OWNER_ID = "tower-owner"
# BP for a win, per set (sets past the last keep its value), and for beating the owner.
SET_BP = (1, 2, 3, 3, 4, 4, 5)
OWNER_BP = {"silver": 10, "gold": 20}

TRAINERS = (
    ("등반가 하람", "Climber Haram", "クライマーのハラム", "한 층씩 오르면 언젠가 꼭대기야.", "One floor at a time and you reach the top.", "一階ずつ登れば、いつか頂上だ。"),
    ("정원사 미루", "Gardener Miru", "ガーデナーのミル", "잘 자란 팀은 쉽게 안 쓰러져.", "A well-grown team does not fall easily.", "よく育ったチームは簡単には倒れない。"),
    ("기관사 도윤", "Engineer Doyun", "機関士のドユン", "출발 신호다. 늦으면 못 탄다!", "That's the whistle. Miss it and you're left behind!", "発車の合図だ。遅れたら置いていくぞ！"),
    ("요리사 나래", "Chef Narae", "シェフのナレ", "불 조절이 승부를 가르지.", "Heat control decides the match.", "火加減が勝負を分けるのよ。"),
    ("천문학자 별하", "Astronomer Byeolha", "天文学者のビョルハ", "오늘 밤 별자리는 내 편이야.", "Tonight the stars are on my side.", "今夜の星座は私の味方。"),
    ("우편배달부 다온", "Courier Daon", "配達員のダオン", "이 승부도 제시간에 배달할게.", "I deliver this win on time too.", "この勝負も時間通りにお届けするよ。"),
    ("화가 은솔", "Painter Eunsol", "画家のウンソル", "네 패배를 한 폭에 담아 줄게.", "I'll paint your defeat in one stroke.", "君の負けを一枚の絵にしてあげる。"),
    ("소방관 태오", "Firefighter Taeo", "消防士のテオ", "위기일수록 침착하게.", "The worse it gets, the calmer I stay.", "ピンチほど落ち着いていくぞ。"),
    ("탐험가 리안", "Explorer Rian", "探検家のリアン", "지도에 없는 길로 간다.", "I take the roads no map shows.", "地図にない道を行く。"),
    ("사서 서하", "Librarian Seoha", "司書のソハ", "네 전법은 이미 책에서 읽었어.", "I already read your tactics in a book.", "君の戦法は本で読んだわ。"),
    ("목수 건우", "Carpenter Geonu", "大工のゴヌ", "기초가 튼튼해야 높이 쌓지.", "A strong base lets you build high.", "土台が強ければ高く積める。"),
    ("작곡가 라온", "Composer Raon", "作曲家のラオン", "이 배틀의 마지막 소절은 내 거야.", "The last bar of this battle is mine.", "このバトルの最後の小節はいただくよ。"),
)
OWNER = ("타워 주인 솔라", "Tower Keeper Sola", "タワーキーパーのソラ")
OWNER_LINES = {
    "silver": ("스무 층을 올라온 실력, 직접 확인해 볼게.", "Twenty floors up. Let me see that skill myself.",
               "二十階まで来た実力、直接確かめさせて。"),
    "gold": ("여기까지 온 도전자는 오랜만이야. 전력으로 상대할게!", "It's been a long time since anyone got this far. Full power!",
             "ここまで来た挑戦者は久しぶり。全力でいくよ！"),
}


@dataclass(frozen=True)
class Member:
    """A Pokémon of the tower at Lv50: the trainer's, the owner's or a rental. `ivs` is every stat's IV."""

    pokemon_id: int
    moves: tuple[int, ...]
    item: str
    ivs: int
    nature: str | None = None

    def battle_member(self) -> dict:
        """The party member the battle builds; `learned_at` lets it use moves learned above Lv50, like a gym foe."""
        member = {"pokemon_id": self.pokemon_id, "level": BATTLE_LEVEL, "learned_at": 100, "shiny": False,
                  "ivs": dict.fromkeys(IV_KEYS, self.ivs), "moves": list(self.moves), "held_item": self.item,
                  "can_evolve": can_evolve(species_id(self.pokemon_id))}
        return member | ({"nature": self.nature} if self.nature else {})

    def to_json(self) -> dict:
        return {"pokemon_id": self.pokemon_id, "moves": list(self.moves), "held_item": self.item, "ivs": self.ivs,
                "nature": self.nature}

    @staticmethod
    def from_json(data: dict) -> "Member":
        return Member(data["pokemon_id"], tuple(data["moves"]), data["held_item"], data["ivs"], data.get("nature"))


@dataclass(frozen=True)
class Opponent:
    """`battle` is the 1-based battle number of the streak. `sprite` names the trainer's art."""

    battle: int
    sprite: str
    trainer: Trainer
    members: tuple[Member, ...]
    trophy: str | None = None

    @property
    def kind(self) -> str:
        return "tower-owner" if self.trophy else "tower"


def set_of(battle: int) -> int:
    return (battle - 1) // SET_SIZE + 1


def tier(battle: int) -> tuple[int, int]:
    return TIERS[min(set_of(battle), len(TIERS)) - 1]


def bp_for(battle: int) -> int:
    trophy = OWNER_BATTLES.get(battle)
    return OWNER_BP[trophy] if trophy else SET_BP[min(set_of(battle), len(SET_BP)) - 1]


def opponent(run: int, battle: int) -> Opponent:
    """The trainer of battle `battle` in the run seeded `run`: the owner at 20 and 50, else three species near the
    set's target total, one or two of them legendary from set `LEGEND_SET` on."""
    if trophy := OWNER_BATTLES.get(battle):
        return Opponent(battle, OWNER_ID, Trainer(_languages(OWNER), _languages(OWNER_LINES[trophy])), owner_team(trophy),
                        trophy)
    rng = random.Random(f"tower-{run}-{battle}")
    picked = _pick(rng, battle, TEAM_SIZE, _legend_count(rng, battle))
    index = rng.randrange(len(TRAINERS))
    row = TRAINERS[index]
    return Opponent(battle, f"tower-{index + 1}", Trainer(_languages(row[:3]), _languages(row[3:])), _armed(picked, battle))


def offer(run: int, battle: int) -> tuple[Member, ...]:
    """The six rentals offered before battle `battle` of the run: the same tier as that battle's trainers."""
    rng = random.Random(f"tower-offer-{run}-{battle}")
    return _armed(_pick(rng, battle, OFFER_SIZE, _legend_count(rng, battle)), battle)


def rentable(pokemon_id: int, battle: int) -> bool:
    """Whether a rental of this species could have reached a team by battle `battle`: offered or beaten up to then."""
    allowed = _pool() | (_legends() if set_of(battle) >= LEGEND_SET else frozenset())
    return pokemon_id in {species.id for species in allowed}


def rental_member(pokemon_id: int, battle: int, moves: tuple[int, ...], item: str) -> Member:
    """A rental fights with the IVs of the battle's tier; its moves and item stay the ones it came with."""
    return Member(pokemon_id, moves, item, tier(battle)[1])


@cache
def owner_team(trophy: str) -> tuple[Member, ...]:
    """The owner's fixed three: strong non-legendaries for silver, a Mega and two legendaries for gold."""
    entries = {
        "silver": ((376, items.ASSAULT_VEST, "adamant"), (149, items.LIFE_ORB, "adamant"), (248, items.LEFTOVERS, "adamant")),
        "gold": ((376, "metagrossite", "adamant"), (381, items.CHOICE_SPECS, "timid"), (384, items.LIFE_ORB, "adamant")),
    }[trophy]
    return tuple(Member(pokemon_id, foe_moves.species(pokemon_id).picked, item, 31, nature)
                 for pokemon_id, item, nature in entries)


def team_key(members: list[dict]) -> str:
    """What stays the same for a locked entry: its national species, in order."""
    return ",".join(str(species_id(member["pokemon_id"])) for member in members)


def _legend_count(rng: random.Random, battle: int) -> int:
    extra = set_of(battle) - LEGEND_SET
    if extra < 0:
        return 0
    return 1 if extra < 2 else 1 + (rng.random() < 0.5)


def _pick(rng: random.Random, battle: int, size: int, legends: int) -> list[Species]:
    """`size` unrelated species ranked near the tier's total, `legends` of them from the legendary pool."""
    target = tier(battle)[0]
    table = species_table()
    chosen: list[Species] = []
    for pool, count in ((_legends(), legends), (_pool(), size)):
        for species in _ranked(rng, sorted(pool, key=lambda species: species.id), target):
            if len(chosen) >= size or count == 0:
                break
            if not any(species.id == other.id or _related(species.id, other.id, table) for other in chosen):
                chosen.append(species)
                count -= 1
    return chosen


def _armed(picked: list[Species], battle: int) -> tuple[Member, ...]:
    moves = [foe_moves.species(species.id).picked for species in picked]
    held = foe_items.assign([holder(species.id, picked_moves) for species, picked_moves in zip(picked, moves)])
    ivs = tier(battle)[1]
    return tuple(Member(species.id, picked_moves, item, ivs) for species, picked_moves, item in zip(picked, moves, held))


@cache
def _pool() -> frozenset[Species]:
    return frozenset(usable_species(species_table(), 1, 1025))


@cache
def _legends() -> frozenset[Species]:
    """Legendary, mythical, Ultra Beast and Paradox species strong enough to stand for a tower legend (no babies)."""
    return frozenset(
        species for species in species_table().values()
        if (species.excluded or species.id in QUASI_LEGENDARY) and species.total >= LEGEND_MIN_TOTAL
        and species.level <= BATTLE_LEVEL and _has_moves(species.id)
    )


def _has_moves(pokemon_id: int) -> bool:
    try:
        return bool(foe_moves.species(pokemon_id).picked)
    except KeyError:
        return False


def _languages(values: tuple[str, ...]) -> dict[str, str]:
    return dict(zip(LANGUAGES, values))
