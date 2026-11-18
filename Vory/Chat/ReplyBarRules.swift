import CoreGraphics
import Foundation

#if os(iOS)
/// 59: the reply bar's rules, apart from its views so the unit tests reach them (`ReplyBarRulesTests`). At rest, with
/// nothing to show but the placeholder, the composer is a one-row pill; tapped, it becomes the card it always was as the
/// keyboard comes up, and goes back to the pill when the keyboard goes with the field empty. A press held on the pill's
/// text area dictates, and letting go puts the words in the field to check before sending. The Mac keeps the card.
enum ReplyBarRules {
    // MARK: Words (each one string, so a change of wording is one line)

    /// The pill's placeholder at rest.
    static let restPlaceholder = "Reply or hold to talk"
    /// The pill's placeholder while a reply runs: a message typed now waits in the queue (Steer still sends it into the
    /// reply, from the card's line or the queued strip).
    static let runningPlaceholder = "Sends after this reply"
    /// The hold bar's hint. It never says "send": letting go only fills the field.
    static let holdHint = "Let go to finish"

    // MARK: The pill or the card

    /// What the collapse depends on, read from the composer as it is.
    struct Composer: Equatable {
        /// The chat's own composer (not the New Message sheet's, not onboarding's tour).
        var chatsOwn = true
        var focused = false
        /// The field's text is empty (whitespace counts as text: it is the person's).
        var textEmpty = true
        var staged = false
        var quoted = false
        var editing = false
        /// A "/" or "@" list is open (the + panel opens above the pill as above the card).
        var listOpen = false
        var longTextOffer = false
        var holdNote = false
        /// The mic is listening or transcribing: the bar is the dictation bar, not the pill.
        var dictating = false
    }

    /// The pill: the chat's own composer, unfocused, with nothing in it and nothing open. Anything else is the card, so a
    /// draft stays in sight with the keyboard down.
    static func collapses(_ c: Composer) -> Bool {
        c.chatsOwn && !c.focused && c.textEmpty && !c.staged && !c.quoted && !c.editing && !c.listOpen
            && !c.longTextOffer && !c.holdNote && !c.dictating
    }

    /// The pill's trailing slot: voice mode at rest (Vory's own, full screen, unchanged; with it already running for this
    /// chat out of sight, the same button brings its screen back), the reply's stop while one runs (`chat.stop()`, as the
    /// card's stop).
    enum PillTrailing: Equatable { case voiceMode, stop }
    static func pillTrailing(running: Bool) -> PillTrailing { running ? .stop : .voiceMode }

    static func placeholder(running: Bool) -> String { running ? runningPlaceholder : restPlaceholder }

    // MARK: Where the bar rests

    /// How far the capsule of Vory's tab bar hangs into the home-indicator area (`VoryTabBar.overhang`): the bar rests
    /// at the same place, so it's as low as the system's own floating bars.
    static let overhang: CGFloat = 13
    /// The gap above the keyboard, above Vory's tab bar, or above the screen's edge with no home indicator.
    static let gap: CGFloat = 8

    /// The bar's bottom edge above the window's bottom edge, at rest: `max(8, safeBottom - 13)`. With the keyboard up, or
    /// with Vory's tab bar under the chat (the bar along the bottom), it stands 8 pt above them instead, as before.
    static func restingGap(safeBottom: CGFloat) -> CGFloat { max(gap, safeBottom - overhang) }

    /// The dock's bottom padding inside the keyboard's safe area: `gap` with the keyboard up or a bar under it; at rest, the
    /// resting gap less the safe area it stands in (negative on a phone with a home indicator: down into that area).
    static func dockBottomPadding(safeBottom: CGFloat, keyboardUp: Bool, barBelow: Bool) -> CGFloat {
        keyboardUp || barBelow ? gap : restingGap(safeBottom: safeBottom) - safeBottom
    }

    /// The dock's padding beyond the 8 pt `BottomDock` keeps below the card itself (`BottomDock.bottomPadding`): 0 with the
    /// keyboard up or a bar under it, and at rest the resting place less those 8 (−21 on a 34 pt phone: down into the
    /// home-indicator area).
    static func dockShift(safeBottom: CGFloat, keyboardUp: Bool, barBelow: Bool) -> CGFloat {
        dockBottomPadding(safeBottom: safeBottom, keyboardUp: keyboardUp, barBelow: barBelow) - gap
    }

    /// Where the dock's bottom edge stands with no keyboard and no lift (window space): the safe area's bottom, less the
    /// bar's reserve, less the shift. Nil until the window is measured. The fold lift (`ConversationView.foldLift`) works
    /// from it.
    static func restingDockBottom(windowHeight: CGFloat, safeBottom: CGFloat, barReserve: CGFloat) -> CGFloat? {
        guard windowHeight > 0 else { return nil }
        return windowHeight - safeBottom - barReserve - dockShift(safeBottom: safeBottom, keyboardUp: false, barBelow: barReserve > 0)
    }

    // MARK: Hold to dictate

    /// How long a press is held before it dictates, and how far it may move first.
    static let holdMinimum: TimeInterval = 0.30
    static let holdMovement: CGFloat = 10
    /// The pill's scale under a press.
    static let pressScale: CGFloat = 1.04

    /// The pill's one touch, from touch-down to the lift: the hold begins at `holdMinimum` if the finger is still down and
    /// has stayed within `holdMovement`; the lift then ends it, or, with no hold, is a tap if the finger never went farther
    /// than `holdMovement` (the largest movement in the touch, so a drag out and back isn't a tap).
    enum LiftAction: Equatable { case ended, tap, none }
    static func liftAction(began: Bool, maxMove: CGFloat) -> LiftAction {
        if began { return .ended }
        return maxMove <= holdMovement ? .tap : .none
    }

    /// The touch's largest movement so far, with the finger now at `now` (straight-line distance from where it went down).
    static func maxMove(_ soFar: CGFloat, start: CGPoint, now: CGPoint) -> CGFloat {
        let dx = now.x - start.x, dy = now.y - start.y
        return max(soFar, (dx * dx + dy * dy).squareRoot())
    }

    /// The hold's timer, set at touch-down for `holdMinimum`, begins the hold only for the touch that set it (`touch`, the
    /// touch counter then; `current`, the counter now), with the finger still down, no hold begun yet, and the finger
    /// within `holdMovement` so far. A lift, a reset or a new touch before it fires leaves it doing nothing, so a cancelled
    /// touch never starts dictation with no finger down.
    static func holdBegins(touch: Int, current: Int, touching: Bool, began: Bool, maxMove: CGFloat) -> Bool {
        touch == current && touching && !began && maxMove <= holdMovement
    }

    /// The hold is offered only on the pill (so never on a focused field, its selection, cursor or edit menu), and not
    /// while voice mode has the microphone or the mic is already dictating.
    static func holdOffered(collapsed: Bool, voiceModeActive: Bool, dictating: Bool) -> Bool {
        collapsed && !voiceModeActive && !dictating
    }

    /// What the hold's recognizer does at each of its states.
    enum HoldEvent { case began, ended, cancelled, failed }
    enum HoldAction: Equatable {
        /// `dictation.start()`, the pill turns into the hold bar.
        case start
        /// `dictation.stop`, the words into the field, focused, the keyboard up. Never sent.
        case fillField
        /// `dictation.cancel()`: a call or a system prompt took the touch; no words.
        case discard
    }
    static func action(for event: HoldEvent) -> HoldAction {
        switch event {
        case .began: return .start
        case .ended: return .fillField
        case .cancelled, .failed: return .discard
        }
    }

    /// Whether dictated words go out at once. The mic follows Settings › Voice › Send after dictation, as before; the
    /// hold never does: letting go puts the words in the field to check (2026-11-17).
    enum DictationSource { case mic, hold }
    static func sendsAtOnce(_ source: DictationSource, sendAfterDictation: Bool) -> Bool {
        source == .mic && sendAfterDictation
    }
}
#endif
