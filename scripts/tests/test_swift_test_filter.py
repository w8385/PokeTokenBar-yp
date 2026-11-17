import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/swift-test-filter.py"

SHOP_AND_BOX = """\
Test Suite 'Selected tests' started at 2026-11-17 10:00:00.000.
Test Suite 'ShopTests' started at 2026-11-17 10:00:00.001.
Test Case '-[PokeTokenBarTests.ShopTests testBuyAddsTheItem]' started.
Test Case '-[PokeTokenBarTests.ShopTests testBuyAddsTheItem]' passed (0.010 seconds).
Test Suite 'ShopTests' passed at 2026-11-17 10:00:00.020.
Test Suite 'BoxTests' started at 2026-11-17 10:00:00.021.
Test Case '-[PokeTokenBarTests.BoxTests testOnlyTheBoxDetailSlotChangesHeldItemsFromTheUI]' started.
Test Case '-[PokeTokenBarTests.BoxTests testOnlyTheBoxDetailSlotChangesHeldItemsFromTheUI]' passed (0.005 seconds).
Test Case '-[PokeTokenBarTests.BoxTests testNamesStayInEveryLanguage]' started.
Test Case '-[PokeTokenBarTests.BoxTests testNamesStayInEveryLanguage]' passed (0.005 seconds).
Test Suite 'BoxTests' passed at 2026-11-17 10:00:00.040.
Test Suite 'Selected tests' passed at 2026-11-17 10:00:00.041.
\t Executed 3 tests, with 0 failures (0 unexpected) in 0.020 (0.041) seconds
"""

NOTHING_RAN = """\
Test Suite 'Selected tests' started at 2026-11-17 10:00:00.000.
Test Suite 'Selected tests' passed at 2026-11-17 10:00:00.001.
\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
"""


class SwiftTestFilterTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        swift = self.root / "swift"
        swift.write_text('#!/bin/sh\necho "$@" > "$FAKE_SWIFT_ARGS"\ncat "$FAKE_SWIFT_OUTPUT"\nexit "$FAKE_SWIFT_EXIT"\n')
        swift.chmod(0o755)

    def run_wrapper(self, filter_value, output=SHOP_AND_BOX, swift_exit=0):
        (self.root / "output.txt").write_text(output)
        env = dict(os.environ,
                   PATH=f"{self.root}{os.pathsep}{os.environ['PATH']}",
                   FAKE_SWIFT_OUTPUT=str(self.root / "output.txt"),
                   FAKE_SWIFT_ARGS=str(self.root / "args.txt"),
                   FAKE_SWIFT_EXIT=str(swift_exit))
        return subprocess.run([sys.executable, str(SCRIPT), "--skip-build", "--filter", filter_value],
                              env=env, capture_output=True, text=True)

    def test_every_part_matched_exits_zero_and_streams_the_output(self):
        result = self.run_wrapper("ShopTests|BoxTests")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("Executed 3 tests", result.stdout)
        self.assertEqual("test --skip-build --filter ShopTests|BoxTests\n",
                         (self.root / "args.txt").read_text())

    def test_a_part_that_matched_nothing_fails_and_is_named(self):
        result = self.run_wrapper("NoSuchClassTests|ShopTests|BagTests")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("'NoSuchClassTests'", result.stderr)
        self.assertIn("'BagTests'", result.stderr)
        self.assertNotIn("'ShopTests'", result.stderr)

    def test_a_run_that_executed_zero_tests_fails(self):
        result = self.run_wrapper("ShopTests", output=NOTHING_RAN)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("executed 0 tests", result.stderr)

    def test_a_class_slash_method_part_must_name_a_method_that_ran(self):
        self.assertEqual(0, self.run_wrapper("BoxTests/testOnlyTheBoxDetailSlotChangesHeldItemsFromTheUI").returncode)
        result = self.run_wrapper("BoxTests/testRenamedAway")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("'BoxTests/testRenamedAway'", result.stderr)

    def test_a_plain_class_part_is_not_met_by_a_longer_class_name(self):
        machine_shop_only = SHOP_AND_BOX.replace("PokeTokenBarTests.ShopTests", "PokeTokenBarTests.MachineShopTests")
        result = self.run_wrapper("ShopTests|BoxTests", output=machine_shop_only)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("'ShopTests'", result.stderr)

    def test_regex_parts_with_a_grouped_alternation_stay_one_part(self):
        invariant_style = (r"/test\w*(InEvery(Supported)?Language|EveryLanguage|AllLanguages)\w*$"
                           r"|^PokeTokenBarTests\.ShopTests/")
        self.assertEqual(0, self.run_wrapper(invariant_style).returncode)
        result = self.run_wrapper(r"^PokeTokenBarTests\.Shop$|^PokeTokenBarTests\.ShopTests/")
        self.assertNotEqual(0, result.returncode)
        self.assertIn(r"'^PokeTokenBarTests\.Shop$'", result.stderr)

    def test_swift_failure_exit_code_is_passed_through(self):
        result = self.run_wrapper("ShopTests", output="error: compile failed\n", swift_exit=7)
        self.assertEqual(7, result.returncode)
        self.assertIn("compile failed", result.stdout)


if __name__ == "__main__":
    unittest.main()
