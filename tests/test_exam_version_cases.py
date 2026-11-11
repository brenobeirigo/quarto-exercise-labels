"""Regression cases for the exam-version filter: one per reproduced failure."""

import re
import shutil
import subprocess
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
FILTER = REPOSITORY / "_extensions" / "exercise-labels" / "exam-version.lua"
QUARTO = shutil.which("quarto")


def plain(number, correct, solution="", heading=True, extra=""):
    """A plain four-option question under its own heading."""
    options = "\n".join(
        f"{L}) [opt {number}{L.lower()}]{{.correct}}" if L == correct
        else f"{L}) opt {number}{L.lower()}" for L in "ABCD")
    head = f"## Question {number}\n\n" if heading else ""
    note = f"::: {{.callout-note title=\"Solution\"}}\n{solution}\n:::\n\n" if solution else ""
    return f"{head}{extra}::: {{.alpha-list}}\n{options}\n:::\n\n{note}"


def panel_question(number, pairs, correct="A", solution=""):
    """Options that cite panels lst-p{number}-a..d, given as slot tuples."""
    options = []
    for L, slots in zip("ABCD", pairs):
        text = " and ".join(f"@lst-p{number}-{s}" for s in slots)
        options.append(f"{L}) [{text}]{{.correct}}" if L == correct else f"{L}) {text}")
    panels = "\n".join(f"::: {{#lst-p{number}-{s}}}\npanel {number}{s}\n:::" for s in "abcd")
    note = f"::: {{.callout-note title=\"Solution\"}}\n{solution}\n:::\n\n" if solution else ""
    return (f"## Question {number}\n\n::: {{.alpha-list}}\n" + "\n".join(options) + "\n:::\n\n"
            f":::: {{#lst-p{number} layout-ncol=\"2\"}}\n{panels}\nCaption.\n::::\n\n{note}")


def section(output, number):
    start = output.index(f"## Question {number}\n")
    nxt = output.find("## Question ", start + 5)
    return output[start:nxt if nxt > 0 else len(output)]


def correct_letter(block):
    lines = re.search(r"::: alpha-list\n(.*?)\n:::", block, re.S).group(1).split("\n")
    marked = [i for i, line in enumerate(lines) if ".correct" in line]
    return "ABCD"[marked[0]]


@unittest.skipUnless(QUARTO, "Quarto is required for the render-contract tests")
class ExamVersionCases(unittest.TestCase):
    def render(self, body, meta=None):
        meta = {"exam-version": "B"} if meta is None else meta
        front = "---\n" + "".join(f"{k}: {v}\n" for k, v in meta.items()) + "---\n\n"
        result = subprocess.run(
            [QUARTO, "pandoc", "--from", "markdown", "--to", "markdown", "--standalone", "--wrap=none",
             "--lua-filter", str(FILTER)],
            input=front + body, text=True, encoding="utf-8", capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def filler(self, start=2, count=5):
        return "".join(plain(n, "ABCD"[n % 4]) for n in range(start, start + count))

    # Panels -----------------------------------------------------------------

    def check_panels(self, pairs):
        body = panel_question(1, pairs, "A") + self.filler()
        out = self.render(body).stdout
        block = section(out, 1)
        options = re.findall(r"^[A-D]\)\s+\[?(.*)$", re.search(r"::: alpha-list\n(.*?)\n:::", block, re.S).group(1), re.M)
        panels = re.findall(r"panel 1([a-d])\n", block)
        slot = {p: "abcd"[i] for i, p in enumerate(panels)}
        written = [tuple(slot[x] for x in re.findall(r"@lst-p1-([a-d])", o)) for o in options]
        # Every letter names exactly the slots it named before, with no repeats.
        self.assertEqual(written, [tuple(p) for p in pairs])
        return block

    def test_cyclic_pairs_keep_their_slots(self):
        self.check_panels([("a", "b"), ("b", "c"), ("c", "d"), ("d", "a")])

    def test_pairs_written_a_and_d_keep_their_slots(self):
        self.check_panels([("a", "b"), ("b", "c"), ("c", "d"), ("a", "d")])

    def test_non_cyclic_pairs_never_duplicate_a_panel(self):
        self.check_panels([("a", "b"), ("c", "d"), ("a", "c"), ("b", "d")])

    def test_single_panels_keep_their_slots(self):
        block = self.check_panels([("a",), ("b",), ("c",), ("d",)])
        self.assertNotEqual(correct_letter(block), "A")

    def test_two_questions_sharing_panels_keep_their_order(self):
        shared = panel_question(1, [("a",), ("b",), ("c",), ("d",)], "A")
        second = shared.replace("## Question 1", "## Question 2").split(":::: {#lst-p1")[0]
        result = self.render(shared + second + self.filler(3))
        self.assertIn("question 1 keeps its order: another question uses the same panels", result.stderr)
        self.assertIn("question 2 keeps its order", result.stderr)

    # One question never affects another --------------------------------------

    def test_broken_question_keeps_its_explanations(self):
        labels = "- **A.** explains 2a.\n- **B.** explains 2b.\n- **C.** explains 2c.\n- **D.** explains 2d."
        broken = plain(2, "A", solution=labels).replace("[opt 2a]{.correct}", "opt 2a")
        out = self.render(plain(1, "B") + broken + self.filler(3)).stdout
        self.assertIn("- **A.** explains 2a.", section(out, 2))
        self.assertIn("- **D.** explains 2d.", section(out, 2))

    def test_data_list_in_a_statement_is_left_alone(self):
        data = "- **A.** Amsterdam\n- **B.** Berlin\n- **C.** Cologne\n- **D.** Delft\n\n"
        out = self.render(plain(1, "B") + plain(2, "C", extra=data) + self.filler(3)).stdout
        self.assertIn("- **A.** Amsterdam\n- **B.** Berlin", section(out, 2))

    def test_solution_under_a_heading_belongs_to_that_question(self):
        early = "::: {.callout-note title=\"Solution\"}\n**Answer:** B.\n:::\n\n"
        body = plain(1, "A") + plain(2, "B", extra=early) + self.filler(3)
        result = self.render(body)
        self.assertIn("question 2 keeps its order", result.stderr)
        self.assertEqual(correct_letter(section(result.stdout, 2)), "B")

    def test_one_block_with_two_answer_lists_keeps_both(self):
        both = plain(1, "B") + plain(2, "C", heading=False,
                                     solution="First: **Answer:** B. Second: **Answer:** C.")
        result = self.render(both + self.filler(3))
        self.assertIn("question 1 keeps its order: its section holds 2 answer lists", result.stderr)
        self.assertIn("question 2 keeps its order", result.stderr)

    def test_includes_are_question_blocks(self):
        body = "".join(
            f"::: {{.exercise-include}}\n{plain(n, 'ABCD'[n % 4], heading=False, solution='Fine.')}:::\n\n"
            for n in range(1, 7))
        result = self.render(body)
        self.assertNotIn("keeps its order", result.stderr)
        self.assertEqual(len(re.findall(r"\.correct", result.stdout)), 6)

    # Letters ----------------------------------------------------------------

    NAMING = [
        "**Answer:** B.", "**Answer: B.**", "The correct answer is B.", "Option **B** is right.",
        "*Option B* is right.", "See (B): it resets.", "Only B resets the counter.",
        "A is wrong because it never resets.", "B makes the same mistake as A.",
        "It was explained in C.", "Besides the error in B, it fails.",
        "A includes the invalid Sub declaration. B includes both faulty ones.",
        "| Option | Effect |\n|---|---|\n| B | resets the counter |",
        "B\n:   resets the counter", "#### Why B",
        "- **A.** B with an extra reset.\n- **B.** b.\n- **C.** c.\n- **D.** d.",
        "* A) No trimming\n* B) Ignores spaces",
    ]

    def test_every_way_of_naming_a_letter_keeps_the_order(self):
        for text in self.NAMING:
            with self.subTest(text=text):
                result = self.render(plain(1, "B", solution=text) + self.filler())
                self.assertIn("question 1 keeps its order", result.stderr)
                self.assertEqual(correct_letter(section(result.stdout, 1)), "B")

    def test_letters_in_the_statement_keep_the_order(self):
        result = self.render(plain(1, "B", extra="Which is right, B or C?\n\n") + self.filler())
        self.assertIn("question 1 keeps its order", result.stderr)

    DATA = [
        "Copy the values in column B.", "Scores in the C band pass.",
        "The encounter order is A, D, 1, C.", "A temporary variable holds it.",
        "A `Sub` performs an action.", "Columns B, C and D hold the scores.",
    ]

    def test_data_letters_let_the_question_move(self):
        for text in self.DATA:
            with self.subTest(text=text):
                result = self.render(plain(1, "B", solution=text) + self.filler())
                self.assertNotIn("question 1 keeps", result.stderr)
                self.assertNotEqual(correct_letter(section(result.stdout, 1)), "B")

    def test_the_article_is_never_rewritten(self):
        labels = ("- **A.** A loop variable is never reset.\n- **B.** Uses b.\n"
                  "- **C.** Uses c.\n- **D.** Uses d.")
        out = self.render(plain(1, "A", solution=labels) + self.filler()).stdout
        self.assertIn("A loop variable is never reset.", out)
        self.assertNotRegex(out, r"[B-D] loop variable")

    def test_own_letters_change_only_when_all_four_bullets_use_them(self):
        labels = ("- **A.** A counts a.\n- **B.** B counts b.\n"
                  "- **C.** C counts c.\n- **D.** D counts d.")
        out = section(self.render(plain(1, "A", solution=labels) + self.filler()).stdout, 1)
        for letter, content in re.findall(r"\*\*([A-D])\.\*\* ([A-D]) counts", out):
            self.assertEqual(letter, content)
        moved = correct_letter(out)
        self.assertNotEqual(moved, "A")
        self.assertIn(f"**{moved}.** {moved} counts a.", out)

    def test_relational_options_keep_their_order(self):
        relational = plain(1, "B").replace("D) opt 1d", "D) None of the above")
        result = self.render(relational + self.filler())
        self.assertIn("question 1 keeps its order: an option refers to the other options", result.stderr)
        self.assertIn("D)  None of the above", result.stdout)

    # Labels -----------------------------------------------------------------

    def test_author_labels_in_the_block_are_not_doubled(self):
        block = ("::: {.alpha-explanations}\n- **A.** note a\n- **B.** note b\n"
                 "- **C.** note c\n- **D.** note d\n:::")
        for meta in ({}, {"exam-version": "B"}):
            with self.subTest(meta=meta):
                out = self.render(plain(1, "B", solution=block) + self.filler(), meta).stdout
                self.assertNotIn("**A.** **A.**", out)
                self.assertEqual(len(re.findall(r"\*\*[A-D]\.\*\* note", section(out, 1))), 4)

    # The key ----------------------------------------------------------------

    def test_a_single_question_moves(self):
        out = self.render(plain(1, "A")).stdout
        self.assertNotEqual(correct_letter(section(out, 1)), "A")

    def test_every_movable_question_moves(self):
        for label in "BCD":
            with self.subTest(label=label):
                out = self.render(plain(1, "A") + plain(2, "A"), {"exam-version": label}).stdout
                self.assertNotEqual(correct_letter(section(out, 1)), "A")
                self.assertNotEqual(correct_letter(section(out, 2)), "A")

    def test_movable_questions_move_when_most_are_pinned(self):
        pinned = "".join(plain(n, "A", solution="**Answer:** A.") for n in range(1, 7))
        out = self.render(pinned + plain(7, "B") + plain(8, "C")).stdout
        self.assertNotEqual(correct_letter(section(out, 7)), "B")
        self.assertNotEqual(correct_letter(section(out, 8)), "C")

    def test_balanced_and_deterministic(self):
        body = "".join(plain(n, "ABCD"[n % 4]) for n in range(1, 21))
        first = self.render(body, {"exam-version": "B", "exercise-audience": "answers"}).stdout
        again = self.render(body, {"exam-version": "B", "exercise-audience": "answers"}).stdout
        self.assertEqual(first, again)
        key = re.search(r"Key, version B:\*\*(.*)", first).group(1)
        letters = re.findall(r"\d+\u00a0([A-D])", key)
        self.assertEqual(sorted(letters.count(l) for l in "ABCD"), [5, 5, 5, 5])
        original = ["ABCD"[n % 4] for n in range(1, 21)]
        self.assertTrue(all(a != b for a, b in zip(original, letters)))

    def test_false_switches_the_feature_off(self):
        body = plain(1, "B") + self.filler()
        plain_out = self.render(body, {}).stdout
        for value in ("false", "\"false\"", "no"):
            with self.subTest(value=value):
                out = self.render(body, {"exam-version": value, "exercise-audience": "answers"}).stdout
                self.assertEqual(correct_letter(section(out, 1)), "B")
                self.assertNotIn("Key, version", out)
                # The document after its YAML header is exactly the plain render.
                self.assertEqual(out.split("---\n\n", 1)[1], plain_out)

    def test_version_a_keeps_the_order_and_prints_its_key(self):
        body = plain(1, "B") + self.filler()
        out = self.render(body, {"exam-version": "A", "exercise-audience": "answers"}).stdout
        self.assertEqual(correct_letter(section(out, 1)), "B")
        self.assertIn("Key, version A:** 1\u00a0B", out)


if __name__ == "__main__":
    unittest.main()
