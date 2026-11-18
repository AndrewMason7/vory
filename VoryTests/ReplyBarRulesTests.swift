import CoreGraphics
import Testing
@testable import Vory

#if os(iOS)
/// 59: the reply bar's rules (`ReplyBarRules`). At rest the composer is a one-row pill (+, the placeholder, the mic, voice
/// mode or the reply's stop), it becomes the card it always was on focus, it rests lower (as low as Vory's tab bar's
/// capsule), and a press held on the pill dictates into the field without sending.
@Suite struct ReplyBarRulesTests {
    typealias R = ReplyBarRules

    // MARK: The pill or the card

    /// At rest, unfocused and empty: the pill.
    @Test func anEmptyUnfocusedComposerIsThePill() {
        #expect(R.collapses(.init()))
    }

    /// Anything in it, or anything open, keeps the card, so a draft stays in sight with the keyboard down.
    @Test(arguments: [
        R.Composer(focused: true), R.Composer(textEmpty: false), R.Composer(staged: true), R.Composer(quoted: true),
        R.Composer(editing: true), R.Composer(listOpen: true), R.Composer(longTextOffer: true), R.Composer(holdNote: true),
        R.Composer(dictating: true),
    ])
    func anythingInItKeepsTheCard(_ c: R.Composer) {
        #expect(!R.collapses(c))
    }

    /// The New Message sheet and onboarding's tour keep the card.
    @Test func otherComposersKeepTheCard() {
        #expect(!R.collapses(.init(chatsOwn: false)))
    }

    // MARK: The pill's trailing slot and words

    /// Voice mode at rest (2026-11-17), the reply's stop while one runs.
    @Test func voiceModeAtRestStopWhileRunning() {
        #expect(R.pillTrailing(running: false) == .voiceMode)
        #expect(R.pillTrailing(running: true) == .stop)
    }

    /// The placeholders, one string each.
    @Test func placeholders() {
        #expect(R.placeholder(running: false) == "Reply or hold to talk")
        #expect(R.placeholder(running: true) == "Sends after this reply")
    }

    /// The hold's hint never says "send": letting go only fills the field.
    @Test func theHoldHintNeverSaysSend() {
        #expect(!R.holdHint.lowercased().contains("send"))
    }

    // MARK: Where the bar rests

    /// A phone with a home indicator (34 pt): 21 pt above the screen's edge, as low as the tab bar's capsule. 57: 42.
    @Test func aHomeIndicatorPhoneRestsTwentyOneAboveTheEdge() {
        #expect(R.restingGap(safeBottom: 34) == 21)               // 57: 42 (8 above the safe area)
        #expect(R.dockBottomPadding(safeBottom: 34, keyboardUp: false, barBelow: false) == -13)  // 57: 8
    }

    /// A home-button phone (the SE, 0 pt): 8 pt above the edge, as before.
    @Test func aHomeButtonPhoneRestsAsBefore() {
        #expect(R.restingGap(safeBottom: 0) == 8)
        #expect(R.dockBottomPadding(safeBottom: 0, keyboardUp: false, barBelow: false) == 8)
    }

    /// A small inset (an iPad's 20 pt, with no bar under the chat): never under 8 pt above the edge.
    @Test func aSmallInsetKeepsTheGap() {
        #expect(R.restingGap(safeBottom: 20) == 8)
        #expect(R.dockBottomPadding(safeBottom: 20, keyboardUp: false, barBelow: false) == -12)
    }

    /// With the keyboard up, or Vory's tab bar under the chat: 8 pt above them, as before.
    @Test(arguments: [CGFloat(0), 20, 34])
    func aboveTheKeyboardOrTheBarAsBefore(safeBottom: CGFloat) {
        #expect(R.dockBottomPadding(safeBottom: safeBottom, keyboardUp: true, barBelow: false) == 8)
        #expect(R.dockBottomPadding(safeBottom: safeBottom, keyboardUp: false, barBelow: true) == 8)
    }

    /// The same overhang as Vory's tab bar's capsule, so the two rest at the same height.
    @Test func theOverhangIsTheTabBars() {
        #expect(R.overhang == VoryTabBar.overhang(safeBottom: 34))
    }

    /// The dock's own 8 pt below the card is the rules' gap, so the shift's arithmetic holds.
    @Test func theDocksOwnPaddingIsTheGap() {
        #expect(BottomDock.bottomPadding == R.gap)
    }

    /// The shift: −21 on a 34 pt phone at rest; 0 with the keyboard up, with a bar under the chat, or with no home
    /// indicator.
    @Test func theShift() {
        #expect(R.dockShift(safeBottom: 34, keyboardUp: false, barBelow: false) == -21)   // 57: 0
        #expect(R.dockShift(safeBottom: 34, keyboardUp: true, barBelow: false) == 0)
        #expect(R.dockShift(safeBottom: 20, keyboardUp: false, barBelow: true) == 0)
        #expect(R.dockShift(safeBottom: 0, keyboardUp: false, barBelow: false) == 0)
    }

    /// restingDockBottom, pinned: the dock's bottom edge at rest, the card's 8 pt above it. An iPhone 17 Pro (874 tall, 34
    /// safe): the dock at 861, the card's edge at 853, 21 above the window's edge (57: the dock at 840, the card 42
    /// above). An SE (667, 0): as 57. An iPad with the bar under the chat (1194, 20, Vory's reserve of 43 there: 56 − 13):
    /// as 57.
    @Test func restingDockBottomPinned() {
        #expect(R.restingDockBottom(windowHeight: 874, safeBottom: 34, barReserve: 0) == 861)   // 57: 840
        #expect(R.restingDockBottom(windowHeight: 667, safeBottom: 0, barReserve: 0) == 667)
        #expect(R.restingDockBottom(windowHeight: 1194, safeBottom: 20, barReserve: 43) == 1131)
        #expect(R.restingDockBottom(windowHeight: 0, safeBottom: 34, barReserve: 0) == nil)
    }

    /// Documentation, not evidence (true by construction; the UI tests are the evidence): the fold lift's two reads agree
    /// at rest, the slot's bottom (the safe area's) less the reserve and the shift being restingDockBottom.
    @Test(arguments: [(CGFloat(874), CGFloat(34), CGFloat(0)), (667, 0, 0), (1194, 20, 43)])
    func theLiftsReadsAgreeAtRest(_ w: (CGFloat, CGFloat, CGFloat)) {
        let slot = w.0 - w.1
        let shift = R.dockShift(safeBottom: w.1, keyboardUp: false, barBelow: w.2 > 0)
        #expect(slot - w.2 - shift == R.restingDockBottom(windowHeight: w.0, safeBottom: w.1, barReserve: w.2))
    }

    // MARK: Hold to dictate

    /// Only on the pill: never on a focused field (its selection, cursor and edit menu stay as they are).
    @Test func theHoldIsOnlyOnThePill() {
        #expect(R.holdOffered(collapsed: true, voiceModeActive: false, dictating: false))
        #expect(!R.holdOffered(collapsed: false, voiceModeActive: false, dictating: false))
    }

    /// Not while voice mode has the microphone, nor while the mic is already dictating.
    @Test func notWithTheMicrophoneTaken() {
        #expect(!R.holdOffered(collapsed: true, voiceModeActive: true, dictating: false))
        #expect(!R.holdOffered(collapsed: true, voiceModeActive: false, dictating: true))
    }

    /// The recognizer's states: a hold starts, letting go fills the field, a system cancel leaves no words.
    @Test func theRecognizersStates() {
        #expect(R.action(for: .began) == .start)
        #expect(R.action(for: .ended) == .fillField)
        #expect(R.action(for: .cancelled) == .discard)
        #expect(R.action(for: .failed) == .discard)
    }

    /// A lift after the hold began ends it, however far the finger went while held.
    @Test func aLiftAfterTheHoldEndsIt() {
        #expect(R.liftAction(began: true, maxMove: 0) == R.LiftAction.ended)
        #expect(R.liftAction(began: true, maxMove: 10) == R.LiftAction.ended)
        #expect(R.liftAction(began: true, maxMove: 500) == R.LiftAction.ended)
    }

    /// With no hold, a lift within 10 pt is a tap (10 itself included); past 10 it's nothing.
    @Test func aShortLiftIsATapUpToTenPoints() {
        #expect(R.liftAction(began: false, maxMove: 0) == R.LiftAction.tap)
        #expect(R.liftAction(began: false, maxMove: 10) == R.LiftAction.tap)
        #expect(R.liftAction(began: false, maxMove: 10.5) == R.LiftAction.none)
        #expect(R.liftAction(began: false, maxMove: 200) == R.LiftAction.none)
    }

    /// The largest movement counts, not the last: a drag 40 pt out and back to the start isn't a tap.
    @Test func aDragOutAndBackIsntATap() {
        let start = CGPoint(x: 100, y: 20)
        let path = [CGPoint(x: 100, y: 20), CGPoint(x: 124, y: 52), CGPoint(x: 110, y: 30), CGPoint(x: 100, y: 20)]
        let most = path.reduce(CGFloat(0)) { R.maxMove($0, start: start, now: $1) }
        #expect(most == 40)
        #expect(R.liftAction(began: false, maxMove: most) == R.LiftAction.none)
        let still = [CGPoint(x: 100, y: 20), CGPoint(x: 106, y: 28), CGPoint(x: 100, y: 20)]
        #expect(R.liftAction(began: false, maxMove: still.reduce(CGFloat(0)) { R.maxMove($0, start: start, now: $1) }) == R.LiftAction.tap)
    }

    /// The timer begins the hold only for its own touch, with the finger down, no hold yet, and within 10 pt.
    @Test func theTimerBeginsOnlyForItsLiveTouch() {
        #expect(R.holdBegins(touch: 3, current: 3, touching: true, began: false, maxMove: 10))
        #expect(!R.holdBegins(touch: 3, current: 4, touching: true, began: false, maxMove: 0))     // a later touch
        #expect(!R.holdBegins(touch: 3, current: 3, touching: false, began: false, maxMove: 0))    // lifted or reset
        #expect(!R.holdBegins(touch: 3, current: 3, touching: true, began: true, maxMove: 0))      // begun already
        #expect(!R.holdBegins(touch: 3, current: 3, touching: true, began: false, maxMove: 10.5))  // moved too far
    }

    /// The hold never sends, whatever Settings › Voice › Send after dictation says. The mic follows the setting, as before.
    @Test(arguments: [false, true])
    func theHoldNeverSends(sendAfterDictation: Bool) {
        #expect(!R.sendsAtOnce(.hold, sendAfterDictation: sendAfterDictation))
        #expect(R.sendsAtOnce(.mic, sendAfterDictation: sendAfterDictation) == sendAfterDictation)
    }

    #if DEBUG
    /// The UI tests' fake dictation (`-vory-fake-dictation "<words>"`, DEBUG only): the words are the argument after the
    /// flag; none without it, or with the flag last.
    @Test func theFakeDictationsWords() {
        #expect(DictationController.fakeWords(in: ["Vory"]) == nil)
        #expect(DictationController.fakeWords(in: ["Vory", "-vory-fake-dictation", "testing testing"]) == "testing testing")
        #expect(DictationController.fakeWords(in: ["Vory", "-vory-fake-dictation", ""]) == "")
        #expect(DictationController.fakeWords(in: ["Vory", "-vory-fake-dictation"]) == nil)
    }
    #endif

    /// The hold's timing: a hold at 0.3 s, a little movement allowed, a slight press scale.
    @Test func theHoldsTiming() {
        #expect(R.holdMinimum == 0.30)
        #expect(R.holdMovement == 10)
        #expect(R.pressScale > 1 && R.pressScale <= 1.05)
    }
}
#endif
