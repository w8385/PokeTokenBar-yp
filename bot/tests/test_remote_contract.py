import json
from pathlib import Path

from ypoke import remote_buy, remote_lineup, remote_train  # noqa: F401  (registers the kinds)
from ypoke.remote_ops import OP_KINDS, UNSUPPORTED

CONTRACT = json.loads((Path(__file__).parents[1] / "contract" / "remote_ops.json").read_text())
OPS = CONTRACT["ops"]


def test_registered_kinds_are_the_contract_kinds():
    assert {"buy", "lineup", "train"} == set(OPS)
    assert set(OPS) <= set(OP_KINDS)


def test_unsupported_reason_matches():
    assert CONTRACT["unsupported_reason"] == UNSUPPORTED


def test_bot_reasons_match_the_contract():
    for kind, entry in OPS.items():
        assert sorted(OP_KINDS[kind].reasons) == entry["bot_reasons"], kind


def test_app_reasons_are_a_subset_of_the_bot_reasons():
    for kind, entry in OPS.items():
        assert set(entry["app_reasons"]) <= set(entry["bot_reasons"]), kind


def test_train_actions_match_the_contract():
    assert sorted(remote_train.ACTIONS) == OPS["train"]["actions"]


def test_train_stats_match_the_contract():
    assert sorted(remote_train.STATS) == CONTRACT["train_stats"]
