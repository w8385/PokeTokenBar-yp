import importlib.util
import itertools
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "generate-trainer-sprites.py"
spec = importlib.util.spec_from_file_location("generate_trainer_sprites", SCRIPT)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)

MIN_DIFFERENT_SHARE = 0.25


class TrainerSpriteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.regions = generator.gyms.regions()

    def test_every_battle_id_has_a_transparent_64px_png_in_the_assets(self):
        for region in self.regions:
            ids = [o.id for o in (*region.gyms, *region.elite, *region.hideout)] + [f"{region.id}-hidden"]
            for battle_id in ids:
                with self.subTest(battle_id):
                    image = Image.open(ROOT / "assets" / "trainers" / f"{battle_id}.png")
                    self.assertEqual(image.size, (64, 64))
                    alpha = image.convert("RGBA").getchannel("A")
                    self.assertEqual(alpha.getextrema(), (0, 255))

    def test_the_committed_assets_match_the_generator(self):
        for region in self.regions:
            for battle_id, image in generator.sprites(region).items():
                with self.subTest(battle_id):
                    stored = Image.open(ROOT / "assets" / "trainers" / f"{battle_id}.png").convert("RGBA")
                    self.assertEqual(stored.tobytes(), image.tobytes())

    def test_no_two_trainers_of_a_region_look_alike(self):
        for region in self.regions:
            sprites = generator.sprites(region)
            self.assertEqual(len(sprites), 18)
            for (a, first), (b, second) in itertools.combinations(sprites.items(), 2):
                with self.subTest(pair=(a, b)):
                    self.assertGreaterEqual(different_share(first, second), MIN_DIFFERENT_SHARE)

    def test_two_runs_write_the_same_bytes(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            for out in (first, second):
                subprocess.run([sys.executable, str(SCRIPT), "--out", out], check=True)
            names = sorted(path.name for path in Path(first).iterdir())
            self.assertEqual(names, sorted(path.name for path in Path(second).iterdir()))
            self.assertEqual(len(names), 9 * 18)
            for name in names:
                with self.subTest(name):
                    self.assertEqual((Path(first) / name).read_bytes(), (Path(second) / name).read_bytes())

    def test_genders_and_skin_tones_spread_evenly_in_every_region(self):
        for region in self.regions:
            looks = generator.cast(region).values()
            genders = [look.gender for look in looks]
            skins = {look.skin for look in looks}
            with self.subTest(region.id):
                self.assertEqual(genders.count("f"), genders.count("m"))
                self.assertEqual(skins, set(generator.SKINS))

    def test_the_two_grunts_of_an_org_differ_in_skin_and_hair(self):
        for region in self.regions:
            looks = generator.cast(region)
            first, second = (looks[o.id] for o in region.hideout if o.kind == "grunt")
            with self.subTest(region.id):
                self.assertNotEqual(first.skin, second.skin)
                self.assertNotEqual(first.hair, second.hair)


def different_share(first: Image.Image, second: Image.Image) -> float:
    a, b = first.load(), second.load()
    opaque = different = 0
    for y in range(64):
        for x in range(64):
            if a[x, y][3] or b[x, y][3]:
                opaque += 1
                different += a[x, y] != b[x, y]
    return different / opaque


if __name__ == "__main__":
    unittest.main()
