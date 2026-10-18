import CoreMotion
import SwiftUI
import VoryCore

/// Feeds `BotAmbient.shared.tilt` from the device's attitude while the app is in front and the
/// Settings › Bots switch is on. The resting hold (the attitude when the source starts, then
/// slowly re-centred) counts as level, so a phone held at any angle shows upright bots.
@MainActor
final class BotMotionSource {
    static let shared = BotMotionSource()
    static let enabledKey = "bots.motion"
    /// The gyroscope lean is its own switch (beta, off by default): it is easy to find twitchy.
    static let tiltKey = "bots.tilt"
    /// How much the bots move: lively (every turn and lean), calm (half of it), still (the
    /// poses and blinks only). Settings › Bots.
    static let styleKey = "bots.motionStyle"
    static var styleScale: Double {
        switch UserDefaults.standard.string(forKey: styleKey) ?? "lively" {
        case "calm": return 0.5
        case "still": return 0
        default: return 1
        }
    }

    private let manager = CMMotionManager()
    private var restRoll = 0.0, restPitch = 0.0
    private var haveRest = false

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey); apply() }
    }
    var tiltEnabled: Bool { UserDefaults.standard.bool(forKey: Self.tiltKey) }

    /// Starts or stops with the setting and the scene phase.
    func apply(active: Bool = true) {
        BotAmbient.shared.enabled = enabled
        BotFace.motionScale = Self.styleScale
        guard enabled, tiltEnabled, active, manager.isDeviceMotionAvailable, !UIAccessibility.isReduceMotionEnabled else {
            manager.stopDeviceMotionUpdates()
            BotAmbient.shared.tilt = .zero
            BotAmbient.shared.tiltLive = false
            haveRest = false
            return
        }
        BotAmbient.shared.tiltLive = true
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let a = motion?.attitude else { return }
            if !haveRest { restRoll = a.roll; restPitch = a.pitch; haveRest = true }
            // The rest drifts toward the current hold, so a new posture becomes the new level.
            restRoll += (a.roll - restRoll) * 0.01
            restPitch += (a.pitch - restPitch) * 0.01
            // A dead zone of a few degrees around the resting hold, then a gentle ramp: ±1 is
            // reached at about 40° instead of 25°, and the value is smoothed harder.
            func shaped(_ v: Double) -> Double {
                let dead = 0.09, full = 0.7
                let m = max(0, abs(v) - dead) / (full - dead)
                return max(-1, min(1, m)) * (v < 0 ? -1 : 1)
            }
            let x = shaped(a.roll - restRoll), y = shaped(a.pitch - restPitch)
            if let next = Self.step(from: BotAmbient.shared.tilt, toward: x, y) { BotAmbient.shared.tilt = next }
        }
    }

    /// One step of the lean from `t` toward the device's (`x`, `y`): the value to write, or nil
    /// when nothing worth drawing changed. Back at the hold it lands on zero, so the faces that
    /// follow it rest as pictures; a change too small to see is not written (every live face
    /// reads the tilt, and the smoothing never quite arrived, which redrew them 30 times a second
    /// at rest). It lands from within 0.04: below about 0.033 a step moves less than a write's
    /// 0.004, so landing any closer in left it there, the faces live, after every lean.
    nonisolated static func step(from t: CGPoint, toward x: Double, _ y: Double) -> CGPoint? {
        var next = CGPoint(x: t.x + (x - t.x) * 0.12, y: t.y + (y - t.y) * 0.12)
        if x == 0, y == 0, abs(next.x) < 0.04, abs(next.y) < 0.04 { next = .zero }
        guard next != t, next == .zero || abs(next.x - t.x) >= 0.004 || abs(next.y - t.y) >= 0.004 else { return nil }
        return next
    }
}
