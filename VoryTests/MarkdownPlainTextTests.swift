import Testing
@testable import VoryCore

/// Copy as Plain Text on the Mac (#402): a reply as it reads, without its markdown. Copy itself keeps copying the
/// markdown (#255).
@Suite struct MarkdownPlainTextTests {
    @Test func inlineMarksGoAndTheWordsStay() {
        #expect(MarkdownPlainText.from("Run **this** now, with `rm -rf` and _care_.") == "Run this now, with rm -rf and care.")
        #expect(MarkdownPlainText.from("See [the docs](https://example.com/docs).") == "See the docs.")
    }

    @Test func blocksAreABlankLineApartAndALinesBreaksStay() {
        #expect(MarkdownPlainText.from("First paragraph.\n\nSecond one,\nwith a break.") == "First paragraph.\n\nSecond one,\nwith a break.")
    }

    @Test func headingsAreTheirWords() {
        #expect(MarkdownPlainText.from("## What I found\n\nThe disk is full.") == "What I found\n\nThe disk is full.")
    }

    @Test func listsKeepTheirBulletsNumbersAndNesting() {
        let md = "- one\n- **two**\n  - two a\n\n1. first\n2. second\n\n- [x] done\n- [ ] not yet"
        #expect(MarkdownPlainText.from(md) == "• one\n• two\n  • two a\n\n1. first\n2. second\n\n☑ done\n☐ not yet")
    }

    @Test func codeIsAsWritten() {
        let md = "Run:\n\n```bash\nfind /var/log -name '*.log.*' -mtime +90 -delete\n```\n\nDone."
        #expect(MarkdownPlainText.from(md) == "Run:\n\nfind /var/log -name '*.log.*' -mtime +90 -delete\n\nDone.")
    }

    @Test func aTablesRowsAreTabSeparated() {
        let md = "| Shard | Errors |\n|---|---:|\n| 001 | **3** |\n| 002 | 0 |"
        #expect(MarkdownPlainText.from(md) == "Shard\tErrors\n001\t3\n002\t0")
    }

    @Test func aQuoteIsItsWordsAndARuleGoes() {
        #expect(MarkdownPlainText.from("> keep the 2 AM run\n\n---\n\nAfter.") == "keep the 2 AM run\n\nAfter.")
    }

    @Test func aPictureIsItsAltText() {
        #expect(MarkdownPlainText.from("Before:\n\n![disk use chart](https://example.com/chart.png)") == "Before:\n\ndisk use chart")
    }
}
