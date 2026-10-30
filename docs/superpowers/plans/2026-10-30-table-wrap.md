# Tables: wrap or scroll — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a markdown table the same reader's choice the code block got in PR #551 — wrap to fit the bubble, or scroll sideways — where wrapping never breaks a word.

**Architecture:** Each column's floor is its widest *word*, measured by SwiftUI itself: one hidden probe `Text` per column holds that column's distinct words one per line, so its natural width is the widest line. `MarkdownTableLayout` holds columns between those floors and a share of the bubble; `MarkdownTableView` tries that wrapped grid first and falls back to today's sideways scroll when the floors cannot fit. One `@AppStorage("table.wrap")` key drives every table.

**Tech Stack:** Swift 6, SwiftUI (`Layout`, `ViewThatFits`, `@AppStorage`, `ImageRenderer`), Swift Testing (`@Suite`/`@Test`/`#expect`), iOS + macOS targets in one Xcode project.

**Spec:** `docs/superpowers/specs/2026-10-30-table-wrap-design.md`

## Global Constraints

- Branch `feat/table-wrap`, worktree `.worktrees/table-wrap`, base `feat/code-wrap` (PR #551).
- Do not change `CodeBody`, `CodeWrapToggle` or any other line of `feat/code-wrap`'s work.
- `table.wrap` is a bare `@AppStorage` defaulting to `true`. No `ChatStyle` key, no Settings row, no `CloudSync`, no Reset line.
- Wrap never breaks a word: a column is never laid out narrower than its word floor.
- A column's floor already includes the grid's 10 pt horizontal padding per side, and is never below `24` pt.
- Scroll mode is unchanged: same widths, same `lineLimit(3)`, same edge fades.
- Nothing in `MarkdownTableSheet`, `MarkdownTableStack`, the parser, or `MarkdownTable.markdown` changes.
- iOS and macOS both build; `MarkdownTableTests`, `TableWrapTests`, `CodeWrapTests` and `TextPiecesTests` all stay green. `VoryMac/UIKitCompat.swift` gives tests `renderer.uiImage` on both platforms, so no `#if os(...)` is needed.
- iOS tests: `xcodebuild test -project Vory.xcodeproj -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Mac tests: `xcodebuild test -scheme VoryMac -destination 'platform=macOS'`
- Filter a suite with `-only-testing:VoryTests/<SuiteName>`.

## Review Focus

- A cell holding one unbreakable token longer than the bubble (a hash, base64, a URL): wrap must fall back to the sideways scroll, never lay out a one-character column (probe: such a column at width 0 draws 480 pt tall).
- An empty column: keeps a 24 pt floor, never folds to zero width.
- An emoji-only column (`⭐⭐⭐⭐⭐`): one word to the probe, so the floor is the whole run and the column is not squeezed to one glyph.
- A table still streaming (rows arriving): floors and widths are measured per `SizeKey`, which carries the table, so a new row invalidates them — no stale columns.
- The accessibility text sizes: `MarkdownTableView` must still draw `MarkdownTableStack` and never overflow sideways.

---

### Task 1: Column words and per-column minimums

**Files:**
- Modify: `Vory/Chat/MarkdownTableSheet.swift:10-64` (`MarkdownTableMetrics`)
- Test: `VoryTests/MarkdownTableTests.swift`

**Interfaces:**
- Consumes: `MarkdownTable` (`header`, `rows`, `cell(row:column:)`) and `MarkdownTable.plain(_:)` from `VoryCore`.
- Produces:
  - `MarkdownTableMetrics.cellPadding: CGFloat` = `20`
  - `MarkdownTableMetrics.minColumnFloor: CGFloat` = `24`
  - `MarkdownTableMetrics.words(_ table: MarkdownTable, column: Int) -> String` — plain words, deduped, `"\n"`-joined
  - `MarkdownTableMetrics.columnWidths(natural: [CGFloat], lo: [CGFloat], hi: CGFloat, fill: CGFloat?) -> [CGFloat]`
  - the existing `columnWidths(natural:fill:min:max:)` keeps its signature and delegates

- [ ] **Step 1: Write the failing tests** (in `MarkdownTableTests`, so the file-private `onlyTable` helper is in reach)

```swift
@Test func aColumnFloorIsItsLongestWord() throws {
    let t = try #require(onlyTable(Self.wide))
    // Every word of the column, one per line: the probe Text's natural width is then its widest line.
    let words = MarkdownTableMetrics.words(t, column: 4).split(separator: "\n").map(String.init)
    #expect(Set(words) == ["Superpower", "Agentic", "coding", "at", "scale", "Long-horizon", "tool", "use"])
    #expect(words.count == Set(words).count, "words are deduped")
    // Markdown never reaches the probe: it measures words, not markers. "/" is a word of its own.
    let lab = MarkdownTableMetrics.words(t, column: 1)
    #expect(!lab.contains("*"))
    #expect(Set(lab.split(separator: "\n").map(String.init)) == ["Lab", "/", "Model", "A", "—", "One"])
}

@Test func anEmptyColumnHasNoWords() throws {
    let t = try #require(onlyTable("| a | b |\n|---|---|\n| 1 |  |"))
    #expect(MarkdownTableMetrics.words(t, column: 1) == "")
    #expect(MarkdownTableMetrics.words(t, column: 0) == "a\n1")
}

@Test func anEmojiRunIsOneWord() throws {
    let t = try #require(onlyTable(Self.wide))
    // ⭐⭐⭐⭐⭐ is a single word: a floor of the whole run, not one glyph.
    let rating = Set(MarkdownTableMetrics.words(t, column: 5).split(separator: "\n").map(String.init))
    #expect(rating == ["Rating", "⭐⭐⭐⭐⭐", "⭐⭐⭐⭐½"])
}

@Test func eachColumnIsHeldAtItsOwnFloor() {
    typealias M = MarkdownTableMetrics
    // Wider than the fill in all: every column stands on its own floor, in order.
    #expect(M.columnWidths(natural: [200, 300, 100], lo: [60, 40, 24], hi: 220, fill: 320) == [60, 40, 24])
    #expect(M.columnWidths(natural: [200, 300, 100], lo: [60, 40, 24], hi: 220, fill: nil) == [60, 40, 24])
    // A floor past `hi` is kept, never clamped down into a broken word.
    #expect(M.columnWidths(natural: [200, 300], lo: [400, 40], hi: 220, fill: 320) == [400, 40])
    // Room to spare: the column that had to wrap gets its one-line width first, the rest grow.
    let roomy = M.columnWidths(natural: [200, 40, 24], lo: [60, 40, 24], hi: 220, fill: 400)
    #expect(abs(roomy.reduce(0, +) - 400) < 0.001)
    #expect(roomy[1] == 40 && roomy[2] == 24)
    #expect(roomy[0] > 200)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project Vory.xcodeproj -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VoryTests/MarkdownTableTests`
Expected: FAIL — `MarkdownTableMetrics` has no member `words`, and no `columnWidths(natural:lo:hi:fill:)`.

- [ ] **Step 3: Implement in `MarkdownTableMetrics`**

```swift
/// The grid's horizontal padding per side, part of every column's floor.
static let cellPadding: CGFloat = 20
/// A column with no words at all still needs a sliver to draw its padding and rules.
static let minColumnFloor: CGFloat = 24

/// The words a column's floor is measured from: every cell's plain text, deduped, one per line.
/// A probe `Text` of this string reports its widest word as its natural width (measured: 39 pt for
/// "Agentic\ncoding\nat\nscale" at footnote size, 60 pt tall for its four lines).
static func words(_ table: MarkdownTable, column c: Int) -> String {
    var firstSeen = Set<String>(), ordered: [String] = [], word = ""
    func flush() {
        if !word.isEmpty, firstSeen.insert(word).inserted { ordered.append(word) }
        word = ""
    }
    func add(_ text: String) {
        for ch in MarkdownTable.plain(text) {
            if ch.isWhitespace { flush() } else { word.append(ch) }
        }
        flush()
    }
    if table.header.indices.contains(c) { add(table.header[c]) }
    for r in table.rows.indices { add(table.cell(row: r, column: c)) }
    // First-seen order, not sorted: the string is only ever measured, and a stable order keeps the
    // cache key stable while a table streams.
    return ordered.joined(separator: "\n")
}
```

For the widths, add the per-column overload `columnWidths(natural:lo:hi:fill:)`: it is today's body with the scalar `min lo` replaced by `lo[i]` and the clamp spelled `Swift.min(Swift.max(natural[i], lo[i]), Swift.max(hi, lo[i]))` — a column whose floor exceeds `hi` keeps its floor rather than breaking a word. Then keep the old signature as a one-line delegation:

```swift
static func columnWidths(natural: [CGFloat], fill: CGFloat?, min lo: CGFloat, max hi: CGFloat) -> [CGFloat] {
    columnWidths(natural: natural, lo: Array(repeating: lo, count: natural.count), hi: hi, fill: fill)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command. Expected: PASS, including the four pre-existing `columnWidths` assertions.

- [ ] **Step 5: Commit**

```bash
git add Vory/Chat/MarkdownTableSheet.swift VoryTests/MarkdownTableTests.swift
git commit -m "feat(table): measure a column by its words, and hold it at its own floor"
```

---

### Task 2: The layout measures floors and wraps the cells

**Files:**
- Modify: `Vory/Chat/MarkdownTableSheet.swift:96-214` (`MarkdownTableLayout`), `:219-308` (`MarkdownTableGrid`)
- Test: `VoryTests/TableWrapTests.swift` (new), `VoryTests/MarkdownTableTests.swift`

**Interfaces:**
- Consumes: Task 1's `words`, `cellPadding`, `minColumnFloor`, `columnWidths(natural:lo:hi:fill:)`.
- Produces:
  - `MarkdownTableLayout(columns:cellCount:minColumn:maxColumn:wraps:fillWidth:sizes:)` — declared in
    that order (`cellCount` after `columns`, `wraps` after `maxColumn`); `cellCount` is how many
    leading subviews are cells, and the subviews after them are the per-column probes.
  - `MarkdownTableLayout.Cache.floors: [CGFloat]?`, kept by `SizeStore` like `natural`.
  - `MarkdownTableGrid(table:lineLimit:wraps:…)` — `var wraps = false` is declared **after** `lineLimit` and **before** `maxColumn`, so memberwise calls read `table:, lineLimit:, wraps:, …`. When `wraps` is true the grid draws every line (`lineLimit: nil`) and appends one probe per column.

- [ ] **Step 1: Write the failing tests**

New file `VoryTests/TableWrapTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
@testable import VoryCore
@testable import Vory

/// The table's wrap switch: a table whose words fit wraps inside the bubble, and one whose words
/// do not reports more than the bubble so the card falls back to its sideways scroll. Drawn through
/// the real views, because the mode is a layout.
@Suite struct TableWrapTests {
    /// Three columns whose words fit a phone bubble once the cells are allowed to wrap.
    static let three = "| Owner | Task | Status |\n|---|---|---|\n| @work | the deploy | Done |\n"

    static func table(_ text: String) -> MarkdownTable? {
        let blocks = MarkdownParser.blocks(from: text)
        guard blocks.count == 1, case .table(let t) = blocks[0] else { return nil }
        return t
    }

    @MainActor static func draw(_ view: some View) -> CGSize {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage?.size ?? .zero
    }

    @MainActor private func grid(_ text: String, wraps: Bool) throws -> some View {
        let t = try #require(Self.table(text))
        return MarkdownTableGrid(table: t, lineLimit: wraps ? nil : 3, wraps: wraps, fillWidth: 320)
            .frame(width: 320)
    }

    @Test @MainActor func wrappingFitsTheBubbleThatScrollingOverflows() throws {
        let wrapped = Self.draw(try grid(Self.three, wraps: true))
        let scrolling = Self.draw(try grid(Self.three, wraps: false))
        #expect(abs(wrapped.width - 320) < 1, "the wrapped grid took \(wrapped.width) pt of a 320 pt bubble")
        #expect(wrapped.height > scrolling.height, "wrapping should trade width for height")
    }

    @Test @MainActor func aTableWhoseWordsDoNotFitReportsMoreThanTheBubble() throws {
        // Six columns of real words: 333 pt of word floors plus 120 pt of padding cannot fit 320.
        let wide = Self.draw(try grid(MarkdownTableTests.wide, wraps: true))
        #expect(wide.width > 320, "the wrapped grid reported \(wide.width) pt, so ViewThatFits falls back")
    }

    @Test @MainActor func anEmptyColumnKeepsASliver() throws {
        let t = try #require(Self.table("| a | b |\n|---|---|\n| 1 |  |"))
        let size = Self.draw(MarkdownTableGrid(table: t, lineLimit: nil, wraps: true, fillWidth: 320).frame(width: 320))
        #expect(size.width >= MarkdownTableMetrics.minColumnFloor)
    }

    @Test @MainActor func aTokenTooWideForTheBubbleIsNotSqueezedLetterByLetter() throws {
        let token = String(repeating: "9f2c7ab4", count: 8)   // 64 characters, one unbreakable word
        let t = try #require(Self.table("| hash |\n|---|\n| \(token) |"))
        let size = Self.draw(MarkdownTableGrid(table: t, lineLimit: nil, wraps: true, fillWidth: 320).frame(width: 320))
        #expect(size.width > 320, "the column must hold its token and scroll")
        #expect(size.height < 80, "the cell stacked into \(size.height) pt instead of staying one line")
    }
}
```

And in `MarkdownTableTests`, extend the cache test so a streaming table cannot reuse stale floors:

```swift
// Floors ride the same key as the widths they feed.
kept.floors = [40, 60, 30]
L.SizeStore.shared.keep(kept)
#expect(L.SizeStore.shared.cache(for: key).floors == [40, 60, 30])
#expect(L.SizeStore.shared.cache(for: other).floors == nil)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… -only-testing:VoryTests/TableWrapTests -only-testing:VoryTests/MarkdownTableTests`
Expected: FAIL — `MarkdownTableGrid` has no `wraps` parameter; `Cache` has no `floors`.

- [ ] **Step 3: Implement**

In `MarkdownTableLayout`: add `var cellCount: Int` after `columns` and `var wraps = false` after
`maxColumn`; add `var floors: [CGFloat]?` to `Cache`; add:

```swift
private func floors(_ subviews: Subviews, _ cache: inout Cache) -> [CGFloat] {
    if let f = cache.floors, f.count == columns { return f }
    var f = [CGFloat](repeating: MarkdownTableMetrics.minColumnFloor, count: columns)
    if subviews.count > cellCount {
        for c in 0..<columns {
            // The probe's natural width is its widest word: the narrowest this column may be.
            let probe = subviews[cellCount + c].sizeThatFits(.unspecified)
            f[c] = Swift.max(MarkdownTableMetrics.minColumnFloor, probe.width + MarkdownTableMetrics.cellPadding)
        }
    }
    cache.floors = f
    SizeStore.shared.keep(cache)
    return f
}
```

and change the tail of `widths(_:_:_:)` to:

```swift
let lo = wraps ? floors(subviews, &cache) : Array(repeating: minColumn, count: columns)
return MarkdownTableMetrics.columnWidths(natural: natural, lo: lo, hi: maxColumn, fill: fillWidth ?? proposal.width)
```

`heights(_:_:_:)` and `placeSubviews` must look at cells only: iterate `subviews.prefix(cellCount)` and count rows as `(cellCount + columns - 1) / columns`. Probes are never placed, so they draw nothing.

In `MarkdownTableGrid`: add `var wraps = false` after `lineLimit`; pass `cellCount: n * (1 + table.rows.count)`, `wraps: wraps` and `maxColumn:` to the layout; use `lineLimit: wraps ? nil : lineLimit` in `text(_:column:header:)`; and append the probes after the cells:

```swift
ForEach(0..<n, id: \.self) { c in
    // Drawn nowhere, measured always: its natural width is the column's floor. Bold, because a bold
    // probe is never narrower than a semibold header or a bold word inside a cell.
    Text(MarkdownTableMetrics.words(table, column: c))
        .font(font.weight(.bold)).lineLimit(nil).fixedSize()
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command. Expected: PASS, whole suites.

- [ ] **Step 5: Commit**

```bash
git add Vory/Chat/MarkdownTableSheet.swift VoryTests/TableWrapTests.swift VoryTests/MarkdownTableTests.swift
git commit -m "feat(table): hold each column at its word floor and draw every line when wrapped"
```

---

### Task 3: The switch, the preference, and the card that falls back

**Files:**
- Modify: `Vory/Chat/MarkdownTableSheet.swift` (`MarkdownTableMetrics.wrapKey`, `TableWrapToggle`)
- Modify: `Vory/Chat/TranscriptView.swift:2298-2385` (`MarkdownTableView`)
- Test: `VoryTests/TableWrapTests.swift`

**Interfaces:**
- Consumes: `MarkdownTableGrid(table:lineLimit:wraps:…)`, `MarkdownTableMetrics.Overflow`, `bubbleColumns`/`bubbleRows`.
- Produces: `MarkdownTableMetrics.wrapKey = "table.wrap"`; `TableWrapToggle`; `MarkdownTableView` honouring the key.

- [ ] **Step 1: Write the failing tests** (append to `TableWrapTests`)

```swift
@MainActor @Test func theSwitchIsFortyFourPointsToHit() {
    UserDefaults.standard.removeObject(forKey: MarkdownTableMetrics.wrapKey)
    let size = Self.draw(TableWrapToggle())
    #expect(size.width >= 44 && size.height >= 44, "the target is \(Int(size.width))x\(Int(size.height))pt")
}

@MainActor @Test func oneKeyDrivesEveryTable() throws {
    let t = try #require(Self.table(Self.three))
    #expect(MarkdownTableMetrics.wrapKey == "table.wrap")
    UserDefaults.standard.removeObject(forKey: MarkdownTableMetrics.wrapKey)
    let wrapped = Self.draw(MarkdownTableView(table: t).frame(width: 320))     // unset: wraps
    UserDefaults.standard.set(false, forKey: MarkdownTableMetrics.wrapKey)
    let scrolling = Self.draw(MarkdownTableView(table: t).frame(width: 320))
    UserDefaults.standard.removeObject(forKey: MarkdownTableMetrics.wrapKey)
    #expect(wrapped.height > scrolling.height, "the switch changed nothing")
}

@MainActor @Test func theAccessibilityTextSizesStillStackInsteadOfScrolling() throws {
    let t = try #require(Self.table(MarkdownTableTests.wide))
    let size = Self.draw(MarkdownTableView(table: t).environment(\.dynamicTypeSize, .accessibility3))
    #expect(size.width <= 321, "the stacked card overflowed at \(size.width) pt")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `… -only-testing:VoryTests/TableWrapTests`
Expected: FAIL — no `MarkdownTableMetrics.wrapKey`, no `TableWrapToggle`.

- [ ] **Step 3: Implement**

In `MarkdownTableMetrics`:

```swift
/// The reader's choice for every table: wrap to fit the bubble, or scroll sideways. One key, so
/// two tables on one screen never disagree, and it outlives the launch.
static let wrapKey = "table.wrap"
```

In `MarkdownTableSheet.swift`, beside `CopyCellMenu`:

```swift
/// The wrap/scroll switch in a table card's corner. The glyph is the change it will make: a
/// scrolling table offers "wrap", a wrapped one offers "unroll".
struct TableWrapToggle: View {
    @AppStorage(MarkdownTableMetrics.wrapKey) private var wrap = true
    var body: some View {
        Button { withAnimation(.snappy) { wrap.toggle() } } label: {
            Image(systemName: wrap ? "arrow.left.and.right" : "text.alignleft")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(wrap ? "Unwrap wide columns" : "Wrap columns to fit")
        .help(wrap ? "Unwrap Columns" : "Wrap Columns")
    }
}
```

In `MarkdownTableView`: add `@AppStorage(MarkdownTableMetrics.wrapKey) private var wrap = true`; raise the grid's `headerInset` from `22` to `44`; split `card` so the wrapped candidate is tried first and the corner holds two 44 pt targets:

```swift
private var wrappedGrid: some View {
    MarkdownTableGrid(table: shownTable, lineLimit: nil, wraps: true,
                      maxColumn: MarkdownTableMetrics.bubbleMaxColumn, headerInset: 44)
}

private var scrollingGrid: some View {          // today's second candidate, unchanged
    ScrollView(.horizontal) { grid }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: MarkdownTableMetrics.Overflow.self) { g in
            MarkdownTableMetrics.overflow(contentWidth: g.contentSize.width, visibleMinX: g.visibleRect.minX, visibleMaxX: g.visibleRect.maxX)
        } action: { _, now in more = now }
        .mask { fade.animation(.easeOut(duration: 0.15), value: more) }
}

private var card: some View {
    Group {
        if wrap {
            // Wrapped first: when the words cannot fit, the grid reports more than the bubble and
            // this falls through to the sideways scroll that keeps a wide table readable.
            ViewThatFits(in: .horizontal) { wrappedGrid; scrollingGrid }
        } else {
            ViewThatFits(in: .horizontal) { grid; scrollingGrid }
        }
    }
    // …background, clipShape, border, .textSelection(.disabled) and the accessibility element as today…
    .overlay(alignment: .topTrailing) {
        // Two 44 pt targets stacked: side by side they would claim a wide gutter from the header.
        VStack(spacing: 0) { openTableButton; TableWrapToggle() }.padding(4)
    }
}
```

`openTableButton` is today's corner button: same glyph, same `.thinMaterial` circle, now with `.frame(width: 44, height: 44)` and `.contentShape(.rect)` around the label so the whole square is the target.

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command, then the full iOS suites and the Mac suite from Global Constraints.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Vory/Chat/TranscriptView.swift Vory/Chat/MarkdownTableSheet.swift VoryTests/TableWrapTests.swift
git commit -m "feat(table): a table wraps to fit the bubble, or scrolls, at the reader's choice"
```

---

### Task 4: Platform gate, and the real thing on the phone

**Files:**
- No new code: this task proves the change on both platforms and on a device.

- [ ] **Step 1: Build the package and run the Mac suite**

```bash
cd Packages/VoryCore && xcodebuild -scheme VoryCore -destination 'generic/platform=macOS' build
cd ../.. && xcodebuild test -scheme VoryMac -destination 'platform=macOS'
```

Expected: `** BUILD SUCCEEDED **`, Mac suite green (it runs `MarkdownTableTests` and `TableWrapTests` too).

- [ ] **Step 2: Run the iOS suites that share this code**

```bash
xcodebuild test -project Vory.xcodeproj -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VoryTests/MarkdownTableTests -only-testing:VoryTests/TableWrapTests \
  -only-testing:VoryTests/CodeWrapTests -only-testing:VoryTests/TextPiecesTests
```

Expected: PASS. `CodeWrapTests` proves the code block's choice still works untouched.

- [ ] **Step 3: Look at it on the phone**

Build and install with `scripts/deploy-device.sh` (local only, in `.git/info/exclude`), open a chat whose reply holds a wide table — the mock gateway's long coding chat has one — and check: wrap on = the whole cell readable in the bubble, the corner switch flips it, wrap off = today's fades and drag came back. Screenshot both states. A screenshot is the evidence; "it builds" is not.

- [ ] **Step 4: Commit anything the device run changed**

```bash
git status --short
git add -A && git commit -m "test(table): the wrap switch on a phone" || echo "nothing to commit"
```
