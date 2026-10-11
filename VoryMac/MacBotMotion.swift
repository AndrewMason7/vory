import Foundation
import SwiftUI
import VoryCore

/// Settings › Bots › Motion on the Mac (1.5, the bot-motion brief's decision E): the same two
/// keys as the iPhone (`bots.motion`, `bots.motionStyle`), applied to the engine the same way,
/// without the phone's gyroscope part (`BotMotionSource` is the iPhone's; it needs CoreMotion
/// and the tilt switch, neither of which the Mac has).
@MainActor
enum MacBotMotion {
    static let enabledKey = "bots.motion"
    static let styleKey = "bots.motionStyle"

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Lively 1, calm 0.5, still 0: how much of the motion the style keeps.
    static func scale(for style: String?) -> Double {
        switch style ?? "lively" {
        case "calm": return 0.5
        case "still": return 0
        default: return 1
        }
    }

    /// Hands the setting to the engine: at launch, and whenever Settings changes it.
    static func apply(defaults: UserDefaults = .standard) {
        BotAmbient.shared.enabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        BotFace.motionScale = scale(for: defaults.string(forKey: styleKey))
    }
}
