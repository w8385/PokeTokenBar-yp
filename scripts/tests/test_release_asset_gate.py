import fnmatch
import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UI = "Sources/PokeTokenBar/UI"
GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "t",
           "GIT_COMMITTER_EMAIL": "t@example.com", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull}
README = {"README.md": "assets/screenshot-shop.png", "README.ko.md": "assets/screenshot-shop-ko.png",
          "README.ja.md": "assets/screenshot-shop-ja.png"}


class ReleaseAssetGateTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.repo = Path(temp.name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("PTB_", "GIT_"))} | GIT_ENV
        scripts = self.repo / "scripts"
        scripts.mkdir()
        for name in ("release-asset-gate.py", "fork-release.sh"):
            shutil.copy(ROOT / "scripts" / name, scripts / name)
        self.git("init", "-q", "-b", "main")
        for readme, image in README.items():
            self.write(readme, f'<img src="{image}">\n')
        self.write(f"{UI}/ShopView.swift", "struct ShopView {}\n")
        self.write(f"{UI}/Design/Palette.swift", "enum Palette {}\n")
        self.draw("screenshot-shop", "v1")
        self.commit("feat(shop): add the shop")
        self.git("tag", "v1.0.0")

    def test_ui_feat_without_a_new_readme_image_stops_with_exit_2(self):
        self.write(f"{UI}/ShopView.swift", "struct ShopView { let eggs = 3 }\n")
        self.draw("screenshot-shop", "v2")
        self.commit("feat(shop): sell eggs")
        self.assertEqual(self.gate().returncode, 2)

    def test_ui_feat_with_a_new_image_in_every_readme_passes(self):
        self.write(f"{UI}/ShopView.swift", "struct ShopView { let eggs = 3 }\n")
        self.draw("screenshot-shop", "v2")
        self.draw("screenshot-eggs", "v1")
        self.show_in_readmes("screenshot-eggs")
        self.commit("feat(shop): sell eggs")
        result = self.gate()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_a_new_image_missing_from_one_readme_does_not_count(self):
        self.write(f"{UI}/ShopView.swift", "struct ShopView { let eggs = 3 }\n")
        self.draw("screenshot-shop", "v2")
        self.draw("screenshot-eggs", "v1")
        self.show_in_readmes("screenshot-eggs", skip="README.ja.md")
        self.commit("feat(shop): sell eggs")
        self.assertEqual(self.gate().returncode, 2)

    def test_an_app_resource_under_assets_is_not_a_readme_image(self):
        self.write(f"{UI}/ShopView.swift", "struct ShopView { let eggs = 3 }\n")
        self.draw("screenshot-shop", "v2")
        self.write("assets/trainers/kanto-1.png", "sprite")
        self.commit("feat(shop): sell eggs")
        self.assertEqual(self.gate().returncode, 2)

    def test_a_changed_screen_needs_every_language_variant_redrawn(self):
        self.write(f"{UI}/ShopView.swift", "struct ShopView { let price = 2 }\n")
        self.write("assets/screenshot-shop.png", "v2")
        self.commit("fix(shop): price")
        result = self.gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("ShopView.swift", result.stdout)
        self.draw("screenshot-shop", "v3")
        self.commit("docs: redraw the shop")
        self.assertEqual(self.gate().returncode, 0)

    def test_redrawing_another_screen_does_not_cover_a_mapped_one(self):
        self.write(f"{UI}/ShopView.swift", "struct ShopView { let price = 2 }\n")
        self.draw("screenshot-bag", "v1")
        self.commit("fix(shop): price")
        self.assertEqual(self.gate().returncode, 1)

    def test_an_unmapped_ui_file_needs_some_readme_image_changed(self):
        self.write(f"{UI}/Design/Palette.swift", "enum Palette { static let a = 1 }\n")
        self.commit("refactor: palette")
        self.assertEqual(self.gate().returncode, 1)

    def test_fork_release_stops_before_building_when_the_gate_fails(self):
        self.write(f"{UI}/ShopView.swift", "struct ShopView { let eggs = 3 }\n")
        self.commit("feat(shop): sell eggs")
        result = self.fork_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("asset gate failed", result.stderr)
        self.assertFalse((self.repo / "build-reached").exists())

    def test_fork_release_check_only_runs_the_gate_against_the_given_base(self):
        self.write(f"{UI}/ShopView.swift", "struct ShopView { let eggs = 3 }\n")
        self.commit("feat(shop): sell eggs")
        failed = self.run_script("--check-only", "v1.0.0")
        self.assertNotEqual(failed.returncode, 0)
        self.draw("screenshot-shop", "v2")
        self.draw("screenshot-eggs", "v1")
        self.show_in_readmes("screenshot-eggs")
        self.commit("docs: draw the egg shelf")
        passed = self.run_script("--check-only", "v1.0.0")
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)

    def test_fork_release_skip_flag_reaches_the_build_and_lands_in_the_notes(self):
        self.write(f"{UI}/ShopView.swift", "struct ShopView { let eggs = 3 }\n")
        self.commit("feat(shop): sell eggs")
        result = self.fork_release(PTB_ASSET_GATE_SKIP="screens reviewed by the integrator")
        self.assertTrue((self.repo / "build-reached").exists(), result.stdout + result.stderr)
        notes = (self.repo / "build/release-notes-v1.1.0.md").read_text()
        self.assertIn("README asset gate skipped: screens reviewed by the integrator", notes)

    def fork_release(self, **env):
        (self.repo / "notes.md").write_text("## New\n")
        stubs = self.repo / "stubs"
        stubs.mkdir()
        self.stub(stubs / "gh", "echo v1.0.0")
        for name in ("sign-with-key.sh", "xcode-pin.sh"):
            self.stub(self.repo / "scripts" / name, "exit 0")
        self.stub(self.repo / "scripts/build-app.sh", "touch build-reached; exit 7")
        return self.run_script("v1.1.0", "notes.md", PATH=f"{stubs}{os.pathsep}{self.env['PATH']}", **env)

    def run_script(self, *args, **env):
        return subprocess.run(["bash", "scripts/fork-release.sh", *args], cwd=self.repo, env=self.env | env,
                              capture_output=True, text=True)

    def gate(self):
        return subprocess.run(["python3", "scripts/release-asset-gate.py", "v1.0.0"], cwd=self.repo, env=self.env,
                              capture_output=True, text=True)

    def stub(self, path, body):
        path.write_text(f"#!/bin/sh\n{body}\n")
        path.chmod(0o755)

    def draw(self, family, content):
        for suffix in ("", "-ko", "-ja"):
            self.write(f"assets/{family}{suffix}.png", content)

    def show_in_readmes(self, family, skip=None):
        for readme, suffix in (("README.md", ""), ("README.ko.md", "-ko"), ("README.ja.md", "-ja")):
            if readme != skip:
                path = self.repo / readme
                path.write_text(path.read_text() + f'<img src="assets/{family}{suffix}.png">\n')

    def write(self, relative, text):
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.repo, env=self.env, check=True, capture_output=True)


class ScreenMapTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("release_asset_gate", ROOT / "scripts/release-asset-gate.py")
        self.gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.gate)

    def test_every_screen_glob_matches_a_ui_file(self):
        ui_files = [p.relative_to(ROOT / UI).as_posix() for p in (ROOT / UI).rglob("*.swift")]
        for pattern, _ in self.gate.SCREENS:
            self.assertTrue(any(fnmatch.fnmatchcase(f, pattern) for f in ui_files), pattern)

    def test_every_mapped_family_has_an_image(self):
        images = {self.gate.family_of(p.relative_to(ROOT).as_posix()) for p in (ROOT / "assets").iterdir()
                  if self.gate.README_IMAGE_RE.match(p.relative_to(ROOT).as_posix())}
        for pattern, families in self.gate.SCREENS:
            for family in families:
                self.assertIn(family, images, pattern)


if __name__ == "__main__":
    unittest.main()
