import SwiftUI

/// The window's own geometry, for the few places that lay out against the window rather than
/// their own frame: the chat thread's bottom edge and keyboard margin, the dock, the tab bar's
/// hang into the home-indicator area, and the caps that were a share of "the screen". It used
/// to come from `UIScreen.main` and a one-off read of the key window's insets, which is wrong
/// whenever the window is not the whole screen (an iPad window, Split View, the Duo's two
/// displays) and goes stale when the window changes size or the insets move (a fold, a vertical
/// bar appearing). This is read from the window every time it lays out, so it follows all of that.
///
/// One per scene, put into the environment by the root; the Mac's views get the empty default
/// and never read it (their layout is the window's own).
@MainActor @Observable
final class WindowGeometry {
    /// The window's bounds in its own space (origin zero).
    var bounds: CGRect = .zero
    /// The window's safe-area insets: each edge its own value, never assumed symmetric.
    var safeArea: EdgeInsets = EdgeInsets()
    /// The keyboard's frame in window space when one is up at the bottom of the window;
    /// `.null` when there is none, it is hidden, or it does not sit on the window's bottom edge
    /// (a floating iPad keyboard, another scene's).
    var keyboard: CGRect = .null

    /// Nonisolated so the environment's default (an empty geometry, what the Mac's views see)
    /// can be made anywhere; every read and write after that is on the main actor.
    nonisolated init() {}

    /// How much of the window's height the keyboard covers above the bottom safe-area inset:
    /// what the dock and the thread move up by. Zero with no keyboard.
    var keyboardOverlap: CGFloat { Self.keyboardOverlap(window: bounds, keyboard: keyboard, safeBottom: safeArea.bottom) }

    /// The keyboard frame `end` (already in window space) that counts: one that sits on the
    /// window's bottom edge (or is entirely below it, which is "hidden") and is less than two
    /// thirds of the window tall. Anything else (a floating keyboard, a hardware keyboard's bar
    /// somewhere else, a whole-window rect from another scene) is `.null`.
    nonisolated static func keyboardRect(window: CGRect, end: CGRect) -> CGRect {
        guard !end.isNull, window.height > 0, end.height < window.height * 0.66 else { return .null }
        if end.minY >= window.maxY - 0.5 { return .null }
        let onWindow = end.intersection(window)
        guard !onWindow.isNull, onWindow.maxY >= window.maxY - 1 else { return .null }
        return end
    }

    nonisolated static func keyboardOverlap(window: CGRect, keyboard: CGRect, safeBottom: CGFloat) -> CGFloat {
        guard !keyboard.isNull, window.height > 0 else { return 0 }
        let covered = max(0, window.maxY - keyboard.minY)
        return min(max(0, covered - safeBottom), window.height * 0.6)
    }
}

extension EnvironmentValues {
    @Entry var windowGeometry: WindowGeometry = WindowGeometry()
}

#if os(iOS)
/// Reads the window into a `WindowGeometry` on every layout and inset change. Put one in the
/// root; it draws nothing.
struct WindowGeometryReader: UIViewRepresentable {
    let geometry: WindowGeometry

    func makeUIView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.geometry = geometry
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: ReaderView, context: Context) { uiView.geometry = geometry }

    final class ReaderView: UIView {
        var geometry: WindowGeometry?
        /// The last keyboard frame the notification gave, in screen space, kept so a window
        /// resize (a fold) can re-place it in window space without waiting for a new one.
        private var keyboardEndOnScreen: CGRect = .null

        override func didMoveToWindow() {
            super.didMoveToWindow()
            publish()
            guard !observing, window != nil else { return }
            observing = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            center.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        }
        private var observing = false
        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func keyboardWillChange(_ n: Notification) {
            keyboardEndOnScreen = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .null
            publish()
        }
        @objc private func keyboardWillHide(_ n: Notification) {
            keyboardEndOnScreen = .null
            publish()
        }

        override func layoutSubviews() { super.layoutSubviews(); publish() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); publish() }

        private func publish() {
            guard let geometry, let window else { return }
            let bounds = window.bounds
            let insets = window.safeAreaInsets
            // The notification's frame is in screen space; the window places it in its own.
            let end: CGRect = keyboardEndOnScreen.isNull ? .null : window.convert(keyboardEndOnScreen, from: window.screen.coordinateSpace)
            let keyboard = WindowGeometry.keyboardRect(window: bounds, end: end)
            if geometry.bounds != bounds { geometry.bounds = bounds }
            let edges = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
            if geometry.safeArea != edges { geometry.safeArea = edges }
            if geometry.keyboard != keyboard { geometry.keyboard = keyboard }
        }
    }
}
#endif
