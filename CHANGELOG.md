# Changelog

## 2.0.1

- A question kept in place because it names options by letter is reported
  with the fix: name the option by its content instead.

## 2.0.0

- `exam-version` works one question block at a time: the `.exercise-include`,
  or the section under the question's heading. Nothing carries over from one
  question to the next.
- Options and panels move by an order that keeps every letter's panels, in the
  same order, for any pattern of panel citations; the key uses only letters a
  question can reach.
- A question keeps its order whenever its statement, hints or Solution name a
  letter anywhere, including bold text, headings, tables and definition lists,
  when an option refers to the others, or when another question cites its
  panels. Data letters such as "column B" or "A, D, 1, C" do not count.
- The article "A" is never rewritten; a bullet's own letter changes only when
  all four bullets start with theirs. Labels already in an explanation block
  are corrected, not doubled.
- `exam-version: false` switches the feature off; `A` keeps the order and
  prints its key.

## 1.6.0

- `.alpha-explanations` takes the same lettered list as `.alpha-list`, with
  `.correct` on the correct option's explanation. The list rotates with its
  options and Pandoc letters it; a bullet list still gets bold labels.

## 1.5.0

- `::: {.alpha-explanations}` encloses one explanation per option, in option
  order. The explanations follow their options in every version, and the
  filter writes their **A.** to **D.** labels.
- Options that cite several panels move too: the panels rotate by the options'
  step, so paired options keep A (a) and (b), B (b) and (c), and so on.
- "explained in C" and "the error in B" count as naming an option.

## 1.4.0

- Panel questions move too: when each option cites one panel of a single
  parent block, the panels rotate with their options, so A still shows (a).
- Options written as a bullet list inside `.alpha-list` rotate too, and the
  key is numbered by each answer list's position on the page.
- The version label is opt-in: `exam-version-label: true` adds "Version B" to
  the subtitle, and by default the paper names no version.
- A question whose Solution names options by letter in a way the bullets
  cannot carry along keeps its order and is reported, instead of a warning
  about an explanation that would no longer match.

## 1.3.0

- `-M exam-version:B` renders a paper with a new balanced answer key: the
  options of plain-text questions rotate, panel questions keep their order,
  explanation bullets follow their options, the subtitle names the version and
  answer builds end with the key.

## 1.2.0

- The filter runs at the `pre-ast` stage, so it sees callouts as ordinary divs.
- `exercise-audience: student` removes note callouts, such as solutions, and
  `.correct` markers from exercise includes; `answers` starts every note
  callout collapsed. A `.question-aside` callout stays in both.
- An include takes `exercise-label` for a fixed label, or none when empty, and
  `print-start` (`page`, `verso` or `recto`), recorded as `data-print-start`.
  A heading can carry `print-start` too.
- Exercise headings also get `mcq-question` or `open-question`.
- A `suffix` option adds text inside the label after its number, such as `)`
  in `Q1)`, so label styles cover it.
- An include hands back its content without the wrapper, and its setup and
  question each move to `target-level`.
- New `neutral-answer-ids` extension in the same repository: student builds
  rename listing, figure and table identifiers that name a correct or wrong
  alternative.

## 1.1.0

- Labels take their colour from the `--exercise-label-color` CSS variable when
  a host sets it, then the Bootstrap primary colour, then the heading colour.

## 1.0.1

- A setup heading, whose identifier starts with `sec-setup-` or the older
  `sec-mcq-setup-`, is never labelled, also as the first heading of an exercise
  include. It holds the shared background of the questions after it.
- A `.exercise-setup` block at the start of an include is the setup of a case
  study: it gets no label, the question after it does, and when a page holds
  several questions of one case, only the first copy of the setup stays.
- An included file with an answer list is labelled multiple choice even when
  its identifier (`sec-exercise-`, `exr-`) suggests an open question. A
  `data-kind` or class on the heading still decides first.

## 1.0.0

- First release. Number open questions and multiple-choice items in headings,
  from explicit markers, conventional exercise sections, and exercise includes.
- Hierarchical numbering with visible question groups.
- `target-level` on an exercise include moves the included headings.
- Options for a label prefix, the letters, a separator, the question group word,
  the maximum exercise heading level, and hiding organising group headings.
