import Foundation
import Testing
@testable import VoryCore

/// #421: a tool card asks for the pictures in its output every time it is drawn open; the scan was a regular expression
/// over the whole output, and an output past the scan cache's size was never remembered, so a 10 MB one held the main
/// thread for seconds on every open, close and redraw of its card.
@Suite struct ToolOutputScanTests {
    static func lines(_ bytes: Int) -> String {
        var out: [String] = [], total = 0, k = 0
        while total < bytes {
            let l = String(format: "%05d  shard-%03d INFO request %d served in %d ms", k, k % 97, k * 7919 % 10007, k % 90 + 3)
            out.append(l); total += l.utf8.count + 1; k += 1
        }
        return out.joined(separator: "\n")
    }
    static func blob(_ bytes: Int) -> String {
        var out: [String] = [], total = 2, k = 0
        while total < bytes {
            let r = #"{"id":\#(k),"shard":"shard-\#(k % 97)","status":"ok","ms":\#(k % 90 + 3)}"#
            out.append(r); total += r.utf8.count + 1; k += 1
        }
        return "[" + out.joined(separator: ",") + "]"
    }

    @Test func aBigOutputIsLookedThroughAtItsEndsOnlyAndRemembered() {
        for (name, text) in [("2 MB lines", Self.lines(2_000_000)), ("2 MB one line", Self.blob(2_000_000)),
                             ("10 MB lines", Self.lines(10_000_000)), ("10 MB one line", Self.blob(10_000_000))] {
            var t0 = Date()
            let whole = MediaScan.scanImagePaths(inToolOutput: text)
            let wholeMs = Date().timeIntervalSince(t0) * 1000
            t0 = Date()
            let first = MediaScan.imagePaths(inToolOutput: text)
            let firstMs = Date().timeIntervalSince(t0) * 1000
            t0 = Date()
            let again = MediaScan.imagePaths(inToolOutput: text)
            let againMs = Date().timeIntervalSince(t0) * 1000
            print(String(format: "C421 image scan %@: whole %.0f ms, ends %.0f ms, again %.1f ms", name, wholeMs, firstMs, againMs))
            #expect(whole.isEmpty && first.isEmpty && again.isEmpty)
            #expect(MediaScan.scanned(text).utf8.count <= (256 << 10) + 1, "\(name): more than the ends looked through")
            #expect(againMs < 50, "\(name): not remembered")
        }
    }

    @Test func aPictureNearTheStartOrTheEndIsFound() {
        let big = Self.lines(3_000_000)
        let start = "Saved /tmp/shots/first.png\n" + big
        let end = big + "\nSaved /tmp/shots/last.png"
        let middle = String(big.prefix(1_500_000)) + "\nSaved /tmp/shots/middle.png\n" + String(big.suffix(1_500_000))
        #expect(MediaScan.imagePaths(inToolOutput: start).map { $0.id } == ["/tmp/shots/first.png"])
        #expect(MediaScan.imagePaths(inToolOutput: end).map { $0.id } == ["/tmp/shots/last.png"])
        // Deep in the middle of a long log it is not looked for: the price of a card that opens at once.
        #expect(MediaScan.imagePaths(inToolOutput: middle).isEmpty)
        // A short output is looked through whole, as before.
        #expect(MediaScan.imagePaths(inToolOutput: "rendered\n" + Self.lines(100_000) + "\nto /tmp/out/chart.webp\nok").map { $0.id } == ["/tmp/out/chart.webp"])
    }
}
