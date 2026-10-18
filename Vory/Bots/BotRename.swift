import Foundation
import VoryCore

/// Renaming a bot for real (#315, part two): its folder on the gateway, through
/// `PATCH /api/profiles/{name}`, which stops the bot and starts it again under the new name
/// (anything it was running stops; its chats, memory and settings move with it). Offered only
/// where the gateway has that route, and never for the default bot, whose folder is fixed: the
/// name and title above it (`BotNames`) are the way to call it something else.
///
/// Hermes renames the folder and what it keys on it (sessions, heartbeats, delivery, the active
/// profile, the wrapper, Honcho hosts, the Companion's files inside it). What it leaves alone
/// is named in the warning: Board tasks keep the old assignee, other bots' instructions are
/// not rewritten, cron jobs and scripts that name the profile still say the old one.
enum BotRename {
    /// Profile names are folder names on the gateway: lowercase letters, digits, dash and
    /// underscore. The same cleaning as New Bot.
    static func cleaned(_ name: String) -> String {
        name.lowercased().map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
            .reduce(into: "") { if !($0.last == "-" && $1 == "-") { $0.append($1) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Names the gateway refuses outright: its own command, the default alias, system binaries.
    static let reserved: Set<String> = ["hermes", "default", "test", "tmp", "root", "sudo"]

    enum Refusal: Equatable {
        case empty, same, reserved, taken, isDefault, connectedThroughIt, offline
        var message: String {
            switch self {
            case .empty: "Type a name."
            case .same: "That is the bot's name already."
            case .reserved: "That name is reserved on the gateway."
            case .taken: "A bot with this name already exists."
            case .isDefault: "The default bot's folder cannot be renamed."
            case .connectedThroughIt: "Vory is connected through this bot's own gateway, which the rename stops. Connect through another bot first."
            case .offline: "The gateway is not reachable."
            }
        }
    }

    /// Why `new` cannot be this bot's name, or nil when it can. `connected` is the gateway's
    /// active profile (the one Vory's address belongs to): its own process is stopped by the
    /// rename and not started again, so that one is refused.
    static func refusal(renaming old: String, to new: String, profiles: [ProfileInfo], connected: String?) -> Refusal? {
        let n = cleaned(new)
        if profiles.first(where: { $0.name == old })?.isDefault == true || old == "default" { return .isDefault }
        if n.isEmpty { return .empty }
        if n == old { return .same }
        if reserved.contains(n) { return .reserved }
        if profiles.contains(where: { $0.name == n }) { return .taken }
        if let connected, connected == old, connected != "default" { return .connectedThroughIt }
        return nil
    }

    /// Whether the gateway has the rename route: its `Allow` for the profile path names PATCH.
    static func supported(on api: HermesAPI) async -> Bool {
        ((try? await api.allowedMethods("/api/profiles/_probe")) ?? []).contains("PATCH")
    }

    /// Everything Vory keeps under the old folder name moves to the new one: the bot's own name
    /// and title, its colour, its look and photo, and the default bot when it was this one.
    /// The old keys go, so the cloud's entries for the old name are retired on the next pass.
    @MainActor static func moveLocalState(from old: String, to new: String, defaults: UserDefaults = .standard) {
        var names = BotNames.stored(defaults)
        if let e = names[old] { names[new] = e; names[old] = nil; BotNames.save(names, defaults) }
        // The colour follows even when it was never chosen: the palette's pick is by name, and
        // a renamed bot should not change colour.
        var colors = BotColors.stored()
        colors[new] = colors[old] ?? BotColors.defaultHex(for: old)
        colors[old] = nil
        BotColors.save(colors)
        var avatars = BotAvatarStore.stored()
        if let a = avatars[old] { avatars[new] = a; avatars[old] = nil; BotAvatarStore.save(avatars) }
        BotAvatarStore.movePhoto(from: old, to: new)
        if defaults.string(forKey: GatewayRuntime.defaultProfileKey) == old { defaults.set(new, forKey: GatewayRuntime.defaultProfileKey) }
    }

    /// The rename itself: the gateway's call, then Vory's own keys, the bot list and the
    /// connection. Returns the bot's new folder name as the gateway spelled it.
    @MainActor static func rename(_ old: String, to new: String, on rt: GatewayRuntime) async throws -> String {
        let n = cleaned(new)
        let r: JSONValue = try await rt.api.send("PATCH", "/api/profiles/\(old)", json: .object(["new_name": .string(n)]))
        let final = r["name"]?.stringValue ?? n
        moveLocalState(from: old, to: final)
        if rt.selectedProfile == old { rt.selectedProfile = final }
        // Its open chats were under the old name; they come back from the reloaded list.
        rt.forgetChats(of: old)
        // The bot came up again under its new name; the socket may have gone with the old one.
        await rt.loadProfiles()
        await rt.reconnectNow()
        NotificationCenter.default.post(name: .hermesBotRenamed, object: nil, userInfo: ["old": old, "new": final])
        NotificationCenter.default.post(name: .hermesSessionsChanged, object: nil)
        return final
    }
}
