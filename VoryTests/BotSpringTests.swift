import Foundation
import Testing
@testable import Vory

/// The spring every bot motion channel runs on (1.5, #304).
@Suite struct BotSpringTests {
    @Test func theSamePathAtAnyFrameRate() {
        func run(hz: Int) -> [Double] {
            var s = BotSpring(0, omega: 6.4, zeta: 0.9)
            var out: [Double] = []
            // Ten samples a second: every hz/10 frames lands on a tenth exactly.
            for frame in 1...hz {
                s.step(toward: 1, dt: 1 / Double(hz))
                if frame % (hz / 10) == 0 { out.append(s.x) }
            }
            return out
        }
        // Sampled every tenth of a second, the three rates agree to a thousandth.
        let a = run(hz: 30), b = run(hz: 60), c = run(hz: 120)
        #expect(a.count == b.count && b.count == c.count)
        for i in a.indices { #expect(abs(a[i] - b[i]) < 0.001 && abs(b[i] - c[i]) < 0.001, "sample \(i): \(a[i]) \(b[i]) \(c[i])") }
    }

    @Test func itSettlesOnTheTargetWithoutALargeOvershoot() {
        var s = BotSpring(0, omega: 6.4, zeta: 0.9)
        var peak = 0.0
        for _ in 0..<180 { s.step(toward: 1, dt: 1 / 60); peak = max(peak, s.x) }
        #expect(s.isSettled(at: 1, tolerance: 0.002))
        #expect(peak < 1.01)
    }

    @Test func aChangeSettlesInAboutAThirdOfASecondAtTheReelsTempo() {
        // Decision 2: the reel's springs; a shape change is 95 % there within 0.35 s.
        var s = BotSpring(0, omega: 14, zeta: 0.9)
        for _ in 0..<21 { s.step(toward: 1, dt: 1 / 60) }
        #expect(s.x > 0.95, "\(s.x)")
    }

    @Test func aLongGapSnapsInsteadOfPlayingSlowMotion() {
        var s = BotSpring(0, omega: 6.4, zeta: 0.9)
        s.step(toward: 1, dt: 0.3)
        #expect(s.x == 1 && s.v == 0)
    }

    @Test func retargetingMidFlightKeepsItsVelocity() {
        var s = BotSpring(0, omega: 6.4, zeta: 0.9)
        for _ in 0..<6 { s.step(toward: 1, dt: 1 / 60) }
        let xBefore = s.x, vBefore = s.v
        #expect(vBefore > 0)
        s.step(toward: 0, dt: 1 / 60)
        // One frame later it is still moving up (no jump back), just slower.
        #expect(s.x > xBefore && s.v < vBefore)
    }
}
