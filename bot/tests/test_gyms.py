import json
import statistics

from ypoke import gym_data, gyms
from ypoke.dex import NATIONAL_TOTAL, REGIONS
from ypoke.gyms import MIN_TOTAL, TEAM_SIZE, Species, usable_species

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


def test_every_trainer_fields_six_distinct_species_of_the_region_at_level_50():
    for region in gyms.regions():
        for opponent in (*region.gyms, *region.elite, *region.hideout):
            assert opponent.level == 50 and len(opponent.team) == TEAM_SIZE, opponent.id
            assert len(set(opponent.team)) == TEAM_SIZE, opponent.id
            assert all(region.first <= species <= region.last for species in opponent.team), opponent.id


def test_a_team_leads_with_its_focus_type_as_far_as_the_region_has_species_of_it():
    table = gyms.species_table()
    for region in gyms.regions():
        pool = usable_species(table, region.first, region.last)
        for opponent in (*region.gyms, *region.elite, *region.hideout):
            if not opponent.types:
                continue
            on_type = sum(1 for species in opponent.team if set(opponent.types) & set(table[species].types))
            available = sum(1 for species in pool if set(opponent.types) & set(species.types))
            assert on_type >= min(gyms.MIN_FOCUS, gyms.FOCUS[opponent.kind], available), opponent.id


def test_a_foe_can_already_attack_and_only_a_gym_fields_a_form_that_could_have_evolved():
    table = gyms.species_table()
    for opponent in all_opponents():
        for species_id in opponent.team:
            species = table[species_id]
            assert species.level <= 50 and not species.excluded and species.total >= MIN_TOTAL, opponent.id
            evolves = [other for other in table.values() if other.parent == species_id and other.reach <= 50]
            assert opponent.kind == "gym" or not evolves, opponent.id


def test_no_member_of_a_team_evolves_from_another():
    table = gyms.species_table()

    def line(species_id):
        ids = set()
        while species_id:
            ids.add(species_id)
            species_id = table[species_id].parent if species_id in table else 0
        return ids

    for opponent in all_opponents():
        for species_id in opponent.team:
            assert not (line(species_id) - {species_id}) & set(opponent.team), opponent.id


def test_gyms_get_stronger_with_their_number_and_the_elite_four_stand_above_the_eighth():
    table = gyms.species_table()
    regions = gyms.regions()

    def mean_total(opponents):
        return statistics.mean(table[species].total for opponent in opponents for species in opponent.team)

    by_number = [mean_total([region.gyms[number] for region in regions]) for number in range(8)]
    assert by_number == sorted(by_number) and by_number[-1] - by_number[0] >= 80
    assert mean_total([o for region in regions for o in region.elite]) > by_number[-1]
    ivs = [regions[0].gyms[number].iv for number in range(8)]
    assert ivs == sorted(ivs) and ivs[0] < ivs[-1] < regions[0].elite[0].iv <= regions[0].elite[-1].iv
    for region in regions:
        assert mean_total(region.gyms[:2]) < mean_total(region.gyms[-2:]), region.id


def test_a_foe_fights_with_its_trainers_ivs():
    for battle_id in ("kanto-1", "kanto-8", "kanto-champion"):
        opponent = gyms.find(battle_id)
        assert all(set(member["ivs"].values()) == {opponent.iv} and len(member["ivs"]) == 6
                   for member in gyms.foe_members(opponent))


def test_champions_pick_high_totals_with_no_shared_first_type_and_grunts_pick_low_ones():
    table = gyms.species_table()

    def average(kind):
        return statistics.mean(
            table[species].total for opponent in all_opponents() if opponent.kind == kind for species in opponent.team
        )

    assert average("champion") > average("gym") > average("grunt")
    assert average("boss") > average("admin") > average("grunt")
    for region in gyms.regions():
        champion = region.elite[-1]
        assert champion.types == ()
        first_types = [table[species].types[0] for species in champion.team]
        assert len(set(first_types)) == len(first_types), champion.id


def test_the_strongest_member_comes_last():
    table = gyms.species_table()
    for opponent in all_opponents():
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
    assert entry["team"] == list(opponent.team)


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
    assert set(kanto["gyms"][0]) == {"id", "kind", "index", "types", "level", "trainer", "team", "run"}
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
