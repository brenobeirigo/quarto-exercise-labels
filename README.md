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
same case, only the first copy of the setup stays.

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
  separator: ""               # ":" gives "Q1: Title"
  group-label: Exercise       # word before a group number
  max-level: 3                # deeper exercise headings are raised to this level
  hide-exercise-groups: true  # remove .exercise-group headings
```

`max-level` does not apply to exercise includes, whose `target-level` decides
the level, or to hierarchical numbering, which keeps every level.

## Output

- An exercise heading gets the classes `exercise-heading exercise` and the
  attributes `data-exercise-id` and `data-exercise-kind`.
- The label is `<span class="exercise-label" data-exercise-id="Q1" data-exercise-type="Q">`.
- A question group heading gets the class `question-group-heading` and the
  attribute `data-question-group-id`, and its label span has the class
  `question-group-label`.
- A heading without an identifier gets `exr-<title>` and a
  `data-generated-anchor` attribute.

The bundled stylesheet colours labels with the Bootstrap primary colour and
hides Quarto section numbers on exercise headings. The
[Lucid theme](https://brenobeirigo.github.io/quarto-extensions/lucid.html) also
adds a copy-reference button to each label and retitles a callout written as
`title="Solution [-@exr-id]"` to "Solution to Q1".

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
