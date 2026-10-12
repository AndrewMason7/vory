import Foundation
import SwiftUI
import VoryCore

/// Settings › Bots › Style on the Mac (1.5, the bot-motion brief's decision E): the iPhone's
/// style key (`bots.motionStyle`), applied to the engine the same way, without the phone's
/// gyroscope part (`BotMotionSource` is the iPhone's; it needs CoreMotion and the tilt switch,
/// neither of which the Mac has). There is no on/off switch: the engine is always on and the
/// Still style is the quiet choice.
@MainActor
enum MacBotMotion {
    static let styleKey = "bots.motionStyle"

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
        BotFace.motionScale = scale(for: defaults.string(forKey: styleKey))
    }
}
