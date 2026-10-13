import Foundation
import Testing
@testable import VoryCore

/// A streaming reply parses only what follows its settled part (`MarkdownParser.Settled`): at every
/// step its blocks must be the ones the whole text parses to, whatever the reply holds.
@Suite struct MarkdownStreamTests {
    /// Streams `text` cut at `cuts` (character counts), carrying the settled part from step to
    /// step, and checks each step against the whole parse. Returns how many steps parsed a tail.
    @discardableResult
    private func stream(_ text: String, cuts: [Int], sourceLocation: SourceLocation = #_sourceLocation) -> Int {
        let chars = Array(text)
        var settled: MarkdownParser.Settled?
        var tails = 0
        for cut in cuts {
            let prefix = String(chars[..<cut])
            if let s = settled, prefix.hasPrefix(s.text) { tails += 1 }
            let step = MarkdownParser.blocks(from: prefix, after: settled)
            let whole = MarkdownParser.blocks(from: prefix)
            #expect(step.blocks == whole, "at \(cut) of \(chars.count): \(prefix.debugDescription)", sourceLocation: sourceLocation)
            if step.blocks != whole { return tails }
            settled = step.settled
        }
        return tails
    }

    private func everyCharacter(_ text: String) -> [Int] { Array(0...text.count) }

    @Test func paragraphsHeadingsAndRules() {
        let text = "Intro line\nstill intro\n\n# Heading\n\nNext paragraph\n\n---\n\nAfter the rule\n   \nwhitespace line above\n\n\n\nmany blanks"
        #expect(stream(text, cuts: everyCharacter(text)) > 0)
    }

    @Test func codeFencesKeepTheirBlankLines() {
        let text = "Before\n\n```swift\nlet a = 1\n\nlet b = 2\n\n\n```\n\nBetween\n\n~~~\nx\n\n~~~\n\nAn open one:\n\n```\nnever\n\nclosed"
        #expect(stream(text, cuts: everyCharacter(text)) > 0)
    }

    @Test func listsAcrossBlankLines() {
        let text = "1. first\n2. second\n\n3. third after a blank\n   continued\n\n- a\n  - b\n    - c\n\n  - d after a blank\n- [ ] task\n- [x] done\n\n10) ten\n11) eleven"
        #expect(stream(text, cuts: everyCharacter(text)) > 0)
    }

    @Test func quotesTablesAndImages() {
        let text = "> quoted\n> more\n\n| a | b |\n|---|:-:|\n| 1 | 2 |\n\n| 3 | 4 |\n\nheader | only\n\n|x|y|\n|-|-|\n![logo](https://x.test/a.png)\n\n[![b](https://x.test/b.svg)](https://x.test)\n\nend"
        #expect(stream(text, cuts: everyCharacter(text)) > 0)
    }

    @Test func aReplyOpeningWithBlankLines() {
        let text = "\n\n\nFirst words\n\nSecond"
        #expect(stream(text, cuts: everyCharacter(text)) > 0)
    }

    /// A long reply streamed a character at a time, so its growing end stops inside every code
    /// fence (blank lines inside it), every loose list (blank lines between its items, one nested)
    /// and every table: each step equals the whole parse, and most steps parse only the tail.
    @Test func aLongReplyStopsInsideFencesListsAndTables() {
        var parts: [String] = []
        for k in 0..<10 {
            parts.append("Paragraph \(k) of a long reply, with **bold** words and a [link](https://x.test/\(k)).")
            parts.append("```swift\nlet a\(k) = 1\n\nlet b\(k) = a\(k) + 1\n\n\n```")
            parts.append("1. first \(k)\n\n2. second, after a blank\n   continued\n\n   3. nested, after a blank")
            parts.append("| col | n |\n|---|--:|\n| a | \(k) |\n| b | \(k + 1) |")
        }
        let text = parts.joined(separator: "\n\n")
        let tails = stream(text, cuts: everyCharacter(text))
        #expect(tails > text.count / 2, "only \(tails) of \(text.count) steps parsed a tail")
    }

    /// Front matter, a byte order mark and CR LF line ends are read off the whole text: those
    /// texts are parsed whole, and still come out right.
    @Test func textsParsedWhole() {
        for text in ["---\ntitle: Hi\n---\n\n# Body\n\npara", "\u{FEFF}---\ntitle: x\n---\n\nBody\n\nmore",
                     "---\n\nA reply that opens with a rule\n\nand goes on", "One\r\n\r\nTwo\r\n\r\nThree",
                     "Plain at first\n\nthen CR LF\r\n\r\nlines\r\n"] {
            stream(text, cuts: everyCharacter(text))
        }
    }

    /// Random replies from a pool of lines, streamed in random steps.
    @Test func randomReplies() {
        let pool = ["Plain words here.", "", "", "  ", "# Heading", "## Sub heading", "- item", "  - nested item",
                    "    indented text", "1. first", "2) second", "10. tenth", "- [ ] task", "- [x] done", "> quoted",
                    "> more quote", "```swift", "```", "~~~", "let x = 1", "| a | b |", "|---|:-:|", "| 1 | 2 |",
                    "---", "***", "![img](https://x.test/a.png)", "Text with a | pipe", "\tTabbed", "@mention here"]
        var rng = SeededGenerator(seed: 0x5EED)
        var tails = 0
        for _ in 0..<150 {
            let text = (0..<Int.random(in: 5...40, using: &rng)).map { _ in pool.randomElement(using: &rng)! }.joined(separator: "\n")
            var cuts: [Int] = [], at = 0
            while at < text.count { at = min(text.count, at + Int.random(in: 1...12, using: &rng)); cuts.append(at) }
            tails += stream(text, cuts: cuts)
        }
        #expect(tails > 0)
    }

    /// A long reply streamed a few characters a token: the tail parse is a fraction of the whole
    /// one, which grew with the reply's length on every token.
    @Test func aLongReplyParsesItsTailOnly() {
        let para = "The export ran in three passes; each pass wrote its rows and checked the totals against the ledger before moving on."
        var parts: [String] = []
        for k in 0..<90 {
            parts.append("\(para) Part \(k).")
            if k % 10 == 0 { parts.append("- one\n- two\n  - two and a half\n- three") }
            if k % 30 == 0 { parts.append("```\nlet a = \(k)\n\nlet b = a\n```") }
        }
        let text = parts.joined(separator: "\n\n")
        let chars = Array(text)
        let prefixes = (Array(stride(from: 12, to: chars.count, by: 12)) + [chars.count]).map { String(chars[..<$0]) }

        var began = Date()
        var whole: [MarkdownBlock] = []
        for p in prefixes { whole = MarkdownParser.blocks(from: p) }
        let wholeTook = Date().timeIntervalSince(began)

        began = Date()
        var settled: MarkdownParser.Settled?
        var tail: [MarkdownBlock] = []
        for p in prefixes { (tail, settled) = MarkdownParser.blocks(from: p, after: settled) }
        let tailTook = Date().timeIntervalSince(began)

        print("MD-STREAM \(chars.count) chars, \(prefixes.count) tokens: whole \(Int(wholeTook * 1000)) ms, tail \(Int(tailTook * 1000)) ms")
        #expect(tail == whole)
        #expect(tailTook * 10 < wholeTook, "tail \(tailTook) s, whole \(wholeTook) s")
    }
}

/// SplitMix64: the same random replies on every run.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
