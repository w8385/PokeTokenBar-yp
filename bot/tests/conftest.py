import pytest
from fixed_clock import fixed_now


@pytest.fixture
def clock():
    return fixed_now
