from ypoke.moves import default_move_ids


def test_defaults_are_the_latest_attacking_moves_and_never_weather_moves():
    weathers = [None, None, "rain", None, None, None, "sun"]
    learnable = [{"id": move_id, "weather": weather} for move_id, weather in enumerate(weathers, start=1)]
    assert default_move_ids(learnable) == [2, 4, 5, 6]
    assert default_move_ids([{"id": 3, "weather": "rain"}]) == []
