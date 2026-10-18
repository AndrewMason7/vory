#if os(iOS)
import CoreGraphics
import Testing
@testable import Vory

/// The lean that follows the phone (Settings › Bots › Tilt): it eases back to the hold and lands
/// on zero there, so the Bots page's faces return to pictures. It stalled a little short of zero
/// (each step below the write threshold), which left the faces live after every lean.
struct BotTiltTests {
    @Test func aLeanLandsOnZeroAtTheHold() {
        var t = CGPoint(x: 0.6, y: -0.25)
        var writes = 0
        for _ in 0..<120 {
            if let next = BotMotionSource.step(from: t, toward: 0, 0) { t = next; writes += 1 }
        }
        #expect(t == .zero, "the lean stalled at \(t) on its way back to the hold")
        #expect(writes < 40, "the way back wrote \(writes) times")
        #expect(BotMotionSource.step(from: .zero, toward: 0, 0) == nil, "the hold wrote")
    }

    @Test func aStillLeanWritesNothing() {
        // Held off the hold: once it has arrived, nothing more is written.
        var t = CGPoint.zero
        for _ in 0..<200 { if let next = BotMotionSource.step(from: t, toward: 0.5, 0.2) { t = next } }
        #expect(BotMotionSource.step(from: t, toward: 0.5, 0.2) == nil, "a held lean kept writing")
        #expect(abs(t.x - 0.5) < 0.04 && abs(t.y - 0.2) < 0.04, "the lean did not arrive: \(t)")
    }
}
#endif
