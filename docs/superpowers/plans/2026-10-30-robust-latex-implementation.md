# Robust LaTeX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Vory's LaTeX pipeline robust against parser loop premature termination, table pipe collisions, multi-line display math hijacking, streaming card completion deadlocks, voice synthesis breakdowns, and XSS/memory vulnerabilities.

**Architecture:** Harden `MathNotation` replacement loops with advancing search offsets, teach `MarkdownBlocks` table parser to respect math delimiters and prevent single-line display math runaway, key `MathCardView` tasks to both equation and closure state with HTML-safe fallback, add multiline math fence support to `SpokenText.Incremental`, and bound `KaTeXCache` with `NSCache`.

**Tech Stack:** Swift 6.2, Swift Testing (`@Test`, `#expect`), SwiftUI, WebKit (`WKWebView`), JavaScriptCore (`JSContext`), Foundation (`NSCache`, `AttributedString`).

**Spec:** Direct remediation of verified findings from the LaTeX Boost Investigation.

## Global Constraints

- Target platform: iOS 27.0+ (iOS Simulator `iPhone 17`).
- Swift 6 strict concurrency compliance (`Sendable`, `@MainActor`, `nonisolated`).
- Zero external package dependencies for `VoryCore`.
- Existing test suites (`VoryTests/MarkdownMathTests.swift` and `VoryTests/InlineMathAuditTests.swift`) must remain 100% passing.

## Review Focus

- Incomplete/streaming LaTeX (e.g., `\frac{1} + \frac{a}{b}`) must not abandon later valid expressions.
- Markdown table rows containing pipes inside math spans (e.g. `| $P(A|B)$ | $f(x) = |x|$ |`) must not misalign or split columns.
- Display math on a single line followed by prose (e.g. `$$E=mc^2$$ where E is energy`) must not open an unclosed block swallowing subsequent lines.
- Voice/TTS during streaming must speak multiline display math and LaTeX environments cleanly rather than spelling out backslashes and braces.
- Raw HTML tags in LaTeX fallback strings (e.g. `<script>` or `<img onerror=alert(1)>`) must be escaped before loading into `WKWebView`.

---

### Task 1: Harden `MathNotation.swift` Loop Replacements & Expand Notation

**Files:**
- Modify: `Packages/VoryCore/Sources/VoryCore/Chat/MathNotation.swift:478-650`
- Test: `VoryTests/InlineMathAuditTests.swift`

**Interfaces:**
- Consumes: `extractArgument`, `extractBracedContent` in `MathNotation.swift`
- Produces: Robust `MathNotation.format(_:)` and `MathNotation.spoken(_:)` handling multiple consecutive formulas without premature loop abortion.

- [ ] **Step 1: Write failing tests for loop resilience and fraction variants**

Add tests to `VoryTests/InlineMathAuditTests.swift`:
```swift
@Test func testLoopResilienceWithPrefixInterferenceAndStreamingTokens() {
    // 1. Accents: \barrier should not abort \bar{x}
    let accentInput = "\\barrier + \\bar{x} + \\bar{y}"
    let accentOutput = MathNotation.format(accentInput)
    #expect(accentOutput.contains("x̄") && accentOutput.contains("ȳ"))

    // 2. Fractions: streaming/malformed \frac should not drop later \frac
    let fracInput = "\\frac{1} + \\frac{a}{b}"
    let fracOutput = MathNotation.format(fracInput)
    #expect(fracOutput.contains("a/b"))

    // 3. Fraction variants: \dfrac and \tfrac
    let dfracInput = "\\dfrac{1}{2} + \\tfrac{3}{4}"
    let dfracOutput = MathNotation.format(dfracInput)
    #expect(dfracOutput.contains("1/2") && dfracOutput.contains("3/4"))

    // 4. Stacking: malformed \overset should not drop later \overset
    let stackInput = "\\overset{?}{=} and \\overset{!}{=}"
    let stackOutput = MathNotation.format(stackInput)
    #expect(!stackOutput.contains("\\overset"))
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `xcodebuild test -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VoryTests/InlineMathAuditTests/testLoopResilienceWithPrefixInterferenceAndStreamingTokens`
Expected: FAIL on `\barrier + \bar{x}` and `\dfrac{1}{2}`.

- [ ] **Step 3: Update `MathNotation.swift` loop cursors and fraction variants**

1. In `replaceAccents`, `replaceFontVariants`, `replaceSquareRoots`, `unwrapTextCommands`, `liftScriptTextCommands`, `replaceFractions`, `replaceBinomials`, and `replaceStacking`:
   Replace unbounded `while let r = s.range(of: tag)` with a cursor-based scan:
   ```swift
   var searchStart = s.startIndex
   while searchStart < s.endIndex, let r = s.range(of: tag, range: searchStart..<s.endIndex) {
       // if match is invalid or prefix is word character, advance cursor:
       // searchStart = r.upperBound; continue
   }
   ```
2. In `replaceFractions`, support `\dfrac`, `\tfrac`, `\cfrac` alongside `\frac`.
3. In `symbols`, add `("pmod", "mod")` and strip sizing commands (`\Huge`, `\huge`, `\large`, `\normalsize`, `\small`, `\footnotesize`, `\tiny`).

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild test -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VoryTests/InlineMathAuditTests/testLoopResilienceWithPrefixInterferenceAndStreamingTokens`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/VoryCore/Sources/VoryCore/Chat/MathNotation.swift VoryTests/InlineMathAuditTests.swift
git commit -m "fix(math): prevent premature loop termination and support fraction variants"
```

---

### Task 2: Protect Markdown Table Parsing & Multi-Line Display Math Delimiters

**Files:**
- Modify: `Packages/VoryCore/Sources/VoryCore/Chat/MarkdownBlocks.swift:270-305, 515-545`
- Test: `VoryTests/MarkdownMathTests.swift`

**Interfaces:**
- Consumes: `MarkdownParser.parse(_:)`, `MarkdownBlocks.tableCells(_:)`
- Produces: Correct table structure containing math pipes and un-hijacked single-line display math blocks.

- [ ] **Step 1: Write failing tests for table pipes and display math line hijacking**

Add tests to `VoryTests/MarkdownMathTests.swift`:
```swift
@Test func testTableCellsWithMathPipes() {
    let markdown = """
    | Condition | Value |
    |---|---|
    | $P(A|B)$ | $f(x) = |x|$ |
    """
    let blocks = MarkdownBlocks.parse(markdown)
    guard case .table(let headers, let rows) = blocks.first else {
        Issue.record("Expected table block")
        return
    }
    #expect(headers.count == 2)
    #expect(rows.count == 1)
    #expect(rows[0].count == 2)
    #expect(rows[0][0].contains("P(A|B)"))
    #expect(rows[0][1].contains("|x|"))
}

@Test func testSingleLineDisplayMathWithTrailingProseDoesNotHijackParagraphs() {
    let markdown = """
    $$x = 1$$ where x is initial state
    This is regular prose that must not be swallowed.
    """
    let blocks = MarkdownBlocks.parse(markdown)
    #expect(blocks.count >= 2)
    guard case .paragraph(let text) = blocks.last else {
        Issue.record("Expected last block to be paragraph, got \(String(describing: blocks.last))")
        return
    }
    #expect(text.contains("regular prose"))
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `xcodebuild test -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VoryTests/MarkdownMathTests/testTableCellsWithMathPipes`
Expected: FAIL due to pipe splitting into 4 cells instead of 2.

- [ ] **Step 3: Implement math delimiter awareness in `tableCells` and delimiter check in `parse`**

1. In `MarkdownBlocks.swift` `tableCells`:
   Track `inMath` toggled by `$` (handling escaped `\$`) and `\(` / `\)`. Do not treat `|` as a cell delimiter when `inMath` is true. Also preserve escaped `\|` when reconstructing cells.
2. In `MarkdownParser.parse`:
   Before opening a multiline `mathFence = "$$"`, check if the line contains a closing `$$` after the initial one. If so, treat the equation as inline or split the single-line block cleanly so subsequent lines remain paragraphs.

- [ ] **Step 4: Run test to verify pass**

Run: `xcodebuild test -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VoryTests/MarkdownMathTests/testTableCellsWithMathPipes -only-testing:VoryTests/MarkdownMathTests/testSingleLineDisplayMathWithTrailingProseDoesNotHijackParagraphs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/VoryCore/Sources/VoryCore/Chat/MarkdownBlocks.swift VoryTests/MarkdownMathTests.swift
git commit -m "fix(markdown): protect table pipes in math and prevent display math hijacking"
```

---

### Task 3: Streaming Card Re-Triggering, HTML Sanitization & Bounded KaTeX Cache

**Files:**
- Modify: `Vory/Chat/MathCard.swift:12-40, 67-91, 355-360`
- Test: `VoryTests/MarkdownMathTests.swift`

**Interfaces:**
- Consumes: `KaTeXEngine.render(latex:)`, `MathCardView`, `KaTeXCache`
- Produces: Memory-safe KaTeX caching, XSS-safe fallback HTML, and responsive completion of streaming math cards.

- [ ] **Step 1: Write unit tests for KaTeX HTML fallback escaping and cache eviction**

Add to `VoryTests/MarkdownMathTests.swift`:
```swift
@Test func testKaTeXFallbackHTMLEscaping() async {
    let maliciousLatex = "\\invalidCommand{<script>alert('xss')</script>}"
    let html = await KaTeXEngine.shared.render(latex: maliciousLatex)
    #expect(!html.contains("<script>"))
    #expect(html.contains("&lt;script&gt;") || html.contains("&lt;") || !html.contains("<script"))
}
```

- [ ] **Step 2: Run test to verify behavior**

Run: `xcodebuild test -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VoryTests/MarkdownMathTests/testKaTeXFallbackHTMLEscaping`
Expected: FAIL if fallback injects unescaped `<script>`.

- [ ] **Step 3: Implement fixes in `MathCard.swift`**

1. In `KaTeXCache`:
   Replace unbounded dictionaries `[String: String]` and `[String: CGSize]` with `NSCache<NSString, NSString>` and `NSCache<NSString, NSValue>` with `countLimit = 500`.
2. In `KaTeXEngine.render`:
   When returning `fallbackHtml`, sanitize `fallback` by replacing `&`, `<`, `>`, `"`, `'` with their respective HTML entities.
3. In `MathCardView`:
   Change the task trigger from `.task(id: equation)` to:
   ```swift
   .task(id: "\(equation):\(closed)") {
       if closed && mathMarkup == nil {
           let markup = await KaTeXEngine.shared.render(latex: equation)
           mathMarkup = markup
       }
   }
   ```

- [ ] **Step 4: Run test to verify pass**

Run: `xcodebuild test -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VoryTests/MarkdownMathTests/testKaTeXFallbackHTMLEscaping`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Vory/Chat/MathCard.swift VoryTests/MarkdownMathTests.swift
git commit -m "fix(mathcard): sanitize fallback html, bound katexcache, and re-trigger on closed"
```

---

### Task 4: Voice Synthesis Multiline Math Support & Speech Vocabulary Expansion

**Files:**
- Modify: `Packages/VoryCore/Sources/VoryCore/Voice/SpokenText.swift:22-107`, `Packages/VoryCore/Sources/VoryCore/Chat/MathNotation.swift:240-279`
- Test: `VoryTests/MathNotationTests.swift`

**Interfaces:**
- Consumes: `SpokenText.Incremental`, `MathNotation.spoken(_:)`
- Produces: Natural spoken representation of multiline display math and LaTeX environments during live audio streaming.

- [ ] **Step 1: Write failing tests for multiline math speech and subscript/superscript vocalization**

Add to `VoryTests/MathNotationTests.swift`:
```swift
@Test func testSpokenSubscriptsAndSuperscripts() {
    let eq = "x_1 + y^4 + z^n"
    let spoken = MathNotation.spoken(eq)
    #expect(spoken.contains("1") && spoken.contains("to the power of 4") && spoken.contains("to the power of n"))
    #expect(!spoken.contains("caret"))
}

@Test func testIncrementalVoiceMultilineDisplayMath() {
    var incremental = SpokenText.Incremental()
    _ = incremental.consume(line: "$$")
    _ = incremental.consume(line: "\\int_0^1 x dx")
    let utterances = incremental.consume(line: "$$")
    let joined = utterances.joined(separator: " ")
    #expect(joined.contains("integral"))
    #expect(!joined.contains("backslash"))
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `xcodebuild test -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VoryTests/MathNotationTests/testSpokenSubscriptsAndSuperscripts -only-testing:VoryTests/MathNotationTests/testIncrementalVoiceMultilineDisplayMath`
Expected: FAIL.

- [ ] **Step 3: Implement multiline math fence in `SpokenText.Incremental` & improve `MathNotation.spoken`**

1. In `SpokenText.Incremental`:
   Add `mathFence: String?` and `mathBuffer: [String]`. When encountering `$$`, `\\[`, or `\\begin{...}`, accumulate lines until closed, then emit `MathNotation.spoken(equation)`.
2. In `MathNotation.spoken`:
   - Map subscript digits `₀`–`₉` to `" 0 "`–`" 9 "` and superscripts `⁴`–`⁹` to `" to the power of 4 "`–`" to the power of 9 "`.
   - Map single-letter powers `^([a-zA-Z0-9])` to `" to the power of $1 "`.
   - Distinguish absolute value `|x|` (spoken as `"absolute value of x"`) from conditional probability `$P(A|B)$` (`"given"`).

- [ ] **Step 4: Run test to verify pass**

Run: `xcodebuild test -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VoryTests/MathNotationTests/testSpokenSubscriptsAndSuperscripts -only-testing:VoryTests/MathNotationTests/testIncrementalVoiceMultilineDisplayMath`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/VoryCore/Sources/VoryCore/Voice/SpokenText.swift Packages/VoryCore/Sources/VoryCore/Chat/MathNotation.swift VoryTests/MathNotationTests.swift
git commit -m "feat(voice): support multiline display math and improve subscript/superscript speech"
```

---

### Task 5: Full Verification & Performance Audit on iPhone 17 Simulator

**Files:**
- Test: Full test suite (`VoryTests`)

**Interfaces:**
- Consumes: All hardened math components.
- Produces: Complete clean test run and zero regressions.

- [ ] **Step 1: Execute complete test suite**

Run: `xcodebuild test -scheme Vory -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 100% PASS across all unit, markdown, math, and snapshot tests.

- [ ] **Step 2: Run swift-format / lint checks**

Run: `git diff --stat` to verify only intended files were modified.

- [ ] **Step 3: Final verification commit and sign-off**

```bash
git add .
git commit -m "chore(audit): verify robust latex implementation across all test targets"
```
