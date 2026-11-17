#!/usr/bin/env python3
"""Run `swift test <args>`; fail when a `--filter` part ran no test or the run ran no test at all.

A `--filter` part that names a file or a deleted class runs nothing, and `swift test` still
exits 0. Usage: scripts/swift-test-filter.py --skip-build --filter 'ShopTests|BoxTests/testFoo'
"""
import re
import subprocess
import sys

TEST_CASE_STARTED = re.compile(r"Test Case '-\[([\w.]+) (\w+)\]' started")
PLAIN_PART = re.compile(r"\w+(/\w+)?")


def main(args):
    process = subprocess.Popen(["swift", "test", *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    executed = []
    for raw in process.stdout:
        sys.stdout.buffer.write(raw)
        sys.stdout.buffer.flush()
        match = TEST_CASE_STARTED.search(raw.decode(errors="replace"))
        if match:
            executed.append(f"{match[1]}/{match[2]}")
    exit_code = process.wait()
    if exit_code != 0:
        return exit_code
    problems = find_problems(filter_parts(args), executed)
    for problem in problems:
        print(f"swift-test-filter: {problem}", file=sys.stderr)
    return 1 if problems else 0


def filter_parts(args):
    """Top-level `|` alternatives of every `--filter` value, so a grouped `(A|B)` stays one part."""
    patterns = [value for flag, value in zip(args, args[1:]) if flag == "--filter"]
    patterns += [arg.split("=", 1)[1] for arg in args if arg.startswith("--filter=")]
    return [part for pattern in patterns for part in split_top_level(pattern)]


def find_problems(parts, executed):
    if not executed:
        return ["the run executed 0 tests"]
    problems = []
    for part in parts:
        try:
            matched = any(part_matches(part, test) for test in executed)
        except re.error as error:
            problems.append(f"--filter part '{part}' is not a valid regex ({error})")
            continue
        if not matched:
            problems.append(f"--filter part '{part}' matched no test that ran (is it an XCTest class name?)")
    return problems


def part_matches(part, test):
    """A plain `Class` or `Class/method` part must name it exactly, so `ShopTests` is not met by `MachineShopTests`."""
    if PLAIN_PART.fullmatch(part):
        test_class, test_method = test.split(".", 1)[1].split("/")
        part_class, _, part_method = part.partition("/")
        return part_class == test_class and part_method in ("", test_method)
    return re.search(part, test) is not None


def split_top_level(pattern):
    parts, start, depth, in_class, index = [], 0, 0, False, 0
    while index < len(pattern):
        char = pattern[index]
        if char == "\\":
            index += 2
            continue
        if in_class:
            in_class = char != "]"
        elif char == "[":
            in_class = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "|" and depth == 0:
            parts.append(pattern[start:index])
            start = index + 1
        index += 1
    parts.append(pattern[start:])
    return [part for part in parts if part]


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
