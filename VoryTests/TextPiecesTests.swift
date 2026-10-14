import Foundation
import SwiftUI
import Testing
@testable import Vory
@testable import VoryCore

// Long text drawn in pieces (#361): where the cuts fall, that nothing is lost or doubled, that a streaming text keeps
// its earlier pieces, and the caps on folds and table cells. Nothing here is drawn.

@Suite struct TextPiecesTests {
    @Test func aShortTextIsOnePiece() {
        #expect(!TextPieces.isLong("The disk is fine."))
        #expect(TextPieces.ranges("The disk is fine.") == [0..<17])
        #expect(TextPieces.strings("The disk is fine.") == ["The disk is fine."])
    }

    @Test func aLongParagraphIsCutAfterASentenceAndNothingIsLost() {
        let text = String(repeating: "The disk on web-01 is at 79 percent and rising slowly. ", count: 400)
        #expect(TextPieces.isLong(text))
        let r = TextPieces.ranges(text)
        #expect(r.count > 10)
        #expect(r.allSatisfy { $0.count <= TextPieces.limit && $0.count >= TextPieces.limit / 2 || $0 == r.last })
        // No line breaks to skip: the pieces meet end to end and cover the text.
        for (a, b) in zip(r, r.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
        #expect(r.first?.lowerBound == 0 && r.last?.upperBound == text.count)
        let chars = Array(text)
        for piece in r.dropLast() { #expect(chars[piece.upperBound - 2] == "." && chars[piece.upperBound - 1] == " ") }
        #expect(TextPieces.strings(text).joined() == text)
    }

    @Test func codeIsCutAtLineBreaksAtMostSixtyLinesAPiece() {
        let text = (1...2000).map { "shard \($0): errors \($0 % 9), slowest \($0 * 7) ms" }.joined(separator: "\n")
        let r = TextPieces.ranges(text, code: true)
        let chars = Array(text)
        for (a, b) in zip(r, r.dropFirst()) {
            // The break between two pieces belongs to neither: the next piece starts on a new line.
            #expect(chars[a.upperBound] == "\n" && b.lowerBound == a.upperBound + 1)
        }
        for piece in r {
            #expect(piece.count <= TextPieces.limit)
            #expect(chars[piece].filter { $0 == "\n" }.count < TextPieces.maxLines)
        }
        #expect(TextPieces.strings(text, code: true).joined(separator: "\n") == text)
    }

    @Test func manyShortLinesMakeShortPieces() {
        let text = String(repeating: "{\n}\n", count: 400)
        #expect(text.utf8.count < TextPieces.limit)
        #expect(TextPieces.isLong(text))
        let pieces = TextPieces.strings(text, code: true)
        #expect(pieces.count > 10)
        #expect(pieces.allSatisfy { $0.filter { $0 == "\n" }.count < TextPieces.maxLines })
    }

    @Test func aSingleHugeLineIsCutInsideItself() {
        let text = String(repeating: "{\"id\":42,\"ok\":true},", count: 2_500)    // 50 KB of minified JSON, one line
        let r = TextPieces.ranges(text, code: true)
        #expect(r.count == 25)
        #expect(r.allSatisfy { $0.count == TextPieces.limit })
        #expect(TextPieces.strings(text, code: true).joined() == text)
    }

    @Test func anUnbrokenTokenIsCutOnlyBetweenWholeCharacters() {
        let family = "👨‍👩‍👧‍👦"     // one character of seven scalars
        let text = String(repeating: "a" + family, count: 2_500)
        let pieces = TextPieces.strings(text)
        #expect(pieces.count == 3)
        #expect(pieces.joined() == text)
        #expect(pieces.map { $0.filter { $0 == Character(family) }.count }.reduce(0, +) == 2_500)
        #expect(pieces.allSatisfy { $0.unicodeScalars.count % 8 == 0 })
    }

    @Test func textAddedAtTheEndChangesOnlyTheLastPiece() {
        var text = ""
        var before: [Range<Int>] = []
        for k in 1...400 {
            text += "Checking shard \(k) for errors and slow requests now. "
            let now = TextPieces.ranges(text)
            let kept = max(0, before.count - 1)
            #expect(Array(now.prefix(kept)) == Array(before.prefix(kept)))
            before = now
        }
        #expect(before.count > 5)
    }

    @Test func styledPiecesKeepTheirStyling() {
        var a = AttributedString()
        for k in 0..<300 {
            var bold = AttributedString("Shard \(k)")
            bold.inlinePresentationIntent = .stronglyEmphasized
            a += bold
            a += AttributedString(" looked healthy today. ")
        }
        let pieces = TextPieces.attributed(a)
        #expect(pieces.count > 3)
        var joined = AttributedString()
        for p in pieces { joined += p }
        #expect(joined == a)
    }

    @Test func aFoldShowsItsStartAndCountsTheRest() {
        let text = String(repeating: "word ", count: 10_000)
        let c = TextPieces.capped(text)
        #expect(c.text.count <= TextPieces.foldCap)
        #expect(text.hasPrefix(c.text))
        #expect(c.text.utf8.count + c.more == text.utf8.count)
        #expect(TextPieces.capped("short").more == 0)
    }

    @Test func aTableShowsAHugeCellCutAndAWideTablePartly() {
        #expect(MarkdownTableMetrics.shownCell("ok") == "ok")
        let cell = String(repeating: "f", count: 50_000)
        #expect(MarkdownTableMetrics.shownCell(cell).count == TextPieces.limit + 1)
        let wide = MarkdownTable(header: (0..<40).map { "c\($0)" }, alignments: Array(repeating: .leading, count: 40),
                                 rows: (0..<100).map { r in (0..<40).map { "\(r)-\($0)" } })
        let shown = wide.prefix(columns: MarkdownTableMetrics.bubbleColumns, rows: MarkdownTableMetrics.bubbleRows)
        #expect(shown.header.count == 16 && shown.rows.count == 60 && shown.rows.allSatisfy { $0.count == 16 })
        #expect(shown.rows[3][5] == "3-5")
        let small = MarkdownTable(header: ["a", "b"], alignments: [.leading, .leading], rows: [["1", "2"]])
        #expect(small.prefix(columns: 16, rows: 60) == small)
    }
}
