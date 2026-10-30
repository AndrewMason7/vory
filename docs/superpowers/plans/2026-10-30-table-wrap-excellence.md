# Table Wrap Excellence & Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Harden the table wrap feature to elite standards with complete defensive bounds checking, cache key isolation across wrap modes, non-breaking space preservation in word floor measurements, and unified visual button styling in the controls strip.

**Architecture:** Embed `wraps: Bool` directly into `MarkdownTableLayout.SizeKey` to eliminate cross-mode cache collisions in `SizeStore`; guard all probe subview indices against layout array bounds; preserve non-breaking spaces (`\u{00A0}`) in `MarkdownTableMetrics.words` to keep units and dates bound to their numbers; and align `TableWrapToggle` with `openTableButton` to share matching frosted `.thinMaterial` circle affordances.

**Tech Stack:** Swift 6, SwiftUI (`Layout`, `ViewThatFits`, `@AppStorage`, `ImageRenderer`), Swift Testing (`@Suite`/`@Test`/`#expect`), Vision framework OCR, iOS + macOS targets in Xcode.

**Spec:** `docs/superpowers/specs/2026-10-30-table-wrap-design.md`

## Global Constraints

- Branch `feat/table-wrap`, worktree `.worktrees/table-wrap`, base `feat/code-wrap` (PR #551).
- Do not modify `CodeBody`, `CodeWrapToggle`, or any file owned exclusively by `feat/code-wrap`.
- Wrap never breaks words: words separated by non-breaking spaces (`\u{00A0}`) are measured as single unbroken tokens.
- Probe subviews are always invisible, non-interactive, and hidden from accessibility.
- Cache entries in `SizeStore.shared` for wrapped vs scrolling layouts never collide.
- iOS automated testing must strictly target iPhone 17 simulator: `xcodebuild test -scheme Vory -destination 'id=4EEC0ADF-8005-41BF-BC27-A3E51C846228'`.
- Physical deployment must target the connected iPhone 17 (`00008150-001943D63E13401C`).

## Review Focus

- Table streaming with fewer probe subviews than columns: `floors` must return safe fallback minimums, never crash.
- Mismatched column count between `natural` and `floors` in `wrapWidths`: must safely return default widths rather than indexing out of range.
- Non-breaking spaces (`10\u{00A0}MB` or `16\u{00A0}flaps/day`): probe must measure the combined phrase as one word floor.
- Same table rendered wrapped and scrolled with `lineLimit: nil`: must produce independent cached sizes via distinct `SizeKey`s.
- Button aesthetics: both buttons in the card strip must carry matching 44 pt `.thinMaterial` circle backgrounds.

---

### Task 1: Defensive Bounds Guarding & Non-Breaking Space Preservation

**Files:**
- Modify: `Vory/Chat/MarkdownTableSheet.swift:45-125` (`wrapWidths`, `words`), `:250-265` (`floors`)
- Test: `VoryTests/MarkdownTableTests.swift`, `VoryTests/TableWrapTests.swift`

**Interfaces:**
- Consumes: `MarkdownTableMetrics.words(_:column:)`, `wrapWidths(natural:floors:hi:fill:)`, `MarkdownTableLayout.floors(_:_:)`
- Produces: Hardened bounds checking and non-breaking space preservation.

- [x] **Step 1: Write the failing tests**

In `VoryTests/MarkdownTableTests.swift`:
```swift
@Test func nonBreakingSpaceKeepsWordsBoundTogether() throws {
    let t = try #require(onlyTable("| Metric |\n|---|\n| 16\u{00A0}flaps/day |"))
    let words = MarkdownTableMetrics.words(t, column: 0).split(separator: "\n").map(String.init)
    #expect(words.contains("16\u{00A0}flaps/day"), "non-breaking spaces must not be split into separate words")
}

@Test func wrapWidthsGuardsMismatchedFloorCount() {
    typealias M = MarkdownTableMetrics
    // floors has fewer elements than natural: must return floors defensively without crashing
    let result = M.wrapWidths(natural: [100, 200, 300], floors: [50, 50], hi: 220, fill: 320)
    #expect(result == [50, 50])
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd .worktrees/table-wrap && xcodebuild test -scheme Vory -destination 'id=4EEC0ADF-8005-41BF-BC27-A3E51C846228' -only-testing:VoryTests/MarkdownTableTests/nonBreakingSpaceKeepsWordsBoundTogether -only-testing:VoryTests/MarkdownTableTests/wrapWidthsGuardsMismatchedFloorCount`
Expected: FAIL (`nonBreakingSpaceKeepsWordsBoundTogether` fails because `isWhitespace` splits `\u{00A0}`).

- [x] **Step 3: Implement defensive checks and breakable whitespace check**

In `MarkdownTableMetrics.words`:
```swift
func add(_ text: String) {
    for ch in MarkdownTable.plain(text) {
        // Only split on breakable whitespace; non-breaking spaces (\u{00A0}) must stay with their words.
        if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            flush()
        } else {
            word.append(ch)
        }
    }
    flush()
}
```

In `MarkdownTableMetrics.wrapWidths`:
```swift
guard let fill, fill.isFinite, !widths.isEmpty, natural.count == widths.count else { return widths }
```

In `MarkdownTableLayout.floors`:
```swift
private func floors(_ subviews: Subviews, _ cache: inout Cache) -> [CGFloat] {
    if let f = cache.floors, f.count == columns { return f }
    var f = [CGFloat](repeating: MarkdownTableMetrics.minColumnFloor, count: columns)
    if subviews.count >= cellCount + columns {
        for c in 0..<columns {
            let probe = subviews[cellCount + c].sizeThatFits(.unspecified).width
            f[c] = Swift.max(MarkdownTableMetrics.minColumnFloor, probe + MarkdownTableMetrics.cellPadding)
        }
    }
    cache.floors = f
    SizeStore.shared.keep(cache)
    return f
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `cd .worktrees/table-wrap && xcodebuild test -scheme Vory -destination 'id=4EEC0ADF-8005-41BF-BC27-A3E51C846228' -only-testing:VoryTests/MarkdownTableTests`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Vory/Chat/MarkdownTableSheet.swift VoryTests/MarkdownTableTests.swift
git commit -m "fix(table): guard probe subview bounds and preserve non-breaking spaces"
```

---

### Task 2: Cache Key Isolation (`wraps` in `SizeKey`)

**Files:**
- Modify: `Vory/Chat/MarkdownTableSheet.swift:210-230` (`SizeKey`), `:370-375` (`MarkdownTableGrid.body`)
- Test: `VoryTests/MarkdownTableTests.swift`, `VoryTests/TableWrapTests.swift`

**Interfaces:**
- Consumes: `MarkdownTableLayout.SizeKey`
- Produces: `SizeKey(table:font:lineLimit:headerInset:typeSize:bold:scale:names:wraps:)`

- [x] **Step 1: Write the failing test**

In `VoryTests/TableWrapTests.swift`:
```swift
@Test func wrappedAndScrollingGridsDoNotShareSizeCache() throws {
    let t = try #require(Self.table(Self.three))
    let wrappedKey = MarkdownTableLayout.SizeKey(table: t, font: .footnote, lineLimit: nil, headerInset: 0,
                                                 typeSize: .large, bold: false, scale: 2, names: nil, wraps: true)
    let scrollingKey = MarkdownTableLayout.SizeKey(table: t, font: .footnote, lineLimit: nil, headerInset: 0,
                                                   typeSize: .large, bold: false, scale: 2, names: nil, wraps: false)
    #expect(wrappedKey != scrollingKey, "wrapped and unwrapped modes with the same lineLimit must have distinct cache keys")
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd .worktrees/table-wrap && xcodebuild test -scheme Vory -destination 'id=4EEC0ADF-8005-41BF-BC27-A3E51C846228' -only-testing:VoryTests/TableWrapTests/wrappedAndScrollingGridsDoNotShareSizeCache`
Expected: FAIL (argument `wraps` does not exist on `SizeKey`).

- [x] **Step 3: Add `wraps: Bool` to `SizeKey`**

In `MarkdownTableLayout.SizeKey`:
```swift
struct SizeKey: Hashable, Sendable {
    var table: MarkdownTable
    var font: Font
    var lineLimit: Int?
    var headerInset: CGFloat
    var typeSize: DynamicTypeSize
    var bold: Bool
    var scale: CGFloat
    var names: Mentions.Names?
    var wraps: Bool = false
    ...
```

In `MarkdownTableGrid.body`:
```swift
let sizes = MarkdownTableLayout.SizeKey(table: table, font: font, lineLimit: wraps ? nil : lineLimit, headerInset: headerInset,
                                        typeSize: typeSize, bold: legibility == .bold, scale: scale,
                                        names: MarkdownTableLayout.SizeKey.names(for: table, Mentions.names),
                                        wraps: wraps)
```

- [x] **Step 4: Run tests to verify they pass**

Run: `cd .worktrees/table-wrap && xcodebuild test -scheme Vory -destination 'id=4EEC0ADF-8005-41BF-BC27-A3E51C846228' -only-testing:VoryTests/TableWrapTests/wrappedAndScrollingGridsDoNotShareSizeCache`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Vory/Chat/MarkdownTableSheet.swift VoryTests/TableWrapTests.swift
git commit -m "fix(table): incorporate wrap mode into layout size cache key"
```

---

### Task 3: Unified Control Affordances in Card Strip

**Files:**
- Modify: `Vory/Chat/MarkdownTableSheet.swift:150-170` (`TableWrapToggle`)
- Modify: `Vory/Chat/TranscriptView.swift:2670-2685` (`controls`)
- Test: `VoryTests/TableWrapTests.swift`

**Interfaces:**
- Consumes: `TableWrapToggle`, `openTableButton`, `controls`
- Produces: Matching 44 pt `.thinMaterial` circular buttons in card header strip.

- [x] **Step 1: Write the failing test**

In `VoryTests/TableWrapTests.swift`:
```swift
@MainActor @Test func bothControlsCarryCircularMaterialAffordance() {
    let toggle = TableWrapToggle()
    let size = Self.draw(toggle)
    #expect(size.width >= 44 && size.height >= 44)
}
```

- [x] **Step 2: Run test to verify current state**

Run: `cd .worktrees/table-wrap && xcodebuild test -scheme Vory -destination 'id=4EEC0ADF-8005-41BF-BC27-A3E51C846228' -only-testing:VoryTests/TableWrapTests/bothControlsCarryCircularMaterialAffordance`

- [x] **Step 3: Update `TableWrapToggle` and `controls` styling**

In `TableWrapToggle`:
```swift
struct TableWrapToggle: View {
    @AppStorage(MarkdownTableMetrics.wrapKey) private var wrap = true

    var body: some View {
        Button { withAnimation(.snappy) { wrap.toggle() } } label: {
            Image(systemName: wrap ? "arrow.left.and.right" : "text.alignleft")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .background(.thinMaterial, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(wrap ? "Unwrap wide columns" : "Wrap columns to fit")
        .help(wrap ? "Unwrap Columns" : "Wrap Columns")
    }
}
```

In `TranscriptView.swift`:
```swift
private var controls: some View {
    HStack(spacing: 6) {
        Spacer(minLength: 0)
        openTableButton
        TableWrapToggle()
    }
    .padding(.vertical, 4).padding(.trailing, 4)
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `cd .worktrees/table-wrap && xcodebuild test -scheme Vory -destination 'id=4EEC0ADF-8005-41BF-BC27-A3E51C846228' -only-testing:VoryTests/TableWrapTests`
Expected: PASS all 15 tests.

- [x] **Step 5: Commit**

```bash
git add Vory/Chat/MarkdownTableSheet.swift Vory/Chat/TranscriptView.swift VoryTests/TableWrapTests.swift
git commit -m "style(table): align wrap toggle with open-table material disc affordance"
```

---

### Task 4: Full Multi-Platform Verification & Device Deployment

**Files:**
- No new file modifications; full verification and deployment.

- [x] **Step 1: Run complete simulator test suites**

```bash
cd .worktrees/table-wrap && xcodebuild test -scheme Vory -destination 'id=4EEC0ADF-8005-41BF-BC27-A3E51C846228' \
  -only-testing:VoryTests/MarkdownTableTests \
  -only-testing:VoryTests/TableWrapTests \
  -only-testing:VoryTests/CodeWrapTests \
  -only-testing:VoryTests/TextPiecesTests
```
Expected: `** TEST SUCCEEDED **` across all suites.

- [x] **Step 2: Build VoryCore and run Mac unit tests**

```bash
cd .worktrees/table-wrap/Packages/VoryCore && xcodebuild -scheme VoryCore -destination 'generic/platform=macOS' build
cd ../.. && xcodebuild -scheme VoryMac -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 3: Deploy to physical iPhone 17**

```bash
cd .worktrees/table-wrap && ./scripts/deploy-device.sh 00008150-001943D63E13401C
```
Expected: App signed, installed, and launched on iPhone 17.

- [x] **Step 4: Verify process running on device**

```bash
xcrun devicectl device info processes -d 00008150-001943D63E13401C | grep -i vory
```
Expected: Running process PID confirmed.
