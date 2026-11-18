#if os(iOS)
import SwiftUI

/// 59: the reply bar's placeholder gestures, as one touch: a `DragGesture(minimumDistance: 0)` from touch-down to the
/// lift, with the hold's timing kept here rather than in a second gesture. Two gestures fought each other in 59's UI runs
/// (with a Button's tap the hold never began, or the tap never came; as `hold.exclusively(before: tap)` the tap never
/// fired on the lift that failed the hold), so there's one, and nothing else on the placeholder.
/// - Touch-down: the touch counter goes up, and a timer is set for `holdMinimum` (0.30 s, `ReplyBarRules`). When it fires
///   the hold begins only for that same touch, with the finger still down, no hold yet and the finger within
///   `holdMovement` (10 pt) so far (`ReplyBarRules.holdBegins`).
/// - The lift: `ReplyBarRules.liftAction`, from whether the hold began and the largest movement in the touch: the hold
///   ends (the words into the field, never sent), or a tap (focus), or nothing (a drag).
/// - A reset with no lift seen (a call or a system prompt taking the touch): the hold, if begun, is cancelled (no words);
///   with no hold, nothing (a cancelled touch isn't a tap). Checked on the next turn, so whichever of the reset and the
///   lift SwiftUI delivers first, a lift is never read as a cancel.
/// It lives only on the pill (never on the card or a focused field), so it never meets the text view's selection, cursor or
/// edit menu. `onPressing` reports a finger on the placeholder from touch-down, for the pill's press scale.
struct HoldToDictate: ViewModifier {
    var onEvent: (ReplyBarRules.HoldEvent) -> Void
    var onTap: () -> Void
    var onPressing: (Bool) -> Void = { _ in }
    /// A finger on the placeholder, from touch-down to the lift or a reset; reset by SwiftUI either way.
    @GestureState private var touching = false
    /// The touch counter: up at each touch-down, and at each lift and reset, so a timer from an earlier touch does nothing.
    @State private var touch = 0
    /// A touch is under way (its first change seen, no lift or reset yet).
    @State private var down = false
    /// The hold has begun and hasn't ended or been cancelled.
    @State private var began = false
    /// The lift was seen (`onEnded`), so the reset that comes with it isn't a cancel.
    @State private var ended = false
    /// The largest movement in the touch so far, from where it went down.
    @State private var maxMove: CGFloat = 0

    #if DEBUG
    /// 59's probe: every step of the touch to the perf log (`-vory-geometry-log`, as the thread's GEO lines), and
    /// `-vory-hold-no-pressing` to skip `onPressing` (the press scale never moves).
    nonisolated static let probe = ProcessInfo.processInfo.arguments.contains("-vory-geometry-log")
    nonisolated static let noPressing = ProcessInfo.processInfo.arguments.contains("-vory-hold-no-pressing")
    nonisolated static func stamp(_ line: String) { if probe { Perf.stamp("HOLDG " + line) } }
    #endif

    func body(content: Content) -> some View {
        let press = DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                if !down {
                    down = true; touch += 1; began = false; ended = false; maxMove = 0
                    let mine = touch
                    #if DEBUG
                    Self.stamp("down \(mine)")
                    #endif
                    // The hold's timer, on the main actor (the Task takes this context's). Never cancelled: a stale one
                    // does nothing (`holdBegins`).
                    Task {
                        try? await Task.sleep(for: .seconds(ReplyBarRules.holdMinimum))
                        timerFired(mine)
                    }
                }
                maxMove = ReplyBarRules.maxMove(maxMove, start: value.startLocation, now: value.location)
            }
            .onEnded { value in
                // A lift after the touch was already read as a cancel: nothing (never a tap).
                guard down else {
                    #if DEBUG
                    Self.stamp("lift after cancel: ignored")
                    #endif
                    return
                }
                maxMove = ReplyBarRules.maxMove(maxMove, start: value.startLocation, now: value.location)
                let action = ReplyBarRules.liftAction(began: began, maxMove: maxMove)
                #if DEBUG
                Self.stamp("lift \(touch) maxMove=\(maxMove) -> \(action)")
                #endif
                ended = true; down = false; touch += 1; began = false
                switch action {
                case .ended:
                    #if DEBUG
                    Self.stamp("ended")
                    #endif
                    onEvent(.ended)
                case .tap:
                    #if DEBUG
                    Self.stamp("tap")
                    #endif
                    onTap()
                case .none:
                    break
                }
            }
        return content
            .gesture(press)
            .onChange(of: touching) { _, now in
                #if DEBUG
                Self.stamp("touching \(now)")
                if !Self.noPressing { onPressing(now) }
                #else
                onPressing(now)
                #endif
                guard !now else { return }
                // A reset with no lift seen is a cancel, read on the next turn (the lift's onEnded may come after it).
                DispatchQueue.main.async {
                    if !ended, down {
                        down = false; touch += 1
                        let wasHeld = began
                        began = false
                        #if DEBUG
                        Self.stamp("cancelled held=\(wasHeld)")
                        #endif
                        if wasHeld { onEvent(.cancelled) }
                    }
                    ended = false
                }
            }
    }

    /// The hold's timer, for the touch numbered `mine`.
    private func timerFired(_ mine: Int) {
        let go = ReplyBarRules.holdBegins(touch: mine, current: touch, touching: touching, began: began, maxMove: maxMove)
        #if DEBUG
        Self.stamp("timer \(mine) current=\(touch) touching=\(touching) began=\(began) maxMove=\(maxMove) -> \(go ? "begin" : "skip")")
        #endif
        guard go else { return }
        began = true
        #if DEBUG
        Self.stamp("began")
        #endif
        onEvent(.began)
    }
}
#endif
