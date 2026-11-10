"""Render-contract tests for the neutral-answer-ids filter."""

import json
import shutil
import subprocess
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
FILTER = REPOSITORY / "_extensions" / "neutral-answer-ids" / "neutral-answer-ids.lua"
QUARTO = shutil.which("quarto")

PAGE = (
    "See @lst-fee-correct1 and [the other](#lst-fee-wrong2).\n\n"
    "::: {#lst-fee-wrong2}\n```python\nx = 1\n```\nFirst.\n:::\n\n"
    "::: {#lst-fee-correct1}\n```python\nx = 2\n```\nSecond.\n:::\n\n"
    "## Fees {#sec-fees-correct}\n"
)


@unittest.skipUnless(QUARTO, "Quarto is required for the render-contract tests")
class NeutralAnswerIdTests(unittest.TestCase):
    def render(self, audience=None):
        front = ""
        if audience is not None:
            front = "---\nexercise-audience: " + audience + "\n---\n\n"
        return subprocess.run(
            [QUARTO, "pandoc", "--from", "markdown", "--to", "json",
             "--lua-filter", str(FILTER)],
            input=front + PAGE, text=True, encoding="utf-8",
            capture_output=True, check=False,
        )

    def test_student_ids_are_neutral_in_page_order(self):
        result = self.render("student")
        self.assertEqual(result.returncode, 0, result.stderr)
        output = result.stdout
        self.assertNotIn("lst-fee-correct1", output)
        self.assertNotIn("lst-fee-wrong2", output)
        # The wrong option comes first on the page, so it is option 1.
        blocks = json.loads(output)["blocks"]
        ids = [block["c"][0][0] for block in blocks if block["t"] == "Div"]
        self.assertEqual(ids, ["lst-option-1", "lst-option-2"])
        self.assertIn('"#lst-option-1"', output)
        self.assertIn('"lst-option-2"', output)
        # Section ids never name an option, so they stay.
        self.assertIn("sec-fees-correct", output)

    def test_answers_keep_authored_ids(self):
        result = self.render("answers")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lst-fee-correct1", result.stdout)
        self.assertNotIn("lst-option-1", result.stdout)

    def test_without_audience_or_profile_ids_are_neutral(self):
        result = self.render()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("lst-fee-correct1", result.stdout)

    def test_unknown_audience_stops_the_render(self):
        result = self.render("teacher")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exercise-audience must be student or answers", result.stderr)


if __name__ == "__main__":
    unittest.main()
