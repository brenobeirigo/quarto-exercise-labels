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
        # The paper names no version unless asked to.
        self.assertNotIn("Version B", result.stdout)

    def test_label_is_written_on_request(self):
        result = self.render({"exam-version": "B", "exam-version-label": "true"})
        self.assertEqual(result.returncode, 0, result.stderr)
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

    def test_explanation_naming_letters_keeps_the_order(self):
        forms = [
            ("B explains 1b.", "B makes the same mistake as A."),
            ("- **A.** A explains 1a.", "Option A explains 1a."),
            ("- **D.** D explains 1d.", "**Answer:** B."),
            ("- **C.** C explains 1c.", "- C) explains 1c."),
        ]
        for old, new in forms:
            with self.subTest(form=new):
                body = question(1, "B").replace(old, new) + question(2, "C")
                result = self.render({"exam-version": "B"}, body=body)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.key(result.stdout)[0], "B")
                self.assertIn("question 1 keeps its order", result.stderr)

    def test_data_letters_do_not_pin_a_question(self):
        body = question(1, "B").replace("A explains 1a.", "A puts 70 in the C band.")
        result = self.render({"exam-version": "B"}, body=body + question(2, "C"))
        self.assertNotIn("keeps its order", result.stderr)
        self.assertNotEqual(self.key(result.stdout)[0], "B")

    def test_panels_rotate_with_their_options(self):
        def panel_question(number):
            options = "\n".join(
                f"{L}) [@lst-p{number}-{L.lower()}]{{.correct}}" if L == "A"
                else f"{L}) @lst-p{number}-{L.lower()}" for L in "ABCD")
            panels = "\n".join(f"::: {{#lst-p{number}-{L.lower()}}}\npanel {number}{L.lower()}\n:::"
                               for L in "ABCD")
            bullets = "\n".join(f"- **{L}.** {L} is panel {number}{L.lower()}." for L in "ABCD")
            return (f"## Question {number}\n\n::: {{.alpha-list}}\n{options}\n:::\n\n"
                    f":::: {{#lst-p{number} layout-ncol=\"2\"}}\n{panels}\nCaption.\n::::\n\n"
                    f"::: {{.callout-note title=\"Solution\"}}\n{bullets}\n:::\n\n")
        body = "".join(panel_question(n) for n in range(1, 5))
        result = self.render({"exam-version": "B"}, body=body)
        self.assertEqual(result.returncode, 0, result.stderr)
        moved = 0
        for number in range(1, 5):
            block = result.stdout[result.stdout.index(f"## Question {number}"):]
            options = re.findall(rf"@lst-p{number}-([a-d])", block)[:4]
            panels = re.findall(rf"panel {number}([a-d])\n", block)[:4]
            bullets = re.findall(rf"\*\*([A-D])\.\*\* \1 is panel {number}([a-d])", block)[:4]
            # Option A shows panel (a), and each bullet follows its option.
            self.assertEqual(options, panels)
            self.assertEqual([b[1] for b in bullets], options)
            moved += options[0] != "a"
        self.assertGreaterEqual(moved, 3)

    def test_bullet_options_rotate_and_key_uses_page_numbers(self):
        bullets = question(2, "A").replace("A) [option 2a]{.correct}", "- [option 2a]{.correct}")
        for letter in "BCD":
            bullets = bullets.replace(f"{letter}) option 2{letter.lower()}", f"- option 2{letter.lower()}")
        odd = "## Question 1\n\n::: {.alpha-list}\nA) one\nB) two\n:::\n\n"
        body = odd + bullets + question(3, "A") + question(4, "A") + question(5, "A")
        result = self.render({"exam-version": "B", "exercise-audience": "answers"}, body=body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("question 1 keeps its order", result.stderr)
        block = result.stdout[result.stdout.index("## Question 2"):result.stdout.index("## Question 3")]
        options = re.findall(r"option 2([a-d])", block)[:4]
        self.assertNotEqual(options[0], "a")
        # The key counts every answer list, so question 2 keeps its number.
        self.assertRegex(result.stdout, r"Key, version B:\*\* 2\u00a0[A-D]")

    @staticmethod
    def enclosed(number, correct):
        options = "\n".join(
            f"{L}) [option {number}{L.lower()}]{{.correct}}" if L == correct
            else f"{L}) option {number}{L.lower()}" for L in "ABCD")
        notes = "\n".join(f"- Explains {number}{L.lower()}." for L in "ABCD")
        return (f"## Question {number}\n\n::: {{.alpha-list}}\n{options}\n:::\n\n"
                f"::: {{.callout-note title=\"Solution\"}}\n::: {{.alpha-explanations}}\n"
                f"{notes}\n:::\n:::\n\n")

    def test_enclosed_explanations_are_labelled_without_a_version(self):
        result = self.render({}, body=self.enclosed(1, "B"))
        self.assertEqual(result.returncode, 0, result.stderr)
        for letter in "ABCD":
            self.assertIn(f"**{letter}.** Explains 1{letter.lower()}.", result.stdout)

    def test_enclosed_explanations_follow_their_options(self):
        body = "".join(self.enclosed(n, "ABCD"[n % 4]) for n in range(1, 9))
        result = self.render({"exam-version": "B"}, body=body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("keeps its order", result.stderr)
        moved = 0
        for number in range(1, 9):
            block = result.stdout[result.stdout.index(f"## Question {number}\n"):]
            block = block[:block.index("## Question", 5)] if "## Question" in block[5:] else block
            options = re.findall(rf"option {number}([a-d])", block)[:4]
            notes = re.findall(rf"\*\*([A-D])\.\*\* Explains {number}([a-d])", block)
            self.assertEqual([n[1] for n in notes], options)
            moved += options != ["a", "b", "c", "d"]
        self.assertGreaterEqual(moved, 6)

    def test_paired_options_keep_their_panels(self):
        # Both ways papers write the last pair: "(d) and (a)" and "(a) and (d)".
        for last in [("d", "a"), ("a", "d")]:
            with self.subTest(last=last):
                self.check_pairs([("a", "b"), ("b", "c"), ("c", "d"), last])

    def check_pairs(self, pairs):
        def paired(number):
            options = "\n".join(
                (f"{L}) [@lst-p{number}-{x} and @lst-p{number}-{y}]{{.correct}}" if L == "A"
                 else f"{L}) @lst-p{number}-{x} and @lst-p{number}-{y}")
                for L, (x, y) in zip("ABCD", pairs))
            panels = "\n".join(f"::: {{#lst-p{number}-{x}}}\npanel {number}{x}\n:::" for x in "abcd")
            return (f"## Question {number}\n\n::: {{.alpha-list}}\n{options}\n:::\n\n"
                    f":::: {{#lst-p{number} layout-ncol=\"2\"}}\n{panels}\nCaption.\n::::\n\n")
        body = "".join(paired(n) for n in range(1, 5))
        result = self.render({"exam-version": "B"}, body=body)
        self.assertEqual(result.returncode, 0, result.stderr)
        moved = 0
        for number in range(1, 5):
            block = result.stdout[result.stdout.index(f"## Question {number}\n"):]
            options = re.findall(rf"@lst-p{number}-([a-d]) and @lst-p{number}-([a-d])", block)[:4]
            panels = re.findall(rf"panel {number}([a-d])\n", block)[:4]
            # Slot letters: each option still names the same slots, in the same order.
            slots = {panel: "abcd"[i] for i, panel in enumerate(panels)}
            self.assertEqual([(slots[x], slots[y]) for x, y in options], pairs)
            moved += panels != ["a", "b", "c", "d"]
        self.assertGreaterEqual(moved, 2)

    def test_lettered_explanations_follow_their_options(self):
        def lettered(number, correct):
            options = "\n".join(
                f"{L}) [option {number}{L.lower()}]{{.correct}}" if L == correct
                else f"{L}) option {number}{L.lower()}" for L in "ABCD")
            notes = "\n".join(
                f"{L}) [note {number}{L.lower()}.]{{.correct}}" if L == correct
                else f"{L}) note {number}{L.lower()}." for L in "ABCD")
            return (f"## Question {number}\n\n::: {{.alpha-list}}\n{options}\n:::\n\n"
                    f"::: {{.callout-note title=\"Solution\"}}\n::: {{.alpha-explanations}}\n"
                    f"{notes}\n:::\n:::\n\n")
        body = "".join(lettered(n, "ABCD"[n % 4]) for n in range(1, 9))
        plain = self.render({}, body=body)
        # Without a version the lettered list stays as written, with no bold labels.
        self.assertNotIn("**A.**", plain.stdout)
        result = self.render({"exam-version": "B"}, body=body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("keeps its order", result.stderr)
        moved = 0
        for number in range(1, 9):
            block = result.stdout[result.stdout.index(f"## Question {number}\n"):]
            if f"## Question {number + 1}\n" in block:
                block = block[:block.index(f"## Question {number + 1}\n")]
            options = re.findall(rf"option {number}([a-d])", block)
            notes = re.findall(rf"note {number}([a-d])", block)
            self.assertEqual(notes, options)
            # The correct mark sits on the same letter in both lists.
            marked = re.findall(rf"^([A-D])\)\s+\[(?:option|note) {number}", block, re.M)
            self.assertEqual(len(marked), 2)
            self.assertEqual(marked[0], marked[1])
            moved += options != ["a", "b", "c", "d"]
        self.assertGreaterEqual(moved, 6)

    def test_invalid_label_stops_the_render(self):
        result = self.render({"exam-version": '"B C"'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exam-version must be a short label", result.stderr)


if __name__ == "__main__":
    unittest.main()
