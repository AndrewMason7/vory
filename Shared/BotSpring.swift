import Foundation

/// A damped spring on one value, stepped by hand: the bot's motion runs on a set of these (the
/// shape blend, each symbol's amount, the eyes, the squash) that pick up from wherever they are
/// when the target changes, so an interrupted change never pops. Semi-implicit Euler in fixed
/// 1/120 s substeps, so 30, 60 and 120 Hz move identically; a long gap (the app coming back)
/// snaps to the target instead of playing a slow-motion frame.
///
/// Not SwiftUI's animations: a Canvas cannot be driven by them, the "from" shape has to be
/// captured mid-flight, and a still frame for tests or a held bot must be deterministic.
public struct BotSpring: Equatable, Sendable {
    /// Position and velocity.
    public var x: Double
    public var v: Double = 0
    /// Angular frequency (how fast) and damping ratio (under 1 overshoots a little).
    public var omega: Double
    public var zeta: Double

    public init(_ x: Double, omega: Double, zeta: Double) {
        self.x = x; self.omega = omega; self.zeta = zeta
    }

    /// The substep every spring uses, whatever the frame rate.
    public static let substep: Double = 1.0 / 120
    /// A gap this long or longer is not a frame: snap.
    public static let snapAfter: Double = 0.25

    /// Advances `dt` seconds toward `target`.
    public mutating func step(toward target: Double, dt: Double) {
        if dt >= Self.snapAfter || dt <= 0 { if dt > 0 { snap(to: target) }; return }
        var left = dt
        while left > 0 {
            let h = min(Self.substep, left)
            // Semi-implicit Euler: the velocity first, then the position with the new velocity.
            let a = -omega * omega * (x - target) - 2 * zeta * omega * v
            v += a * h
            x += v * h
            left -= h
        }
    }

    public mutating func snap(to target: Double) { x = target; v = 0 }

    /// At rest on `target`: within a hair of it and not moving.
    public func isSettled(at target: Double, tolerance: Double = 0.001) -> Bool {
        abs(x - target) < tolerance && abs(v) < tolerance
    }
}
