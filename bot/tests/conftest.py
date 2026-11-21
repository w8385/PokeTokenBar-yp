import threading
import time

import pytest
from fixed_clock import fixed_now

THREAD_BUDGET = 10


@pytest.fixture
def clock():
    return fixed_now


@pytest.fixture(autouse=True)
def every_thread_a_test_starts_ends():
    before = set(threading.enumerate())
    yield
    if left := threads_still_running(before, THREAD_BUDGET):
        pytest.fail(f"threads still running after the test: {left}")


def threads_still_running(before: set[threading.Thread], seconds: float) -> list[str]:
    deadline = time.monotonic() + seconds
    for thread in set(threading.enumerate()) - before:
        thread.join(max(0.0, deadline - time.monotonic()))
    return sorted(thread.name for thread in set(threading.enumerate()) - before if thread.is_alive())
