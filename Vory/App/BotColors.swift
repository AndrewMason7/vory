import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import VoryCore

/// One accent colour per bot (profile). Stored in UserDefaults as `{profile: "#RRGGBB"}` under
/// `botColors`; profiles without a saved colour get a stable pick from the palette so two bots
/// never look alike by accident. Used by the chat title pill, the Bots list, notifications' tint
/// and the Live Activity.
/// The bot look maps (colours, avatar choices) as stored: one JSON string each, decoded once per
/// distinct string and kept. Every face on screen read its map by decoding the string again on
/// each body evaluation, which a list of a hundred rows did on every frame of a fling.
enum BotLookMaps {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: [String: String]] = [:]

    static func map(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty else { return [:] }
        lock.lock(); defer { lock.unlock() }
        if let m = cache[raw] { return m }
        let m = (raw.data(using: .utf8)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        if cache.count > 16 { cache.removeAll() }
        cache[raw] = m
        return m
    }
}

enum BotColors {
    static let storageKey = "botColors"
    /// The watch and the Mac pick from the same list (VoryCore's), so a bot is one colour everywhere.
    static let palette: [String] = BotPalette.hexes

    static func stored() -> [String: String] {
        BotLookMaps.map(UserDefaults.standard.string(forKey: storageKey))
    }

    @MainActor static func save(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map), let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: storageKey)
        }
        BotLooksMirror.mirror()
    }

    static func hex(for profile: String, overrides: [String: String]? = nil) -> String {
        if let h = (overrides ?? stored())[profile], !h.isEmpty { return h }
        return defaultHex(for: profile)
    }

    /// Deterministic palette pick: same name, same colour, on every device.
    static func defaultHex(for profile: String) -> String { BotPalette.defaultHex(for: profile) }

    static func color(for profile: String, overrides: [String: String]? = nil) -> Color {
        Color(hex: hex(for: profile, overrides: overrides)) ?? .accentColor
    }

    @MainActor static func set(_ color: Color, for profile: String) {
        var map = stored()
        map[profile] = color.hexString
        save(map)
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        (NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

/// A bot's avatar: the studio bot (body, eyes, colour) that moves while `active` (the bot is
/// working), or the photo the user chose.
struct BotAvatar: View {
    var profile: String
    var size: CGFloat = 28
    var active: Bool = false
    /// Draw this choice instead of the stored one (the picker's previews).
    var override: BotAvatarChoice? = nil
    /// Thinking squint, finish spin (by profile), tilt-following eyes.
    var mood: BotFaceView.Mood = BotFaceView.Mood()
    /// Paint the glass finish instead of using real glass: for a bot inside another glass
    /// surface (a toolbar button), where glass on glass goes murky.
    var drawn = false
    @AppStorage(BotColors.storageKey) private var raw = ""
    @AppStorage(BotAvatarStore.storageKey) private var avatarsRaw = ""
    @AppStorage(BotAvatarStore.glassAllKey) private var glassAll = false

    private var overrides: [String: String] { BotLookMaps.map(raw) }
    private var effectiveMood: BotFaceView.Mood {
        var m = mood; if m.profile == nil { m.profile = profile }; return m
    }
    private var choice: BotAvatarChoice {
        if let override { return override }
        let m = BotLookMaps.map(avatarsRaw)
        return BotAvatarChoice(raw: BotAvatarStore.effective(m[profile] ?? "", glassAll: glassAll))
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.botsLive) private var pageLive
    /// The live face is mounted around a blink (and for a finish spin or a tap); between those
    /// an idle small face is the cached still, see `restsAsImage`.
    @State private var liveForBlink = false

    /// A small idle face in a list draws as a picture: one cached image per look, no Canvas, no
    /// shadow filter pass on every scrolled frame (the phone's list fling spent its frames on
    /// the rows' faces, 2026-10-11). The live view comes back only for the moments it is needed:
    /// a blink (held while the list scrolls), the finish spin, a tap. Faces that stand for a
    /// working session, bigger faces and the painted twin keep the live view.
    private var restsAsImage: Bool {
        // Any size: the Bots page's cards (78 pt) and the dashboard's faces rest as pictures
        // too; a face that leans with the device keeps its live view.
        guard !active, !drawn, override == nil, !mood.followsTilt, choice != .photo, mood.state == .idle else { return false }
        let now = Date()
        let a = BotAmbient.shared
        if let s = mood.session, let d = a.finishedSessions[s], now.timeIntervalSince(d) < 1.2 { return false }
        if mood.session == nil, let d = a.finished[profile], now.timeIntervalSince(d) < 1.2 { return false }
        if let d = a.tapped[profile], now.timeIntervalSince(d) < 1.2 { return false }
        return !liveForBlink
    }
    /// The same seed the live view blinks on, so the picture and the live face agree on when.
    private var blinkSeed: Int {
        let spec = choice.spec(hex: "")
        let raw = spec.shape.utf8.reduce(0) { $0 + Int($1) } + spec.eyes.utf8.reduce(0) { $0 + Int($1) }
            + (effectiveMood.profile ?? "").utf8.reduce(0) { $0 &* 31 &+ Int($1) }
        return Int(UInt(bitPattern: raw) % 1_000_003)
    }

    var body: some View {
        let hex = BotColors.hex(for: profile, overrides: overrides)
        Group {
            if choice == .photo, let image = BotAvatarStore.photo(for: profile) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else if restsAsImage {
                Image(uiImage: BotAvatarImage.cached(profile: profile, size: size, scheme: colorScheme))
                    .resizable().frame(width: size, height: size)
            } else {
                BotFaceView(spec: choice.spec(hex: hex), size: size, active: active, drawn: drawn, mood: effectiveMood)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        // Between blinks the picture; the live face is mounted a moment before each blink and
        // taken down after it, unless the list is moving (then the blink is skipped).
        .task(id: "\(profile)|\(size)|\(active)|\(mood.state == .idle)") {
            guard !active, !drawn, !mood.followsTilt, mood.state == .idle else { return }
            while !Task.isCancelled {
                let now = Date().timeIntervalSinceReferenceDate
                let next = BotMotionModel.nextBlink(after: now + 0.1, seed: blinkSeed)
                try? await Task.sleep(for: .seconds(max(0.05, next - now - 0.08)))
                if Task.isCancelled { return }
                if BotAmbient.shared.scrolling || !BotAmbient.shared.enabled || !pageLive { continue }
                liveForBlink = true
                try? await Task.sleep(for: .milliseconds(560))
                liveForBlink = false
            }
        }
    }
}

/// Copies the bot colours, avatar choices and photo thumbnails into the shared keychain
/// (`BotLooks`) for the notification extensions.
@MainActor
enum BotLooksMirror {
    static func mirror() {
        // The all-bots glass setting is baked in here, for every profile the gateway knows, so
        // the extensions (which only read this mirror) draw the same bot as the app.
        var avatars = BotAvatarStore.stored()
        var colors = BotColors.stored()
        let profiles = AppModel.shared.runtime?.profiles ?? []
        let known = Set(avatars.keys).union(profiles.map(\.name))
        for profile in known {
            avatars[profile] = BotAvatarStore.effective(avatars[profile] ?? "")
            if colors[profile] == nil { colors[profile] = BotColors.hex(for: profile) }
        }
        var photos: [String: Data] = [:]
        for (profile, choice) in avatars where choice == "photo" {
            if let image = BotAvatarStore.photo(for: profile), let data = thumbnail(image) { photos[profile] = data }
        }
        // The push names a bot by its profile name; a companion that only knows the label still
        // finds it, so every look is stored under both.
        for p in profiles where p.label != p.name && !p.label.isEmpty {
            avatars[p.label] = avatars[p.name]; colors[p.label] = colors[p.name]; photos[p.label] = photos[p.name]
        }
        BotLooks(colors: colors, avatars: avatars, photos: photos).save()
        #if os(iOS)
        WatchSync.shared.refresh()
        #endif
        // A look changed (a photo replaced leaves no setting behind to notice): iCloud gets it.
        CloudSync.shared.looksChanged()
    }

    private static func thumbnail(_ image: UIImage) -> Data? {
        let side: CGFloat = 128
        let scale = side / max(image.size.width, image.size.height)
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let small = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.75)
    }
}
