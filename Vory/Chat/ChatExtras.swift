import ImageIO
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import VoryCore

/// Last known session list per gateway + profile, so the Chats tab draws instantly on launch
/// and refreshes behind it. Small JSON in UserDefaults; Settings › Appearance can clear it.
enum SessionCache {
    static let prefix = "sessions.cache."

    static func key(connection: UUID, profile: String?) -> String { prefix + connection.uuidString + "." + (profile ?? "-") }

    static func load(connection: UUID, profile: String?) -> [StoredSession] {
        guard let data = UserDefaults.standard.data(forKey: key(connection: connection, profile: profile)) else { return [] }
        return (try? JSONDecoder().decode([StoredSession].self, from: data)) ?? []
    }

    /// Any cached list for this gateway, whichever bot it was for: shown at a cold launch when
    /// the exact one is missing, so the page is never empty while the first load runs.
    static func loadAny(connection: UUID) -> [StoredSession] {
        let head = prefix + connection.uuidString + "."
        var best: [StoredSession] = []
        for (k, v) in UserDefaults.standard.dictionaryRepresentation() where k.hasPrefix(head) {
            if let data = v as? Data, let list = try? JSONDecoder().decode([StoredSession].self, from: data), list.count > best.count { best = list }
        }
        return best
    }

    static func save(_ sessions: [StoredSession], connection: UUID, profile: String?) {
        if let data = try? JSONEncoder().encode(sessions) { UserDefaults.standard.set(data, forKey: key(connection: connection, profile: profile)) }
    }

    static func clearAll() {
        let d = UserDefaults.standard
        for k in d.dictionaryRepresentation().keys where k.hasPrefix(prefix) { d.removeObject(forKey: k) }
    }

    static var approximateBytes: Int {
        let d = UserDefaults.standard
        return d.dictionaryRepresentation().filter { $0.key.hasPrefix(prefix) }.values.compactMap { ($0 as? Data)?.count }.reduce(0, +)
    }
}

/// A bot avatar rendered to a UIImage, for places SwiftUI cannot draw a view — menu item icons.
enum BotAvatarImage {
    @MainActor private static let cache = NSCache<NSString, UIImage>()
    /// `make`, memoised by look: the thread draws one of these beside every reply, and a live
    /// bot view per row (glass, timeline) is what made a long thread stutter while scrolling.
    /// `closed`: the same face mid-blink, for a list row's blink by picture swap.
    @MainActor static func cached(profile: String, size: CGFloat = 28, scheme: ColorScheme = .light, closed: Bool = false) -> UIImage {
        let key = "\(profile)|\(size)|\(scheme == .dark ? "d" : "l")|\(BotAvatarStore.choice(for: profile).raw)|\(BotColors.hex(for: profile))|\(BotAvatarStore.glassAll)|\(closed ? "shut" : "open")" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        BotFace.stillBlink = closed ? 1 : 0
        let img = make(profile: profile, size: size, scheme: scheme)
        BotFace.stillBlink = 0
        cache.setObject(img, forKey: key)
        return img
    }

    /// A look that is not a bot's own (the Look tab's shape and eye tiles, the Companion card's
    /// bot): memoised by its spec. `closed`: mid-blink, for the blink by picture swap.
    @MainActor static func cached(spec: BotLookSpec, size: CGFloat, scheme: ColorScheme, closed: Bool = false) -> UIImage {
        let key = "spec|\(spec.shape)|\(spec.eyes)|\(spec.hex)|\(spec.finish)|\(size)|\(scheme == .dark ? "d" : "l")|\(closed ? "shut" : "open")" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        BotFace.stillBlink = closed ? 1 : 0
        let r = ImageRenderer(content: BotFaceView(spec: spec, size: size, active: false, drawn: true).environment(\.colorScheme, scheme))
        r.scale = 3
        r.isOpaque = false
        let img = (r.uiImage ?? UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in }).withRenderingMode(.alwaysOriginal)
        BotFace.stillBlink = 0
        cache.setObject(img, forKey: key)
        return img
    }

    @MainActor static func make(profile: String, size: CGFloat = 28, scheme: ColorScheme = .light) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        if BotAvatarStore.choice(for: profile) == .photo, let photo = BotAvatarStore.photo(for: profile) {
            return renderer.image { ctx in
                ctx.cgContext.addEllipse(in: CGRect(x: 0, y: 0, width: size, height: size)); ctx.cgContext.clip()
                photo.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
            }.withRenderingMode(.alwaysOriginal)
        }
        // The studio bot itself, painted (glass cannot render offscreen), at 3x for the menu.
        let spec = BotAvatarStore.choice(for: profile).spec(hex: BotColors.hex(for: profile))
        let r = ImageRenderer(content: BotFaceView(spec: spec, size: size, active: false, drawn: true).environment(\.colorScheme, scheme))
        r.scale = 3
        r.isOpaque = false
        return (r.uiImage ?? renderer.image { _ in }).withRenderingMode(.alwaysOriginal)
    }
}

/// Floating glass "↓" that appears once the transcript is scrolled away from the bottom.
struct JumpToBottomButton: View {
    var visible: Bool
    var action: () -> Void
    var body: some View {
        if visible {
            Button(action: action) {
                Image(systemName: "chevron.down").font(.body.weight(.semibold))
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Jump to latest")
            .transition(.scale.combined(with: .opacity))
        }
    }
}

/// The whole message as plain, selectable text — for copying just a part of it.
/// Text you can select by range, with the handles and the Copy/Look Up menu UIKit gives: SwiftUI's
/// own selectable text offers Copy and Share for the whole thing and nothing in between (a
/// tester: "the select text window doesn't work").
#if os(macOS)
/// On the Mac an AppKit text view too, as on the iPhone: SwiftUI's selectable `Text` drew the whole text as one
/// picture, and a long output past the graphics card's largest texture was an empty box (#361). The text view lays
/// out and draws only what is on screen, and selects by range as before.
struct SelectableText: View {
    var text: String
    var monospaced = false
    /// What VoiceOver calls the text (the sheet's title).
    var label = "Text"
    var body: some View {
        SelectableTextView(text: text, monospaced: monospaced, label: label)
            .frame(minWidth: 420, minHeight: 320)
    }
}

private struct SelectableTextView: NSViewRepresentable {
    var text: String
    var monospaced: Bool
    var label: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        if let v = scroll.documentView as? NSTextView {
            v.isEditable = false
            v.isSelectable = true
            v.drawsBackground = false
            v.textContainerInset = NSSize(width: 12, height: 12)
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let v = scroll.documentView as? NSTextView else { return }
        if v.string != text { v.string = text }
        // Only when it changes: setting the font lays the whole text out again (100 KB on a Show all sheet).
        let font: NSFont = monospaced ? .monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
                                      : .preferredFont(forTextStyle: .body)
        if v.font != font { v.font = font }
        if v.textColor != .labelColor { v.textColor = .labelColor }
        if v.accessibilityLabel() != label { v.setAccessibilityLabel(label) }
    }
}
#else
struct SelectableText: UIViewRepresentable {
    var text: String
    var monospaced = false
    /// What VoiceOver calls the text (the sheet's title).
    var label = "Text"
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.isScrollEnabled = true
        v.alwaysBounceVertical = true
        v.backgroundColor = .clear
        v.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 24, right: 12)
        v.dataDetectorTypes = [.link]
        v.adjustsFontForContentSizeCategory = true
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) {
        // Only what changed: setting the font lays the whole text out again (100 KB on a Show all sheet).
        let font = monospaced ? UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular) : UIFont.preferredFont(forTextStyle: .body)
        if v.font != font { v.font = font }
        if v.textColor != .label { v.textColor = .label }
        if v.accessibilityLabel != label { v.accessibilityLabel = label }
        if v.text != text { v.text = text }
    }
}
#endif

struct SelectTextSheet: View {
    /// What the text is: "Select Text" for a message's own, the bot's name and "Reasoning" for a reasoning shown whole.
    var title = "Select Text"
    var text: String
    var monospaced = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SelectableText(text: text, monospaced: monospaced, label: title)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Done, a swipe down on the phone, Escape on the Mac.
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .primaryAction) { Button { UIPasteboard.general.string = text } label: { Label("Copy all", systemImage: "doc.on.doc") } }
            }
        }
    }
}

/// Small decoded previews of attachment images, by file and size, so a row never holds the
/// full-resolution bitmap.
/// `scale` is the display's scale where the picture will show (`\.displayScale` in the view
/// that asks), not the main screen's: an external display or the Duo's other display can differ.
enum AttachmentThumbs {
    @MainActor private static let cache = NSCache<NSString, UIImage>()
    private static func key(_ url: URL, _ side: CGFloat, _ scale: CGFloat) -> NSString { "\(url.path)|\(Int(side))|\(scale)" as NSString }

    @MainActor static func image(at url: URL, side: CGFloat, scale: CGFloat) -> UIImage? {
        let key = key(url, side, scale)
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = decode(at: url, pixels: Int(side * scale)) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// The same, decoded off the main thread: a row's thumbnails and the viewer's picture are
    /// made where a scroll does not wait for them.
    @MainActor static func imageAsync(at url: URL, side: CGFloat, scale: CGFloat) async -> UIImage? {
        let key = key(url, side, scale)
        if let hit = cache.object(forKey: key) { return hit }
        let pixels = Int(side * scale)
        let box = await Task.detached(priority: .userInitiated) { Box(decode(at: url, pixels: pixels)) }.value
        if let image = box.image { cache.setObject(image, forKey: key) }
        return box.image
    }

    /// The file downsampled to at most `pixels` a side, never the whole bitmap.
    nonisolated static func decode(at url: URL, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCache: false]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private final class Box: @unchecked Sendable { let image: UIImage?; init(_ image: UIImage?) { self.image = image } }
}
