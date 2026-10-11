import Foundation
import os

/// Animation intervals for the hitch metrics (1.5, "absolutely smooth"): each named moment a
/// control opens or closes something is an os_signpost animation interval, so Instruments'
/// Animation Hitches and XCTOSSignpostMetric in SmoothnessPerfUITests can score it (hitch
/// time per second, worst hitch). Free when nothing listens; nothing is drawn.
enum Smooth {
    private static let poster = OSSignposter(subsystem: "Vory", category: "Smooth")
    nonisolated(unsafe) private static var open: [String: OSSignpostIntervalState] = [:]
    private static let lock = NSLock()

    /// Marks a short animation: the interval runs for `seconds` from now (the transition's
    /// length plus a little settle), then ends itself.
    static func animate(_ name: StaticString, for seconds: Double = 0.7) {
        let state = poster.beginAnimationInterval(name)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { poster.endInterval(name, state) }
    }

    /// A long interval with an explicit end (a whole turn): `end` with the same name closes it.
    static func begin(_ name: StaticString) {
        let key = "\(name)"
        lock.lock(); defer { lock.unlock() }
        guard open[key] == nil else { return }
        open[key] = poster.beginAnimationInterval(name)
    }

    static func end(_ name: StaticString) {
        let key = "\(name)"
        lock.lock(); let state = open.removeValue(forKey: key); lock.unlock()
        if let state { poster.endInterval(name, state) }
    }
}
