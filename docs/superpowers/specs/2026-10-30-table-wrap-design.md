# Tables: wrap or scroll, at the reader's choice

Short design (small change). Branch `feat/table-wrap`, stacked on `feat/code-wrap` (PR #551), base
`release-1.5.1`. Written 2026-10-30.

## Intent

Code blocks now let the reader choose between wrapping and scrolling (PR #551). Tables do not: a
table wider than the bubble **always** scrolls sideways and its cells are cut at three lines with a
"…", so the reader either drags or opens the full-screen sheet to see what a cell actually says.
This gives tables the same choice, on the same terms, with the same control — and makes wrap mean
something a table can honestly promise: *fit the bubble without breaking words*.

## Goals

- A `table.wrap` mode with a corner switch, 44 pt target, one shared key remembered between launches.
- Wrap mode: columns held between their **longest-word floor** and a share of the bubble; cells draw
  every line (no three-line "…"), so a 2–4 column table is fully readable in the bubble.
- When the floors cannot fit, the table keeps today's sideways scroll with its edge fades — the
  switch stops promising what the columns can't deliver, rather than breaking words.
- The existing full-screen button's target rises from ≈24 pt to 44 pt.

## Non-goals

- No Settings › Reading row, no `ChatStyle` key, no `CloudSync`, no Reset-to-default line: the
  preference is a bare `@AppStorage` inside the view, exactly as `code.wrap` is (Andrew's call,
  2026-10-30). Consistency with the shipped code-block work beats the older `ChatStyle` pattern
  here; revisiting both together is a later, separate request.
- No change to `MarkdownTableSheet`, `MarkdownTableStack` (the accessibility text sizes), the
  markdown parser, or Copy as Markdown.
- Scroll mode keeps its three-line cap: that is what makes a very wide table readable at all.

## Anti-goals

- A wrap mode that breaks words mid-letter (the old pre-#42 bug: "Superpo / wer").
- A switch that lies: saying "wrapped" while the card still scrolls, or two switches on one screen
  disagreeing.
- Per-table state that drifts; or a wrap mode that proposes a width below a column's floor, which
  SwiftUI answers with a one-character-wide column a screen tall (measured: a 32-character token at
  width 0 lays out 480 pt tall).

## Constraints

- iOS and macOS (`VoryMac` draws the same SwiftUI views), Dynamic Type, **Bold Text**
  (`legibilityWeight`), VoiceOver labels unchanged.
- `MarkdownTableLayout.SizeStore` caches measured sizes by `SizeKey`; floors and the mode must be
  part of what invalidates that cache, or a switch mid-thread draws stale columns.
- No new dependencies. SwiftUI only, measuring through the view itself (probe `Text`s), so no
  platform font bridging enters the codebase.
- The PR's base is `feat/code-wrap`; it must not change the code block's own lines (`CodeBody`,
  `CodeWrapToggle`) or any other of that branch's work, so #551 stays reviewable on its own. It does
  modify `TranscriptView.swift`, where `MarkdownTableView` lives — a different region of the file.

## Approaches (picked in conversation, 2026-10-30)

| | How | Verdict |
|---|---|---|
| **A. Ask the layout** | inside `MarkdownTableLayout`, `subview.sizeThatFits(ProposedViewSize(width: 0, height: nil))` per cell | **Rejected on evidence.** A throwaway probe (SwiftUI `Layout` + `ImageRenderer`, 8 cell shapes, both with and without `fixedSize(horizontal: false, vertical: true)`) returned `width: 0 → 0.0`, `width: 1 → 1.0`, `unspecified → one-line width`. SwiftUI clamps to the proposal and never reports a word floor |
| **B. Measure the text** | B1: pure `MarkdownTableMetrics.wordFloors(...)` over CoreText, one measurement per word. B2: one hidden probe `Text` per column holding that column's words one per line — its natural width *is* the widest word | **Picked: B2.** B1 was the plan until a probe killed the font bridge: `Font.Context` has no accessible initialiser in the SDK (grepped the `.swiftinterface`), so a point size has to be hardcoded, and 13 pt measured **25 % wider** than the view draws on the Mac (a long token: 248.7 vs 197.0). B1 would drift with Dynamic Type and the reader's Small/Large text setting. B2 was probed instead and returns the widest line exactly — `Text("Agentic\ncoding\nat\nscale")` → 39 pt wide, 60 pt tall (four lines) — at the same font, size, weight and environment the cell draws with, with no platform font bridging at all |
| **C. Shrink toward the existing 64 pt floor** | wrap whenever columns can shrink to `minColumn` | Rejected: 64 pt is arbitrary, says nothing about words, and would fit tables it could not actually hold |

## Decided (by Andrew)

- Wrap when the words fit the bubble, scroll otherwise. No word-breaking, ever.
- Preference registration copied from the code block: bare `@AppStorage`, no Settings row.
- Branch `feat/table-wrap` off `feat/code-wrap`, PR base `feat/code-wrap`.

## My calls (check these while reading)

1. **Floors measured conservatively, through the view.** Each column gets one probe `Text` whose
   text is the column's distinct words joined by newlines, drawn at the grid's font in **bold** (the
   heaviest weight any cell uses: headers are semibold, `**bold**` inside a cell is bold), because a
   bold probe is never narrower than the word it guards. Its natural width is the floor. Markdown is
   stripped first (`MarkdownTable.plain`), so `**Lab A**` measures as "Lab A".
2. **Padding is part of the floor.** The grid keeps 10 pt horizontal padding per side, so a column's
   floor is its word floor + 20. That 20 pt is why a 6-column table needs 453 pt and will scroll.
3. **Duplicate the switch, don't generalise #551's.** A `TableWrapToggle` in the table file, same
   44 pt square and same glyph pair as `CodeWrapToggle`. Fifteen duplicated lines buys a table PR
   that does not touch the code-block PR's files; unify the two after #551 merges.
4. **The switch and the open-table button sit in the card's own 44 pt top strip**, not over the
   grid. An overlay claimed its room from the last header cell through `headerInset`, and a wrapped
   column can be 65 pt wide — the OCR of a rendered card showed "Sta" where "Status" should be, so
   the inset went back to 0 and the buttons got a strip. (Found by reading the drawn PNG, after the
   first implementation passed every size assertion it had.)
5. **Scroll mode's own arithmetic is untouched** — same widths, same three-line cap, same fades —
   but wrap is the **default**, so every table in every existing chat changes shape on the next
   launch (taller, every line drawn), and every card gains a 44 pt controls strip. That is the
   point of the feature, not a side effect; a reader who turns the switch off gets exactly today's
   card, minus the bigger targets.
6. **A floor never collapses.** An empty column keeps a small minimum (24 pt) so a table with a blank
   column does not fold to nothing.

## Left to the builder

Exact function signatures, the `words` helper that feeds each column's probe, the `SizeKey` and
`Cache` additions, the probe placement, cell/header insets, and the shapes of the tests — all pinned
in the implementation plan.
