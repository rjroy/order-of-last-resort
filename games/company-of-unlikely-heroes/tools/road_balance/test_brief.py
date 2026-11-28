import copy
import unittest

from brief import summarize


def case(name, wounded=False, status="victory", hp=(5, 5), carry=(5, 5)):
    result = {"status": status, "metrics": {}}
    if status == "victory":
        result["metrics"]["carryover_hp"] = dict(zip(("a", "b"), carry))
    return {
        "mission": name, "variant": "stock", "roster": ["a", "b"],
        "policy": "test", "wounded": wounded, "result": result,
        "opening": [{"id": hero, "hp": health, "max_hp": 5}
                    for hero, health in zip(("a", "b"), hp)]
                   + [{"id": "enemy", "hp": 2, "max_hp": 2}],
    }


class BriefTest(unittest.TestCase):
    def test_carry_and_outcomes(self):
        report = {"cases": [
            case("full"), case("hurt", carry=(5, 4)),
            case("up", True, hp=(3, 3), carry=(4, 3)),
            case("same", True, hp=(3, 3), carry=(3, 3)),
            case("down", True, hp=(3, 3), carry=(2, 3)),
            case("mixed", True, hp=(3, 3), carry=(4, 2)),
            case("loss", status="defeat"), case("cap", status="round_limit"),
        ]}
        text = summarize(report)
        self.assertIn("fresh 1 wounded / 1 full", text)
        self.assertIn("1 improved / 1 same / 1 worse / 1 mixed", text)
        self.assertIn("6 wins, 1 defeats, 1 round-limit (indeterminate)", text)

    def test_comparison_only_compares_carry_on_paired_wins(self):
        baseline = {"cases": [case("a"), case("b"), case("c", status="round_limit")]}
        result = copy.deepcopy(baseline)
        result["cases"][0]["result"]["metrics"]["carryover_hp"]["a"] = 4
        result["cases"][1]["result"] = {"status": "defeat", "metrics": {}}
        text = summarize(result, baseline)
        self.assertIn("3 matched; 1 outcome changes; 1 carryover changes among 1 wins", text)

    def test_identity_mismatch_and_duplicates_fail(self):
        report = {"cases": [case("a")]}
        for field, value in (("mission", "b"), ("variant", "other"),
                             ("roster", ["b", "a"]), ("policy", "other"),
                             ("wounded", True)):
            other = copy.deepcopy(report)
            other["cases"][0][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "identities differ"):
                summarize(report, other)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            summarize({"cases": [case("a"), case("a")]})

    def test_invalid_carry_and_outcome_fail(self):
        broken = case("a")
        del broken["result"]["metrics"]["carryover_hp"]["a"]
        with self.assertRaisesRegex(ValueError, "mismatch"):
            summarize({"cases": [broken]})
        with self.assertRaisesRegex(ValueError, "unknown outcome"):
            summarize({"cases": [case("a", status="ongoing")]})


if __name__ == "__main__":
    unittest.main()
