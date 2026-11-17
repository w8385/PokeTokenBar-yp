import json
import statistics
from dataclasses import replace
from pathlib import Path

from ypoke import foe_items, foe_moves, gym_data, gyms, items, tera_forms
from ypoke.abilities import NAMES as ABILITY_NAMES
from ypoke.dex import NATIONAL_TOTAL, REGIONS
from ypoke.gyms import MIN_TOTAL, TEAM_SIZE, Species, usable_species
from ypoke.mega_stones import MEGA_STONES, move_mega_form_id
from ypoke.type_chart import effectiveness

BORROWED = {
    "brock", "misty", "surge", "erika", "koga", "sabrina", "blaine", "giovanni", "lance", "falkner", "bugsy",
    "whitney", "morty", "chuck", "jasmine", "pryce", "clair", "roxanne", "brawly", "wattson", "flannery", "norman",
    "winona", "tate", "liza", "wallace", "juan", "steven", "archie", "maxie", "roark", "gardenia", "maylene",
    "fantina", "byron", "candice", "volkner", "cynthia", "cyrus", "cilan", "lenora", "burgh", "elesa", "clay",
    "skyla", "brycen", "drayden", "iris", "ghetsis", "viola", "grant", "korrina", "ramos", "clemont", "valerie",
    "olympia", "wulfric", "diantha", "lysandre", "ilima", "lana", "kiawe", "mallow", "acerola", "mina", "hapu",
    "guzma", "lusamine", "milo", "nessa", "kabu", "bea", "allister", "opal", "gordie", "melony", "piers", "raihan",
    "leon", "rose", "katy", "brassius", "iono", "kofu", "larry", "ryme", "tulip", "grusha", "geeta", "nemona",
    "team rocket", "team aqua", "team magma", "team galactic", "team plasma", "team flare", "team skull",
    "team yell", "team star",
}
# Gyms whose region has too few unrelated species of the type, so an evolution line fills the rest.
SAME_LINE_GYMS = {"kalos-5", "kalos-6", "kalos-7", "alola-8"}
FACADE = 263
THIEF = 168
LEARNSETS = Path(__file__).with_name("champion_learnsets.json")


def all_opponents():
    return [
        opponent for region in gyms.regions() for opponent in (*region.gyms, *region.elite, *region.hideout)
    ]


def test_nine_regions_cover_the_national_dex_in_order():
    regions = gyms.regions()
    assert [region.id for region in regions] == list(REGIONS)
    assert regions[0].first == 1 and regions[-1].last == NATIONAL_TOTAL
    assert all(later.first == earlier.last + 1 for earlier, later in zip(regions, regions[1:]))


def test_a_region_has_eight_gyms_four_elite_members_a_champion_and_a_four_battle_hideout():
    for region in gyms.regions():
        assert [gym.id for gym in region.gyms] == [f"{region.id}-{index}" for index in range(1, 9)]
        assert [(o.id, o.kind) for o in region.elite] == [
            *((f"{region.id}-elite-{index}", "elite") for index in range(1, 5)), (f"{region.id}-champion", "champion"),
        ]
        assert [(o.id, o.kind) for o in region.hideout] == [
            (f"{region.id}-hideout-1", "grunt"), (f"{region.id}-hideout-2", "grunt"),
            (f"{region.id}-hideout-3", "admin"), (f"{region.id}-hideout-4", "boss"),
        ]


def test_every_trainer_fields_distinct_species_of_the_region_at_level_50():
    for region in gyms.regions():
        for opponent in (*region.gyms, *region.elite, *region.hideout):
            size = gyms.GYM_SIZES[opponent.index - 1] if opponent.kind == "gym" else TEAM_SIZE
            if opponent.kind == "champion":
                size = TEAM_SIZE + opponent.finale
            assert opponent.level == 50 and len(opponent.team) == size, opponent.id
            assert len(set(members(opponent))) == size, opponent.id
            assert all(region.first <= species <= region.last for species in opponent.team), opponent.id


def members(opponent):
    """The team as (species, form) pairs; a species may repeat only when every copy names its own form."""
    pairs = [(ace.species, ace.form) for ace in opponent.aces] or [(species_id, None) for species_id in opponent.team]
    return [(species_id, form if all(f for s, f in pairs if s == species_id) else None) for species_id, form in pairs]


def gym_lineup_faults(region, table):
    faults = []
    for gym in region.gyms:
        if len(gym.team) != gyms.GYM_SIZES[gym.index - 1]:
            faults.append((gym.id, "size", len(gym.team)))
        for species_id in gym.team:
            if gym.types[0] not in table[species_id].types:
                faults.append((gym.id, "off-type", species_id))
            if not region.first <= species_id <= region.last:
                faults.append((gym.id, "out of region", species_id))
            if table[species_id].excluded:
                faults.append((gym.id, "legendary, mythical or baby", species_id))
    return faults


def test_a_gym_fields_only_its_type_from_its_region_three_to_six_by_number():
    assert gyms.GYM_SIZES == (3, 3, 4, 4, 5, 5, 6, 6)
    table = gyms.species_table()
    for region in gyms.regions():
        assert gym_lineup_faults(region, table) == [], region.id


def test_the_gym_lineup_check_catches_an_off_type_out_of_region_or_missized_team():
    table = gyms.species_table()
    kanto = gyms.regions()[0]
    broken = replace(kanto.gyms[0], team=(*kanto.gyms[0].team, 6, 252))
    faults = gym_lineup_faults(replace(kanto, gyms=(broken, *kanto.gyms[1:])), table)
    assert {fault[1] for fault in faults} == {"size", "off-type", "out of region"}


def test_a_type_swapped_region_keeps_ids_and_moves_the_leader_with_the_type():
    assert gym_data.GYM_TYPES["kalos"][7] == "fairy" and gyms.find("kalos-8").trainer.name["en"] == "Frill"
    assert gym_data.GYM_TYPES["johto"][4] == "rock" and gyms.find("johto-5").trainer.name["en"] == "Cairn"


def test_an_elite_four_or_hideout_team_leads_with_its_focus_type_as_far_as_the_region_has_species_of_it():
    table = gyms.species_table()
    for region in gyms.regions():
        pool = usable_species(table, region.first, region.last)
        for opponent in (*region.elite, *region.hideout):
            if not opponent.types:
                continue
            on_type = sum(1 for species in opponent.team if set(opponent.types) & set(table[species].types))
            available = sum(1 for species in pool if set(opponent.types) & set(species.types))
            assert on_type >= min(gyms.MIN_FOCUS, gyms.FOCUS[opponent.kind], available), opponent.id


def test_a_foe_can_already_attack_and_only_a_gym_or_a_short_elite_type_fields_a_form_that_could_have_evolved():
    table = gyms.species_table()
    for opponent in all_opponents():
        if opponent.kind == "champion":
            continue
        for species_id in opponent.team:
            species = table[species_id]
            assert species.level <= 50 and not species.excluded and species.total >= MIN_TOTAL, opponent.id
            assert species_id not in gyms.QUASI_LEGENDARY, opponent.id
            evolves = [other for other in table.values() if other.parent == species_id and other.reach <= 50]
            focus = opponent.kind == "elite" and set(opponent.types) & set(species.types)
            assert opponent.kind == "gym" or focus or not evolves, opponent.id


def test_no_member_of_a_team_evolves_from_another():
    table = gyms.species_table()

    def line(species_id):
        ids = set()
        while species_id:
            ids.add(species_id)
            species_id = table[species_id].parent if species_id in table else 0
        return ids

    for opponent in all_opponents():
        if opponent.id in SAME_LINE_GYMS:
            continue
        for species_id in opponent.team:
            assert not (line(species_id) - {species_id}) & set(opponent.team), opponent.id


def test_gyms_get_stronger_with_their_number_and_the_elite_four_stand_above_the_eighth():
    table = gyms.species_table()
    regions = gyms.regions()

    def mean_total(opponents):
        return statistics.mean(table[species].total for opponent in opponents for species in opponent.team)

    by_number = [mean_total([region.gyms[number] for region in regions]) for number in range(8)]
    assert mean_total([o for g in regions for o in g.gyms[6:]]) - mean_total([o for g in regions for o in g.gyms[:2]]) >= 30
    assert by_number[0] == min(by_number)
    assert mean_total([o for region in regions for o in region.elite if o.kind == "elite"]) > by_number[-1]
    ivs = [regions[0].gyms[number].iv for number in range(8)]
    assert ivs[0] == min(ivs) and ivs[-1] == max(ivs) < regions[0].elite[0].iv <= regions[0].elite[-1].iv


def test_a_foe_fights_with_its_trainers_ivs():
    for battle_id in ("kanto-1", "kanto-8", "kanto-champion"):
        opponent = gyms.find(battle_id)
        assert all(set(member["ivs"].values()) == {opponent.iv} and len(member["ivs"]) == 6
                   for member in gyms.foe_members(opponent))
    assert gyms.find("kanto-champion").iv == 31


def test_grunts_pick_lower_totals_than_the_admin_and_the_boss():
    table = gyms.species_table()

    def average(kind):
        return statistics.mean(
            table[species].total for opponent in all_opponents() if opponent.kind == kind for species in opponent.team
        )

    assert average("champion") > average("elite") > average("grunt")
    assert average("boss") > average("admin") > average("grunt")


def test_the_strongest_member_comes_last_except_in_the_champions_hand_made_order():
    table = gyms.species_table()
    for opponent in all_opponents():
        if opponent.kind == "champion":
            continue
        totals = [table[species].total for species in opponent.team]
        assert totals == sorted(totals), opponent.id


def test_a_team_is_the_same_on_every_call_and_after_a_rebuild():
    before = {opponent.id: opponent.team for opponent in all_opponents()}
    gyms.regions.cache_clear()
    gyms._by_id.cache_clear()
    assert {opponent.id: opponent.team for opponent in all_opponents()} == before


def test_the_preview_is_the_lineup_the_battle_uses():
    opponent = gyms.find("kanto-3")
    assert [member["pokemon_id"] for member in gyms.foe_members(opponent)] == list(opponent.team)
    assert {member["level"] for member in gyms.foe_members(opponent)} == {50}
    entry = next(g for g in gyms.catalog()["regions"][0]["gyms"] if g["id"] == "kanto-3")
    assert entry["team"] == list(opponent.team) and entry["finale"] == 0


def test_the_preview_never_shows_a_champions_finale_only_counts_it():
    for region in gyms.catalog()["regions"]:
        champion = region["elite"]["battles"][-1]
        opponent = gyms.find(champion["id"])
        assert champion["finale"] == opponent.finale >= 1
        assert champion["team"] == list(opponent.team[:TEAM_SIZE])
        assert not set(opponent.team[TEAM_SIZE:]) & set(champion["team"])
        assert str(opponent.team[-1]) not in json.dumps(champion["team"])
        preview = json.dumps(champion)
        for ace in opponent.aces[TEAM_SIZE:]:
            forms = {ace.form, MEGA_STONES.get(ace.item, (None, None))[1], move_mega_form_id(ace.species, ace.moves, ace.item),
                     tera_forms.STELLAR_FORM if ace.item == items.STELLAR_CRYSTAL else None} - {None}
            assert ace.item not in preview and not any(str(form) in preview for form in forms), (region["id"], ace)


def test_every_foe_brings_its_picked_moves_and_the_champion_its_table_moves():
    for opponent in all_opponents():
        members = gyms.foe_members(opponent)
        assert all(member["learned_at"] == 100 and 1 <= len(member["moves"]) <= 4 for member in members), opponent.id
        if opponent.kind == "champion":
            entries = gym_data.CHAMPION_TEAMS[opponent.region]
            assert [tuple(member["moves"]) for member in members] == [ace.moves for ace in entries]
            assert [member["pokemon_id"] for member in members] == [ace.form or ace.species for ace in entries]
            assert [(m["ability"], m["nature"]) for m in members] == [(ace.ability, ace.nature) for ace in entries]
        else:
            assert [tuple(m["moves"]) for m in members] == [foe_moves.species(s).picked for s in opponent.team]


def item_faults(opponent):
    faults = []
    held = list(opponent.items)
    if len(set(held)) != len(held):
        faults.append((opponent.id, "duplicate", held))
    for species_id, moves, item in zip(opponent.team, opponent.moves, held, strict=True):
        if not foe_items.fires(item, gyms.holder(species_id, moves)):
            faults.append((opponent.id, "no-op", species_id, item))
    return faults


def test_every_foe_holds_an_item_that_fires_and_no_team_holds_one_twice():
    for opponent in all_opponents():
        assert len(opponent.items) == len(opponent.team) and all(opponent.items), opponent.id
        assert item_faults(opponent) == [], opponent.id


def test_no_pve_foe_holds_a_focus_band_counting_the_finale():
    assert {opponent.id: opponent.items for opponent in all_opponents() if items.FOCUS_BAND in opponent.items} == {}
    frail = dict.fromkeys(("hp", "attack", "defense", "special_attack", "special_defense", "speed"), 40)
    assert items.FOCUS_BAND not in foe_items.wishes(foe_items.Holder(10, ("bug",), frail, (), False))


def test_a_pve_team_holds_at_most_one_mega_stone_or_stellar_crystal_in_its_six_and_one_in_its_finale():
    assert {opponent.id: mega_budget_faults(opponent) for opponent in all_opponents()
            if mega_budget_faults(opponent)} == {}
    champion = gyms.find("kanto-champion")
    dragonite = champion.team.index(149)
    second_in_six = tuple("dragoninite" if index == dragonite else item for index, item in enumerate(champion.items))
    assert mega_budget_faults(replace(champion, items=second_in_six))
    assert mega_budget_faults(replace(champion, team=(*champion.team, 6), moves=(*champion.moves, champion.moves[3]),
                                      items=(*champion.items, "charizardite-y"), finale=2))


def mega_budget_faults(opponent) -> list[list[str]]:
    shown = len(opponent.shown)
    parts = (mega_capable(opponent.items[:shown]), mega_capable(opponent.items[shown:]))
    return [part for part in parts if len(part) > 1]


def mega_capable(items_held: tuple[str, ...]) -> list[str]:
    return [item for item in items_held if item in MEGA_STONES or item == items.STELLAR_CRYSTAL]


def test_no_pve_foe_carries_facade_without_an_orb_a_filler_move_or_an_off_stab_type_boost():
    assert {opponent.id: pick_faults(opponent) for opponent in all_opponents() if pick_faults(opponent)} == {}


def test_the_pick_check_catches_facade_a_filler_move_and_an_off_stab_type_boost():
    champion = gyms.find("kanto-champion")
    lead_moves = champion.moves[0]

    def with_first(moves=lead_moves, item=champion.items[0]):
        return replace(champion, moves=(moves, *champion.moves[1:]), items=(item, *champion.items[1:]))

    articuno = champion.team.index(144)
    cases = [
        with_first(moves=(*lead_moves[:3], FACADE)),
        with_first(moves=(*lead_moves[:3], THIEF)),
        replace(champion, items=tuple("black-belt" if index == articuno else item
                                      for index, item in enumerate(champion.items))),
    ]
    assert all(pick_faults(case) for case in cases)
    assert pick_faults(with_first(moves=(*lead_moves[:3], FACADE), item=items.FLAME_ORB)) == []


def pick_faults(opponent) -> list[tuple]:
    faults = []
    for species_id, moves, item in zip(opponent.team, opponent.moves, opponent.items, strict=True):
        learnable_left = foe_moves.species(species_id).learnable - set(moves) - foe_moves.FILLER
        for move_id in set(moves) & foe_moves.FILLER:
            orb_facade = move_id == FACADE and item in (items.FLAME_ORB, items.TOXIC_ORB)
            if learnable_left and not orb_facade:
                faults.append((species_id, "filler", move_id))
        if item in items.TYPE_BOOST_ITEMS and items.TYPE_BOOST_ITEMS[item] not in stab_or_strongest(species_id, moves):
            faults.append((species_id, "off-stab boost", item))
    return faults


def stab_or_strongest(species_id: int, move_ids: tuple[int, ...]) -> set[str]:
    holder = gyms.holder(species_id, move_ids)
    scores = {move: foe_moves.score(move, holder.types, holder.stats["attack"], holder.stats["special_attack"])
              for move in holder.moves}
    top = max(scores.values())
    return {move.type for move, value in scores.items() if move.type in holder.types or value == top}


def test_the_item_check_catches_a_duplicate_and_each_kind_of_no_op():
    gym = gyms.find("kanto-8")
    first = gym.team[0]
    fully_evolved = next(s for s in gym.team if not gyms.can_evolve(s))
    not_poison = next(s for s in gym.team if "poison" not in gyms.species_table()[s].types)
    lead_types = {foe_moves.move(m).type for m in gym.moves[0]}
    cases = [
        replace(gym, items=(gym.items[1], *gym.items[1:])),
        replace(gym, team=(fully_evolved, *gym.team[1:]), items=(items.EVIOLITE, *gym.items[1:])),
        replace(gym, team=(not_poison, *gym.team[1:]), items=(items.BLACK_SLUDGE, *gym.items[1:])),
        replace(gym, items=(items.FLAME_ORB, *gym.items[1:])),
        replace(gym, items=("heat-rock", *gym.items[1:])),
        replace(gym, items=("charizardite-x" if first != 6 else "gengarite", *gym.items[1:])),
        replace(gym, items=("griseous-core", *gym.items[1:])),
        replace(gym, items=("flame-plate" if "fire" not in lead_types else "splash-plate", *gym.items[1:])),
        replace(gym, items=(items.PUNCHING_GLOVE, *gym.items[1:])),
        replace(gym, items=(next(berry for berry, kind in items.RESIST_BERRIES.items()
                                 if effectiveness(kind, gyms.species_table()[first].types) <= 1), *gym.items[1:])),
        replace(gym, items=(next(i for i, t in items.TYPE_BOOST_ITEMS.items()
                                 if t not in {foe_moves.move(m).type for m in gym.moves[0]}), *gym.items[1:])),
    ]
    assert all(item_faults(case) for case in cases)


def test_a_champion_fields_its_regions_listed_legendaries_and_its_pseudo_legendary_from_a_valid_table():
    table = gyms.species_table()
    learnsets = json.loads(LEARNSETS.read_text())
    for region in gyms.regions():
        entries = gym_data.CHAMPION_TEAMS[region.id]
        listed = gym_data.CHAMPION_LEGENDARIES[region.id]
        champion = region.elite[-1]
        assert champion.types == () and champion.iv == 31
        assert 7 <= len(entries) <= 9 and champion.finale == len(entries) - TEAM_SIZE, region.id
        ids = [ace.species for ace in entries]
        assert all(region.first <= i <= region.last for i in ids), region.id
        assert set(listed) <= set(ids) and ids[-1] == listed[0], region.id
        assert not any(table[i].excluded for i in ids if i not in listed), region.id
        assert set(gym_data.PSEUDO_LEGENDARIES[region.id]) <= set(ids[:TEAM_SIZE]), region.id
        for ace in entries:
            learnset = learnsets[str(ace.form or ace.species)]
            assert 1 <= len(ace.moves) <= 4 and len(set(ace.moves)) == len(ace.moves), (region.id, ace)
            assert set(ace.moves) <= set(learnset["moves"]), (region.id, ace)
            if ace.form is None:
                attacking = {move_id for move_id in ace.moves if foe_moves.move(move_id)}
                assert attacking <= foe_moves.species(ace.species).learnable, (region.id, ace)
            assert ace.ability is None or (ace.ability in learnset["abilities"] and ace.ability in ABILITY_NAMES), ace
        assert item_faults(champion) == [], region.id


def test_the_champion_learnset_table_covers_every_member():
    learnsets = json.loads(LEARNSETS.read_text())
    wanted = {str(ace.form or ace.species) for team in gym_data.CHAMPION_TEAMS.values() for ace in team}
    assert set(learnsets) == wanted


def test_a_regions_gyms_use_eight_different_types_and_no_two_regions_share_the_order():
    orders = [gym_data.GYM_TYPES[region_id] for region_id in REGIONS]
    assert all(len(set(order)) == 8 for order in orders)
    assert len(set(orders)) == len(orders)
    for region_id in REGIONS:
        assert not set(gym_data.ELITE_TYPES[region_id]) & set(gym_data.GYM_TYPES[region_id])


def test_every_trainer_is_an_original_character_with_a_short_line_in_three_languages():
    seen = {language: [] for language in gyms.LANGUAGES}
    rows = [
        *(row for rows in gym_data.LEADERS.values() for row in rows), *(row for rows in gym_data.ELITE.values() for row in rows),
        *gym_data.CHAMPIONS.values(), *(row for org in gym_data.ORGS.values() for row in org),
    ]
    assert len(rows) == 72 + 36 + 9 + 27
    for row in rows:
        assert len(row) == 6 and all(text.strip() for text in row)
        assert all(len(line) <= 60 for line in row[3:])
        for language, name in zip(gyms.LANGUAGES, row[:3]):
            seen[language].append(name)
    assert all(len(set(names)) == len(rows) for names in seen.values())
    english = {name.lower() for name in seen["en"]} | {word.lower() for name in seen["en"] for word in name.split()}
    assert not english & BORROWED


def test_the_hideout_is_two_grunts_an_admin_and_a_boss_of_the_organizations_types():
    for region in gyms.regions():
        grunts, admin, boss = region.hideout[:2], region.hideout[2], region.hideout[3]
        assert grunts[0].trainer == grunts[1].trainer and region.org.name["ko"] in grunts[0].trainer.name["ko"]
        assert admin.trainer != boss.trainer and len({o.trainer.name["en"] for o in region.hideout}) == 3
        assert {o.types for o in region.hideout} == {region.org.types} == {gym_data.ORG_TYPES[region.id]}
        assert grunts[0].team != grunts[1].team


def test_runs_are_linked_in_order_and_gyms_stand_alone():
    for region in gyms.regions():
        for run, battles in ((region.elite_run, region.elite), (region.hideout_run, region.hideout)):
            assert [(o.run, o.step, o.steps) for o in battles] == [(run, step, len(battles)) for step in range(1, len(battles) + 1)]
            assert [gyms.next_in_run(o) for o in battles] == [o.id for o in battles[1:]] + [None]
            assert all(gyms.run_of(o) == battles for o in battles)
        assert all(gym.run is None and gyms.next_in_run(gym) is None for gym in region.gyms)
    assert len(gyms.regions()[0].elite) == 5


def test_the_catalog_is_plain_json_with_the_three_groups_per_region():
    body = json.loads(json.dumps(gyms.catalog(), ensure_ascii=False))
    kanto = body["regions"][0]
    assert [region["id"] for region in body["regions"]] == list(REGIONS)
    assert set(kanto) == {"id", "name", "first", "last", "gyms", "elite", "hideout"}
    assert set(kanto["gyms"][0]) == {"id", "kind", "index", "types", "level", "trainer", "team", "finale", "run"}
    assert kanto["gyms"][0]["run"] is None and kanto["gyms"][0]["types"] == ["water"]
    assert kanto["elite"]["badges_needed"] == 8 and kanto["elite"]["run"] == "kanto-elite"
    assert kanto["elite"]["battles"][4] == {
        **kanto["elite"]["battles"][4], "kind": "champion", "types": [],
        "run": {"id": "kanto-elite", "step": 5, "steps": 5},
    }
    assert kanto["hideout"]["org"]["types"] == ["electric", "ghost"] and kanto["hideout"]["org"]["name"]["en"]
    assert len(kanto["hideout"]["battles"]) == 4
    assert gyms.find("kanto-champion").kind == "champion" and gyms.find("kanto-hideout-4").kind == "boss"
    assert gyms.find("kanto-9") is None and gyms.find("") is None


def test_usable_species_drops_forms_with_a_stronger_one_reachable_and_unarmed_or_weak_ones():
    def species(species_id, parent, level, reach=None, excluded=False, total=400):
        return Species(species_id, ("fire",), parent, level, excluded, total, level if reach is None else reach)

    table = {
        1: species(1, 0, 1, 1), 2: species(2, 1, 16), 3: species(3, 2, 36), 4: species(4, 0, 40, 1),
        5: species(5, 0, 5, 1, excluded=True), 6: species(6, 0, 1, 1, total=MIN_TOTAL - 1),
        7: species(7, 0, 1, 1), 8: species(8, 7, 999, 7), 9: species(9, 8, 10, 10),
    }
    assert [s.id for s in usable_species(table, 1, 9)] == [3, 4, 9]
    assert [s.id for s in usable_species(table, 4, 9)] == [4, 9]
