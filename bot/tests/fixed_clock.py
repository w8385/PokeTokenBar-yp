from datetime import UTC, datetime

NOW = datetime(2026, 11, 12, 9, 30, tzinfo=UTC)


def fixed_now() -> datetime:
    return NOW
