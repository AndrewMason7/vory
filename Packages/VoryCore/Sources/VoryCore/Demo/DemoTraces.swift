import Foundation

/// What builds before 11bd131 left of the demo (#493): the chat list saved the demo's chats under its id, and a later
/// launch read them back, so the list kept their first times and the demo's chats aged ("last week"). Nothing is
/// written for the demo now (`GatewayRuntime.isEphemeral`, and the list's cache never reads or writes it); this takes
/// away what was: every key of the app's defaults that names the demo's id, and its transcript folder. Run at launch
/// and when the demo ends, so a device that ran an older demo is cleaned too. It matches the demo's gateway id only:
/// its chats' ids have the shape of a real Hermes chat's.
public enum DemoTraces {
    /// At launch, unless the demo is already the gateway in use (a test build's `-vory-demo`): nothing is taken from
    /// under a demo that runs. Leaving the demo sweeps in any case (`sweep`).
    @MainActor public static func sweepAtLaunch(store: ConnectionStore, defaults: UserDefaults = .standard,
                                                caches: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) {
        guard store.demo == nil else { return }
        sweep(defaults: defaults, caches: caches)
    }

    public static func sweep(defaults: UserDefaults = .standard,
                             caches: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) {
        let id = GatewayConnection.demoID.uuidString
        for key in defaults.dictionaryRepresentation().keys where key.uppercased().contains(id) {
            defaults.removeObject(forKey: key)
        }
        if let caches {
            try? FileManager.default.removeItem(at: caches.appending(path: "transcripts/\(id)", directoryHint: .isDirectory))
        }
    }
}
