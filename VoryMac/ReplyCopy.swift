import SwiftUI
import VoryCore

extension TranscriptMedia {
    /// What Copy puts on the pasteboard for a reply (#255): the markdown its bubble shows, with
    /// the pictures' MEDIA: lines and gateway paths left out as the bubble leaves them out, trimmed.
    static func copyText(_ text: String) -> String {
        images(in: text).isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : MediaScan.textWithoutMedia(text)
    }

    /// What Copy as Plain Text puts there (#402): the same, as it reads, without the markdown.
    static func copyPlainText(_ text: String) -> String {
        MarkdownPlainText.from(copyText(text))
    }
}

/// The Mac's Copy on a reply (#255, #402): beside the bubble's trailing edge, by its last line, while the pointer is on
/// the bubble, on the controls or on the gap between them, and for half a second after it leaves. Copy copies the reply's
/// markdown and shows a checkmark for a moment; the ⋯ beside it offers Copy as Plain Text and Select Text, the way to copy
/// any part of a reply, more than a paragraph too.
///
/// The controls take a place of their own beside the bubble, inside the row. Drawn past the bubble's edge, outside its
/// frame, they got no hover there: the pointer on its way to Copy left the bubble and Copy went before it arrived (#402).
/// They stay in the tree while hidden (faded, not taking clicks), so a menu opened from them is never pulled from under
/// itself. Hidden from VoiceOver: the bubble's menu has Copy, Copy as Plain Text and Select Text, and Chat › Copy Last
/// Reply (⇧⌘C) is the keyboard way.
struct ReplyCopyHover: ViewModifier {
    var text: String
    var enabled: Bool
    var onSelectText: () -> Void = {}
    @State private var hovering = false
    @State private var lingering = false
    @State private var copiedAt: Date?
    @State private var leaving: Task<Void, Never>?

    /// The room the controls take beside the bubble: the trailing margin the row kept before.
    static let width: CGFloat = 46
    /// How long the controls stay after the pointer leaves.
    static let grace: Duration = .milliseconds(500)

    func body(content: Content) -> some View {
        let copied = copiedAt != nil
        let shown = enabled && (hovering || lingering || copied)
        HStack(alignment: .bottom, spacing: 2) {
            content
            HStack(spacing: 0) {
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(copied ? "Copied" : "Copy reply")
                Menu {
                    Button { UIPasteboard.general.string = TranscriptMedia.copyPlainText(text) } label: { Label("Copy as Plain Text", systemImage: "doc.plaintext") }
                    Button(action: onSelectText) { Label("Select Text…", systemImage: "selection.pin.in.out") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More ways to copy")
            }
            .frame(width: Self.width, alignment: .leading)
            .padding(.bottom, 2)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(true)
        }
        // One hover over the bubble, the gap and the controls.
        .contentShape(.rect)
        .onHover(perform: hover)
        .animation(.easeOut(duration: 0.12), value: shown)
    }

    private func hover(_ inside: Bool) {
        leaving?.cancel()
        if inside {
            hovering = true
            lingering = false
        } else {
            hovering = false
            lingering = true
            leaving = Task { @MainActor in
                try? await Task.sleep(for: Self.grace)
                guard !Task.isCancelled else { return }
                lingering = false
            }
        }
    }

    private func copy() {
        UIPasteboard.general.string = TranscriptMedia.copyText(text)
        let at = Date()
        withAnimation(.snappy) { copiedAt = at }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedAt == at { withAnimation(.snappy) { copiedAt = nil } }
        }
    }
}
