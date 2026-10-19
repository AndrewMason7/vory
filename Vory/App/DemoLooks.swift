import Foundation
import VoryCore

/// The demo's bots' looks and names while the demo runs (#392): each its own body, eyes and colour (`DemoBots`), and
/// the demo's own names, in memory only. Never in the stored looks or names, so never in iCloud, the extensions' mirror
/// or another device, and never those of this person's own bots: the demo's folders ("default" among them) are the
/// usual ones, so a name or look kept for a real bot would otherwise show on the demo's, and an edit in the demo would
/// change the real one. A look, colour or name changed during the demo stays here, and all of it goes when the demo
/// ends. `BotAvatarStore`, `BotColors` and `BotNames` ask here first.
enum DemoLooks {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var avatarMap: [String: String]?
    nonisolated(unsafe) private static var colorMap: [String: String]?
    nonisolated(unsafe) private static var nameMap: [String: [String: String]]?

    static var isOn: Bool { lock.withLock { avatarMap != nil } }
    static func avatar(for profile: String) -> String? { lock.withLock { avatarMap?[profile] } }
    static func color(for profile: String) -> String? { lock.withLock { colorMap?[profile] } }
    /// The demo's own names for a bot (as `BotNames` keeps them: "n" and "t"): each demo bot's name and title from
    /// `DemoBots` (the tour's "Sprout · Research"), then whatever is given in the demo.
    static func names(for profile: String) -> [String: String]? { lock.withLock { nameMap?[profile] } }

    /// The demo's looks on (true) or gone (false), as the gateway in use is the demo or not.
    static func set(on: Bool) {
        lock.withLock {
            if on {
                guard avatarMap == nil else { return }
                avatarMap = Dictionary(uniqueKeysWithValues: DemoBots.all.map { ($0.name, BotAvatarChoice.studio(shape: $0.shape, eyes: $0.eyes).raw) })
                colorMap = Dictionary(uniqueKeysWithValues: DemoBots.all.map { ($0.name, $0.hex) })
                nameMap = Dictionary(uniqueKeysWithValues: DemoBots.all.map { ($0.name, ["n": $0.display, "t": $0.title]) })
            } else {
                avatarMap = nil
                colorMap = nil
                nameMap = nil
            }
        }
    }

    /// Names given to a bot during the demo (nil clears them): kept for the demo only. False when it isn't running.
    static func keep(names entry: [String: String]?, for profile: String) -> Bool {
        lock.withLock {
            guard nameMap != nil else { return false }
            nameMap?[profile] = entry
            return true
        }
    }

    /// A look or colour picked during the demo: kept for the demo only. False when the demo isn't running.
    static func keep(avatar raw: String? = nil, color hex: String? = nil, for profile: String) -> Bool {
        lock.withLock {
            guard avatarMap != nil else { return false }
            if let raw { avatarMap?[profile] = raw }
            if let hex { colorMap?[profile] = hex }
            return true
        }
    }
}
