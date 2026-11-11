# Changelog

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
