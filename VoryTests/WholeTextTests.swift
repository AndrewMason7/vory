import Foundation
import Testing
@testable import Vory

/// #421: a whole text shown in a sheet (a tool's full call, a reasoning or a reply shown whole) stays in one text view
/// when it can, so a reply selects across its paragraphs, and is drawn as bounded pieces when one text view would lay
/// out a block past the graphics card's largest texture or a tree too big to read.
@Suite struct WholeTextTests {
    let standard = TextPieces.Limits.standard
    let largest = TextPieces.Limits.largestAccessibility

    @Test func anOrdinaryReplyKeepsTheTextView() {
        let paragraph = String(repeating: "The export retried a shard and the second pass matched. ", count: 30)   // ~1,700 characters
        let reply = Array(repeating: paragraph, count: 20).joined(separator: "\n\n")                                // ~34 KB
        #expect(SelectableText.fitsOneView(reply, standard))
        #expect(SelectableText.fitsOneView("", standard))
        #expect(SelectableText.fitsOneView(String(repeating: "x", count: 4_000), standard))
    }

    @Test func aLongLineOrAHugeWholeIsPieces() {
        #expect(!SelectableText.fitsOneView(String(repeating: "x", count: 4_001), standard))
        let oneLine = "[" + Array(repeating: #"{"id":1,"status":"ok"}"#, count: 400).joined(separator: ",") + "]"   // ~9 KB, no break
        #expect(!SelectableText.fitsOneView(oneLine, standard))
        let manyLines = Array(repeating: "00001  shard-001 INFO request 7919 served in 4 ms", count: 3_000).joined(separator: "\n")   // ~150 KB
        #expect(!SelectableText.fitsOneView(manyLines, standard))
        // The largest text size holds less in a paragraph.
        let paragraph = String(repeating: "word ", count: 200)   // 1,000 characters
        #expect(SelectableText.fitsOneView(paragraph, standard))
        #expect(!SelectableText.fitsOneView(paragraph, largest))
    }

    @Test func thePiecesAreTheWholeTextAndNoneIsTooBig() {
        let oneLine = "[" + (0..<20_000).map { #"{"id":\#($0),"shard":"shard-\#($0 % 97)","status":"ok"}"# }.joined(separator: ",") + "]"
        let lines = (0..<20_000).map { String(format: "%05d  shard-%03d INFO request %d served in %d ms", $0, $0 % 97, $0 * 7919 % 10007, $0 % 90 + 3) }.joined(separator: "\n")
        for (name, text) in [("one line", oneLine), ("many lines", lines)] {
            let pieces = TextPieces.strings(text, code: true, standard)
            #expect(pieces.allSatisfy { $0.count <= standard.chars }, "\(name): a piece over the limit")
            #expect(pieces.allSatisfy { $0.reduce(0) { $1.isNewline ? $0 + 1 : $0 } < standard.lines }, "\(name): a piece over the lines")
            // Nothing is lost: the pieces are the text, less the line breaks a cut was made at.
            let cutAtBreaks = text.count - pieces.reduce(0) { $0 + $1.count }
            #expect(cutAtBreaks >= 0 && cutAtBreaks < pieces.count, "\(name): characters lost or doubled")
            #expect(pieces.joined().filter { !$0.isNewline } == text.filter { !$0.isNewline }, "\(name): the pieces are not the text")
        }
    }
}
