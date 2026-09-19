# Changelog

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
