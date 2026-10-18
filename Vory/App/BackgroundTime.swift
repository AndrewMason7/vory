#if os(iOS)
import Foundation

/// Background time for a stretch of async work started while the app is out of sight (a
/// notification action, a push-started Live Activity, Siri, a watch request). Ended when the
/// work ends or when the system says the time is up, whichever comes first.
///
/// The time is held by a block on a queue of its own and given back from there when the
/// system says the time is up, as `AwayWatch` holds it for a running turn. With
/// `beginBackgroundTask` that call came on the main thread, and a main thread busy with a long
/// turn's events could not answer it in the seconds allowed: the system ended the app for the
/// time left held (#371, "crashed in the background" on 1.4 (10)). The work here waited on
/// the gateway, which could wait for good on a socket that had died quietly (see
/// `GatewaySocket`), so the time did run out. Ending twice is harmless.
final class BackgroundTime: Sendable {
    /// How the time is asked for: the system's expiring activity, or a stand-in in the tests.
    typealias Start = @Sendable (String, @escaping @Sendable (_ expired: Bool) -> Void) -> Void
    static let system: Start = { ProcessInfo.processInfo.performExpiringActivity(withReason: $0, using: $1) }

    private let release = DispatchSemaphore(value: 0)

    /// `expired` runs when the system says the time is up, on the activity's queue (never the
    /// main thread) and before the time is given back.
    init(_ name: String, start: Start = BackgroundTime.system, expired: (@Sendable () -> Void)? = nil) {
        let release = release
        start(name) { isExpired in
            if isExpired {
                expired?()
                release.signal()
            } else {
                _ = release.wait(timeout: .now() + 600)
            }
        }
    }

    deinit { release.signal() }

    func end() { release.signal() }
}
#endif
