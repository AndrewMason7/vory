#if os(iOS)
import UIKit
import VoryCore

/// The runtime's "away" (`GatewayRuntime.isAway`) for a launch in the background (#371).
///
/// Away comes from the scene's phase, and a launch in the background (the daily backup task, a
/// push-started Live Activity, a watch request) has no scene: its runtime started out "in front",
/// and a long turn's events, list refreshes and redraws ran there in full. It now starts away
/// when the app is in the background. Away holds the chats' views still, so it must never stick:
/// each time the app becomes active it is cleared, whatever a scene's phase did or did not report.
@MainActor enum AwayAtLaunch {
    static func startsAway(_ state: UIApplication.State) -> Bool { state == .background }

    /// Clears `isAway` on the runtime `current()` gives, each time the app becomes active.
    @discardableResult
    static func clearOnActive(center: NotificationCenter = .default, _ current: @escaping @MainActor () -> GatewayRuntime?) -> any NSObjectProtocol {
        // Posted on the main thread, by the system and the tests.
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { current()?.isAway = false }
        }
    }
}
#endif
