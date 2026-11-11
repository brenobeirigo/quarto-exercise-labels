"""Render-contract tests for the exam-version filter."""

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
FILTER = REPOSITORY / "_extensions" / "exercise-labels" / "exam-version.lua"
QUARTO = shutil.which("quarto")


def question(number, correct, panel=False):
    options = []
    for index, letter in enumerate("ABCD"):
        text = f"@lst-q{number}-{letter.lower()}" if panel else f"option {number}{letter.lower()}"
        options.append(f"{letter}) [{text}]{{.correct}}" if letter == correct else f"{letter}) {text}")
    bullets = "\n".join(f"- **{letter}.** {letter} explains {number}{letter.lower()}."
                        for letter in "ABCD")
    return (f"## Question {number}\n\n::: {{.alpha-list}}\n" + "\n".join(options)
            + "\n:::\n\n::: {.callout-note title=\"Solution\"}\n" + bullets + "\n:::\n\n")


PAPER = "".join(question(n, "ABCD"[n % 4], panel=n in (3, 7)) for n in range(1, 13))


@unittest.skipUnless(QUARTO, "Quarto is required for the render-contract tests")
class ExamVersionTests(unittest.TestCase):
    def render(self, meta, body=PAPER, to="markdown"):
        front = "---\nsubtitle: Exam\n" + "".join(f"{k}: {v}\n" for k, v in meta.items()) + "---\n\n"
        return subprocess.run(
            [QUARTO, "pandoc", "--from", "markdown", "--to", to, "--standalone",
             "--lua-filter", str(FILTER)],
            input=front + body, text=True, encoding="utf-8", capture_output=True, check=False)

    @staticmethod
    def key(output):
        letters = []
        for block in re.findall(r"::: alpha-list\n(.*?)\n:::", output, re.S):
            lines = block.split("\n")
            letters.append("ABCD"[[i for i, line in enumerate(lines) if ".correct" in line][0]])
        return letters

    def test_without_version_the_paper_is_unchanged(self):
        plain = self.render({})
        self.assertEqual(plain.returncode, 0, plain.stderr)
        self.assertEqual(self.key(plain.stdout), ["ABCD"[n % 4] for n in range(1, 13)])
        self.assertNotIn("Version", plain.stdout)

    def test_version_moves_plain_answers_and_keeps_panels(self):
        result = self.render({"exam-version": "B"})
        self.assertEqual(result.returncode, 0, result.stderr)
        original = ["ABCD"[n % 4] for n in range(1, 13)]
        key = self.key(result.stdout)
        for number, (old, new) in enumerate(zip(original, key), 1):
            if number in (3, 7):
                self.assertEqual(new, old, f"panel question {number} moved")
            else:
                self.assertNotEqual(new, old, f"question {number} kept its letter")
        self.assertEqual({letter: key.count(letter) for letter in "ABCD"},
                         {"A": 3, "B": 3, "C": 3, "D": 3})
        self.assertIn("Version B", result.stdout)

    def test_options_rotate_and_bullets_follow(self):
        output = self.render({"exam-version": "B"}).stdout
        first = re.search(r"::: alpha-list\n(.*?)\n:::", output, re.S).group(1).split("\n")
        bullets = re.search(r"title=\"Solution\"\}\n(.*?)\n:::", output, re.S).group(1).split("\n")
        for letter, option, bullet in zip("ABCD", first, bullets):
            content = re.search(r"option 1([a-d])", option).group(1)
            # Each bullet keeps its own text and takes the letter of its option.
            self.assertIn(f"explains 1{content}.", bullet)
            self.assertTrue(bullet.startswith(f"- **{letter}.** {letter} explains"), bullet)

    def test_same_label_gives_same_key_and_labels_differ(self):
        first = self.key(self.render({"exam-version": "B"}).stdout)
        again = self.key(self.render({"exam-version": "B"}).stdout)
        other = self.key(self.render({"exam-version": "C"}).stdout)
        self.assertEqual(first, again)
        self.assertNotEqual(first, other)

    def test_key_only_in_answer_builds(self):
        answers = self.render({"exam-version": "B", "exercise-audience": "answers"}).stdout
        student = self.render({"exam-version": "B", "exercise-audience": "student"}).stdout
        self.assertIn("Key, version B:", answers)
        self.assertNotIn("Key, version", student)

    def test_explanation_naming_another_option_warns(self):
        body = question(1, "B").replace("B explains 1b.", "B makes the mistake of A.")
        result = self.render({"exam-version": "B"}, body=body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("names option A", result.stderr)

    def test_invalid_label_stops_the_render(self):
        result = self.render({"exam-version": '"B C"'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exam-version must be a short label", result.stderr)


if __name__ == "__main__":
    unittest.main()
