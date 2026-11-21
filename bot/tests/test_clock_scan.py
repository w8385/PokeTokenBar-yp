import re
from pathlib import Path

SOURCE = Path(__file__).resolve().parent.parent / "ypoke"
WALL_CLOCK = re.compile(r"\b(datetime\.(now|utcnow|today)|date\.today|time\.(time|time_ns))\s*\(")


def wall_clock_reads(root: Path) -> list[str]:
    reads = []
    for path in sorted(root.rglob("*.py")):
        if path.name == "clock.py":
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if WALL_CLOCK.search(line):
                reads.append(f"{path.relative_to(root)}:{number}: {line.strip()}")
    return reads


def test_the_bot_reads_the_wall_clock_only_in_clock_py():
    assert wall_clock_reads(SOURCE) == []


def test_the_scan_finds_each_wall_clock_spelling(tmp_path):
    source = tmp_path / "reads.py"
    source.write_text("a = datetime.now(UTC)\nb = datetime.utcnow()\nc = time.time()\nd = date.today()\n"
                      "e = time.monotonic()\nf = self._now()\n")

    assert [read.split(":")[1] for read in wall_clock_reads(tmp_path)] == ["1", "2", "3", "4"]
