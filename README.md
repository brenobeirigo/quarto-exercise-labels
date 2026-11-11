# Quarto Exercise Labels

[![Quarto extension checks](https://github.com/brenobeirigo/quarto-exercise-labels/actions/workflows/checks.yml/badge.svg)](https://github.com/brenobeirigo/quarto-exercise-labels/actions/workflows/checks.yml)

`exercise-labels` is a Quarto filter that numbers exercises in headings. It puts
a label such as `Q1`, `M2`, or `Q2.1` in front of the heading text, gives every
exercise a stable anchor, and records the label in data attributes that styles
and scripts can use. Open questions and multiple-choice items have separate
counters.

Labels are ordinary text, so they appear in HTML, PDF, Word, and Reveal.js
output. HTML output also loads a small stylesheet.

**How-to and live demo:** <https://brenobeirigo.github.io/quarto-extensions/exercise-labels.html>

## Install

```bash
quarto add brenobeirigo/quarto-exercise-labels
```

The repository installs two extensions: `exercise-labels` and
[`neutral-answer-ids`](#neutral-answer-ids). Each one is enabled on its own.
Both run at the `pre-ast` stage, before Quarto turns callouts and
cross-reference targets into its own elements.

## Enable

```yaml
filters:
  - exercise-labels
```

## Mark exercises

### On the heading

| Markup | Result |
|---|---|
| `{.exercise}` or `{.question}` | Open question, labelled `Q` |
| `{.mcq}` or `{.multiple-choice}` | Multiple-choice item, labelled `M` |
| `{data-kind="Q"}` or `{data-kind="M"}` | Chooses the kind explicitly |
| `{#exr-...}`, `{#sec-exercise-...}`, `{#sec-question-...}` | Open question |
| `{#exr-mcq-...}` or `{#sec-mcq-...}` | Multiple-choice item. `{#sec-mcq-setup-...}` is left alone |

```markdown
### Compute the sample mean {.exercise}

### Pick the median {.exercise data-kind="M"}
```

### By section

- Under a level-2 heading with the identifier `exercises`, every level-3 heading
  is an open question. A heading titled "Exercises" gets that identifier
  automatically.
- Under `multiple-choice-exercises` or `multiple-choice-questions`, every
  level-3 heading is a multiple-choice item.
- A level-1 `.exercises` heading whose title mentions multiple choice, or a
  document whose title does, makes every level-2 heading a multiple-choice item.
- `.exercise-tier` headings are never labelled. `.exercise-group` headings
  organise the source and are removed from the output, unless
  `hide-exercise-groups` is `false`.

### Included exercises

```markdown
::: {.exercise-include target-level="3"}
{{< include exercises/running-total.qmd >}}
:::
```

The headings inside move so the first one sits at `target-level`, which
defaults to 3, and that first heading becomes the exercise. The kind is `M` when
the include contains an `.alpha-list`, and `Q` otherwise. Add `.exercise-bank`
to label every heading one level below the first one instead.

An include whose first heading has an identifier starting with `sec-setup-`
(or the older `sec-mcq-setup-`) is a shared background for the questions after
it: its headings move, but it gets no label and no number.

A question of a case study can start by including its setup, wrapped in
`::: {.exercise-setup setup="<case>"}`. The setup is never labelled, the
question heading after it is, and when a page holds several questions of the
same case, only the first copy of the setup stays. The setup and the question
each move so that their first heading sits at `target-level`.

An include hands back its content without the wrapping div, so a table of
contents lists both the setup and the question.

A paper host can set two more attributes on an include:

| Attribute | Effect |
|---|---|
| `exercise-label="Question 1"` | Uses this text as the label instead of the counter. An empty value, `exercise-label=""`, shows no label, for a question printed on its own page. |
| `print-start="verso"` | Records `data-print-start` on the question heading, for print stylesheets. The value is `page`, `verso` or `recto`. A heading can carry `print-start` too. |

```markdown
::: {.exercise-include target-level="2" exercise-label="Question 1" print-start="verso"}
{{< include questions/mcq-count-local-global.qmd >}}
:::
```

### Student and answer versions

Set the top-level `exercise-audience` metadata to build a student or an answer
version of a paper from the same sources, usually in two Quarto profiles:

```yaml
# _quarto-questions.yml
exercise-audience: student

# _quarto-answers.yml
exercise-audience: answers
```

Inside exercise includes, a `student` build removes every note callout, such
as a `Solution`, and the `.correct` marker of each correct alternative, so the
page source holds no answer. A note callout with the class `.question-aside`
belongs to the question and stays, unless its title names a solution, answer,
rubric or marking. An `answers` build keeps everything and starts each note
callout collapsed. Without `exercise-audience`, includes stay as written.

### Question groups

With `numbering: hierarchical`, a `.question-group` heading shows "Exercise 1:"
and the exercises under it are numbered `Q1.1`, `M1.2`, and so on. Grouped
exercises are left out of the table of contents, while the group heading stays
in it. The next heading at the group's level or higher ends the group.

```markdown
## Budget a small event {.question-group}

### Add the fixed costs {.exercise}
```

## Options

Set options in a document header or in `_quarto.yml`. A page-specific `prefix`
belongs in that page's header.

```yaml
exercise-labels:
  numbering: flat             # flat | hierarchical
  prefix: ""                  # "2.4" gives 2.4.Q1
  question: Q                 # letter for open questions
  choice: M                   # letter for multiple-choice items
  suffix: ""                  # ")" gives "Q1) Title", inside the label
  separator: ""               # ":" gives "Q1: Title", after the label
  group-label: Exercise       # word before a group number
  max-level: 3                # deeper exercise headings are raised to this level
  hide-exercise-groups: true  # remove .exercise-group headings
```

`max-level` does not apply to exercise includes, whose `target-level` decides
the level, or to hierarchical numbering, which keeps every level.

## Output

- An exercise heading gets the classes `exercise-heading exercise`, then
  `mcq-question` or `open-question`, and the attributes `data-exercise-id` and
  `data-exercise-kind`. A heading with an empty fixed label has no
  `data-exercise-id`.
- The label is `<span class="exercise-label" data-exercise-id="Q1" data-exercise-type="Q">`.
- A question group heading gets the class `question-group-heading` and the
  attribute `data-question-group-id`, and its label span has the class
  `question-group-label`.
- A heading without an identifier gets `exr-<title>` and a
  `data-generated-anchor` attribute.

The bundled stylesheet colours labels with `--exercise-label-color` when set,
then the Bootstrap primary colour, and finally the heading's current text
colour.
It hides Quarto section numbers on exercise headings.
Set the CSS variable on the page or a surrounding container to style both
exercise and question-group labels without changing the generated markup:

```css
:root {
  --exercise-label-color: #315c45;
}
```

The filter does not inject inline colours.
A host theme can still apply a more specific `color` rule directly to the label;
in that case, adapt that rule or add a scoped host stylesheet rule using
`color: var(--exercise-label-color, var(--bs-primary, currentColor))`.
The [Lucid theme](https://brenobeirigo.github.io/quarto-extensions/lucid.html) also
adds a copy-reference button to each label and retitles a callout written as
`title="Solution [-@exr-id]"` to "Solution to Q1".

## Exam versions

A multiple-choice paper gets a new answer key from the same sources with one
flag. Nothing in the questions changes:

```bash
quarto render exam.qmd --profile questions -M exam-version:B
quarto render exam.qmd --profile answers -M exam-version:B
```

Without `exam-version`, or with `A`, the paper renders as written. Any other
label, such as `B` or `C`, gives its own key, the same every time, so the
student and answer renders always agree.

- A question is an `.alpha-list` with four options and one `.correct` marker.
  Its options rotate together, so the correct one lands on its new letter.
- A question whose options cite a listing, figure or table (`@lst-`, `@fig-`,
  `@tbl-`) keeps its order, so option A still points at panel (a).
- The new key changes every other answer, keeps the A to D totals balanced and
  avoids the same letter on consecutive questions.
- Explanation bullets written as `- **A.** ...` follow their options. A first
  word that repeats the bullet's letter, as in `**A.** A counts ...`, changes
  with it. Describe other options instead of naming their letters; the render
  warns when an explanation names one.
- The subtitle gets "Version B", and an answer build
  (`exercise-audience: answers`) ends with the version's key.

The filter comes with the extension and runs before `exercise-labels`. A
project that loads the filters by path lists `exam-version.lua` first.

## Neutral answer ids

Questions often name their alternatives in identifiers, such as
`lst-fee-correct1` or `fig-cellphone-wrong2`. An identifier is in the page
source, and a reader sees it when hovering a link. Enable the second extension
to rename them in student builds:

```yaml
filters:
  - exercise-labels
  - neutral-answer-ids
```

In a student build, every listing, figure or table identifier that contains
`correct` or `wrong` becomes `<prefix>-option-<n>`, numbered in page order, so
neither the name nor the number gives the answer away. Cross-references, links,
code cell labels and raw HTML follow the new identifiers. Section identifiers
stay.

The build is for answers when `exercise-audience` is `answers`. Without that
option, it is for answers when the active Quarto profiles include `answers`.
An answer build keeps the authored identifiers.

## Examples

- `example.qmd` numbers an Exercises section and an include with a prefix.
- `example-hierarchical.qmd` shows question groups.

```bash
quarto render example.qmd --to html
```

## Test

```bash
python -m unittest discover -s tests -v
```

## License

[MIT](LICENSE)
