import SwiftUI
import UIKit

/// Every touch-down in the window opens a short `Smooth` animation interval ("touch"), so the
/// hitch metrics cover what a tap starts even where the control swallows the gesture before
/// any modifier of ours sees it (a Menu, a toolbar item, a sheet's own buttons). A recognizer
/// that never claims the touch: it only watches, the control under the finger still gets it.
struct TouchSignpostProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        private var recognizer: Watcher?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer?.view?.removeGestureRecognizer(recognizer!)
            recognizer = nil
            guard let window else { return }
            let w = Watcher(target: nil, action: nil)
            w.cancelsTouchesInView = false
            w.delaysTouchesBegan = false
            w.delaysTouchesEnded = false
            w.delegate = w
            window.addGestureRecognizer(w)
            recognizer = w
        }
    }

    final class Watcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            Smooth.animate("touch", for: 0.9)
            state = .failed
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
    }
}
