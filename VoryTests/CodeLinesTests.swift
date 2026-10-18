import Foundation
import Testing
@testable import Vory

/// #421: a code block's line count and first lines, read without splitting the text (a big tool output was split
/// into tens of thousands of lines on every redraw of its card). Same answers as the split it replaces.
@Suite struct CodeLinesTests {
    /// What CodeBlock worked out before: the count, and the first `cap` lines joined again.
    private func bySplit(_ text: String, cap: Int) -> (count: Int, head: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return (lines.count, lines.count <= cap ? text : lines.prefix(cap).joined(separator: "\n"))
    }

    @Test func theSameAsSplittingIt() {
        let texts = ["", "one", "one\n", "\n", "\n\n\n", "a\nb", "a\nb\nc", "a\n\nb\n", "é\n😀 two\nthree", String(repeating: "x", count: 5000),
                     (1...100).map { "line \($0)" }.joined(separator: "\n"), (1...30).map { "l\($0)" }.joined(separator: "\n") + "\n"]
        for text in texts {
            for cap in [1, 2, 3, 30, 40] {
                let new = TextPieces.lines(text, cap: cap)
                let old = bySplit(text, cap: cap)
                #expect(new.count == old.count, "count of \(text.prefix(20).debugDescription) at \(cap)")
                // CodeBlock shows the whole text when it has no more lines than the cap.
                let shown = new.count <= cap ? text : String(new.head)
                #expect(shown == old.head, "head of \(text.prefix(20).debugDescription) at \(cap)")
            }
        }
    }

    @Test func aBridgedStringToo() {
        let text = NSString(string: "first\nsecond\nthird") as String
        let r = TextPieces.lines(text, cap: 2)
        #expect(r.count == 3)
        #expect(r.head == "first\nsecond")
    }

    @Test func timedOnTwoMegabytes() {
        let big = (0..<33_000).map { String(format: "%05d  shard-%03d INFO request %d served in %d ms", $0, $0 % 97, $0 * 7919 % 10007, $0 % 90 + 3) }.joined(separator: "\n")
        var t0 = Date()
        for _ in 0..<5 { _ = bySplit(big, cap: 30) }
        let split = Date().timeIntervalSince(t0) / 5
        t0 = Date()
        for _ in 0..<5 { _ = TextPieces.lines(big, cap: 30) }
        let scan = Date().timeIntervalSince(t0) / 5
        print(String(format: "C421 code lines on %d bytes: split %.1f ms, scan %.2f ms", big.utf8.count, split * 1000, scan * 1000))
        #expect(TextPieces.lines(big, cap: 30).count == 33_000)
    }
}
