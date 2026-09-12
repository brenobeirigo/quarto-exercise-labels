"""Render-contract tests for the exercise-labels filter.

Most tests read Pandoc's JSON syntax tree, where heading levels, identifiers,
classes, attributes, and label text are exact. One test renders the examples
with Quarto to check the HTML integration.
"""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
FILTER = REPOSITORY / "_extensions" / "exercise-labels" / "exercise-labels.lua"
QUARTO = shutil.which("quarto")


def inline_text(inlines):
    parts = []
    for inline in inlines:
        kind = inline.get("t")
        if kind == "Str":
            parts.append(inline["c"])
        elif kind == "Space":
            parts.append(" ")
        elif kind in ("Emph", "Strong", "Span"):
            content = inline["c"][1] if kind == "Span" else inline["c"]
            parts.append(inline_text(content))
        elif kind == "Code":
            parts.append(inline["c"][1])
    return "".join(parts)


def collect_headings(node, found):
    if isinstance(node, dict):
        if node.get("t") == "Header":
            level, (identifier, classes, pairs), content = node["c"]
            label = None
            label_classes = []
            label_attributes = {}
            for inline in content:
                if inline.get("t") == "Span":
                    (_, span_classes, span_pairs), span_content = inline["c"]
                    if "exercise-label" in span_classes or "question-group-label" in span_classes:
                        label = inline_text(span_content)
                        label_classes = span_classes
                        label_attributes = dict(span_pairs)
                        break
            found[identifier] = {
                "level": level,
                "classes": classes,
                "attributes": dict(pairs),
                "label": label,
                "label_classes": label_classes,
                "label_attributes": label_attributes,
                "text": inline_text(content),
            }
        for value in node.values():
            collect_headings(value, found)
    elif isinstance(node, list):
        for value in node:
            collect_headings(value, found)


@unittest.skipUnless(QUARTO, "Quarto is required for the render-contract tests")
class ExerciseLabelTests(unittest.TestCase):
    def run_pandoc(self, markdown, reader="markdown"):
        return subprocess.run(
            [QUARTO, "pandoc", "--from", reader, "--to", "json", "--lua-filter", str(FILTER)],
            input=markdown,
            text=True,
            encoding="utf-8",
            capture_output=True,
            check=False,
        )

    def headings(self, markdown, reader="markdown"):
        result = self.run_pandoc(markdown, reader)
        self.assertEqual(result.returncode, 0, result.stderr)
        found = {}
        collect_headings(json.loads(result.stdout)["blocks"], found)
        return found

    def test_explicit_markers_number_questions_and_choices_separately(self):
        found = self.headings(
            "## Compute the mean {.exercise}\n\n"
            '## Pick the median {.exercise data-kind="M"}\n\n'
            "## Trace the loop {#exr-trace-loop}\n\n"
            "## Choose an estimator {#exr-mcq-estimator}\n\n"
            "## Read the setup {#sec-mcq-setup-sample}\n"
        )
        mean = found["compute-the-mean"]
        self.assertEqual(mean["label"], "Q1")
        self.assertEqual(mean["text"], "Q1 Compute the mean")
        self.assertIn("exercise-heading", mean["classes"])
        self.assertIn("exercise", mean["classes"])
        self.assertEqual(mean["attributes"]["data-exercise-id"], "Q1")
        self.assertEqual(mean["attributes"]["data-exercise-kind"], "Q")
        self.assertEqual(mean["label_attributes"]["data-exercise-type"], "Q")
        self.assertEqual(found["pick-the-median"]["label"], "M1")
        self.assertEqual(found["exr-trace-loop"]["label"], "Q2")
        self.assertEqual(found["exr-mcq-estimator"]["label"], "M2")
        self.assertIsNone(found["sec-mcq-setup-sample"]["label"])

    def test_conventional_sections_label_their_subheadings(self):
        found = self.headings(
            "## Exercises\n\n"
            "### First task\n\n"
            "### Warm-up tier {.exercise-tier}\n\n"
            "### Second task\n\n"
            "### Grouping heading {.exercise-group}\n\n"
            "## Multiple-choice questions\n\n"
            "### Pick one\n\n"
            "## Summary\n\n"
            "### Not an exercise\n"
        )
        self.assertEqual(found["first-task"]["label"], "Q1")
        self.assertIsNone(found["warm-up-tier"]["label"])
        self.assertEqual(found["second-task"]["label"], "Q2")
        self.assertNotIn("grouping-heading", found)
        self.assertEqual(found["pick-one"]["label"], "M1")
        self.assertIsNone(found["not-an-exercise"]["label"])

    def test_multiple_choice_chapter_labels_level_two_headings(self):
        found = self.headings(
            "# Multiple-choice exercises {.exercises}\n\n## Which is larger\n\n### Detail\n"
        )
        self.assertEqual(found["which-is-larger"]["label"], "M1")
        self.assertIsNone(found["detail"]["label"])

    def test_exercise_groups_can_stay_visible(self):
        found = self.headings(
            "---\nexercise-labels:\n  hide-exercise-groups: false\n---\n\n"
            "## Exercises\n\n### Grouping heading {.exercise-group}\n"
        )
        self.assertIn("grouping-heading", found)
        self.assertIsNone(found["grouping-heading"]["label"])

    def test_options_set_prefix_letters_separator_and_level(self):
        found = self.headings(
            "---\n"
            "exercise-labels:\n"
            '  prefix: "2.4"\n'
            "  question: E\n"
            '  separator: ":"\n'
            "  max-level: 2\n"
            "---\n\n"
            "#### Deep task {.exercise}\n"
        )
        deep = found["deep-task"]
        self.assertEqual(deep["level"], 2)
        self.assertEqual(deep["label"], "2.4.E1")
        self.assertEqual(deep["text"], "2.4.E1: Deep task")

    def test_default_max_level_raises_deep_exercises_to_three(self):
        found = self.headings("##### Deep task {.exercise}\n")
        self.assertEqual(found["deep-task"]["level"], 3)

    def test_hierarchical_numbering_groups_questions(self):
        found = self.headings(
            "---\nexercise-labels:\n  numbering: hierarchical\n---\n\n"
            "## Budget {.question-group}\n\n"
            "### Sum costs {.exercise}\n\n"
            '### Pick a total {.exercise data-kind="M"}\n\n'
            "## Forecast {.question-group}\n\n"
            "### Extend the trend {.exercise}\n\n"
            "## Closing notes\n\n"
            "### Standalone {.exercise}\n"
        )
        budget = found["budget"]
        self.assertEqual(budget["label"], "Exercise 1")
        self.assertEqual(budget["text"], "Exercise 1: Budget")
        self.assertIn("question-group-label", budget["label_classes"])
        self.assertIn("question-group-heading", budget["classes"])
        self.assertEqual(budget["attributes"]["data-question-group-id"], "1")
        self.assertEqual(found["sum-costs"]["label"], "Q1.1")
        self.assertIn("unlisted", found["sum-costs"]["classes"])
        self.assertEqual(found["pick-a-total"]["label"], "M1.2")
        self.assertEqual(found["forecast"]["label"], "Exercise 2")
        self.assertEqual(found["extend-the-trend"]["label"], "Q2.1")
        self.assertIsNone(found["closing-notes"]["label"])
        self.assertEqual(found["standalone"]["label"], "Q1")
        self.assertNotIn("unlisted", found["standalone"]["classes"])

    def test_include_shifts_headings_and_labels_the_first(self):
        result = self.run_pandoc(
            '::: {.exercise-include target-level="4"}\n'
            "# Check the total {#exr-total}\n\n"
            "## Hint\n"
            ":::\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("target-level", result.stdout)
        found = {}
        collect_headings(json.loads(result.stdout)["blocks"], found)
        self.assertEqual(found["exr-total"]["level"], 4)
        self.assertEqual(found["exr-total"]["label"], "Q1")
        self.assertEqual(found["hint"]["level"], 5)
        self.assertIsNone(found["hint"]["label"])

    def test_include_with_alpha_list_is_multiple_choice(self):
        found = self.headings(
            "::: {.exercise-include}\n"
            "# Pick the best estimate\n\n"
            "::: {.alpha-list}\n- One\n- Two\n:::\n"
            ":::\n"
        )
        heading = found["pick-the-best-estimate"]
        self.assertEqual(heading["level"], 3)
        self.assertEqual(heading["label"], "M1")

    def test_exercise_bank_labels_each_child_heading(self):
        found = self.headings(
            '::: {.exercise-include .exercise-bank target-level="2"}\n'
            "# Loops\n\n"
            "## Count down\n\n"
            "### Detail\n\n"
            "## Sum a list\n"
            ":::\n"
        )
        self.assertEqual(found["loops"]["level"], 2)
        self.assertIsNone(found["loops"]["label"])
        self.assertEqual(found["count-down"]["level"], 3)
        self.assertEqual(found["count-down"]["label"], "Q1")
        self.assertIsNone(found["detail"]["label"])
        self.assertEqual(found["sum-a-list"]["label"], "Q2")

    def test_headings_without_identifiers_get_exercise_anchors(self):
        found = self.headings(
            "## Compute the mean {.exercise}\n\n## Compute the mean {.exercise}\n",
            reader="markdown-auto_identifiers",
        )
        self.assertEqual(found["exr-compute-the-mean"]["attributes"]["data-generated-anchor"], "Q1")
        self.assertEqual(found["exr-compute-the-mean-2"]["attributes"]["data-generated-anchor"], "Q2")

    def test_invalid_target_level_stops_the_render(self):
        result = self.run_pandoc('::: {.exercise-include target-level="9"}\n# Task\n:::\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("target-level", result.stderr)

    def test_invalid_numbering_stops_the_render(self):
        result = self.run_pandoc(
            "---\nexercise-labels:\n  numbering: nested\n---\n\n## Task {.exercise}\n"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("numbering", result.stderr)

    def test_quarto_render_loads_the_stylesheet(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            shutil.copytree(REPOSITORY / "_extensions", project / "_extensions")
            for name in ("example.qmd", "example-hierarchical.qmd"):
                shutil.copy2(REPOSITORY / name, project / name)
                result = subprocess.run(
                    [QUARTO, "render", name, "--to", "html"],
                    cwd=project,
                    text=True,
                    encoding="utf-8",
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            html = (project / "example.html").read_text(encoding="utf-8")
            self.assertIn("exercise-labels.css", html)
            self.assertIn('class="exercise-label"', html)
            self.assertIn('data-exercise-id="3.Q1"', html)
            self.assertIn('data-exercise-id="3.M1"', html)
            grouped = (project / "example-hierarchical.html").read_text(encoding="utf-8")
            self.assertIn('data-exercise-id="Q1.1"', grouped)
            self.assertIn('class="question-group-label"', grouped)


if __name__ == "__main__":
    unittest.main()
