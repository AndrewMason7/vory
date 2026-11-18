import UIKit
import XCTest

/// 59: the reply bar (the pill at rest, the card on focus, the latched mic bar, the hold to dictate, the lower rest) on
/// screen. Launched as the demo (`-vory-demo`: the app's own demo connection, no gateway) with the DEBUG fake dictation
/// (`-vory-fake-dictation`: no microphone, no permission, no audio session). Skipped unless HERMES_E2E_BUNDLE is set.
/// Each test logs `R59` lines for a reader of the test log; most tests also assert. With REPLYBAR_BASE=57 (a clean 57
/// build, for side-by-side reads) only testModelChipAsFiftySeven and testAudit run, on 57's card.
@MainActor
final class ReplyBar59UITests: XCTestCase {
    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment
    private var base57: Bool { env["REPLYBAR_BASE"] == "57" }

    // MARK: Helpers

    private func say(_ s: String) { print("R59 \(s) t=\(String(format: "%.3f", Date().timeIntervalSince1970))") }
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    private func f(_ r: CGRect) -> String { String(format: "(%.1f,%.1f,%.1f,%.1f)", r.minX, r.minY, r.width, r.height) }
    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private var keyboardUp: Bool { app.keyboards.count > 0 }
    /// The keyboard as XCUITest sees it, beside the window: "keyboards=<n> frame=<frame or ->
    /// window=<frame>". A software keyboard on screen has a frame inside the window; none, "-".
    private var keyboardRead: String {
        let n = app.keyboards.count, k = app.keyboards.firstMatch
        return "keyboards=\(n) frame=\(n > 0 && k.exists ? f(k.frame) : "-") window=\(f(app.windows.firstMatch.frame))"
    }

    /// The fake's words: "testing testing", or none with R59_EMPTY=1 (an explicit flag: xcodebuild may not pass an empty
    /// environment value on).
    private var fakeWords: String { env["R59_EMPTY"] == "1" ? "" : (env["R59_WORDS"] ?? "testing testing") }

    /// The demo, the fake dictation (`fakeWords`), and the test's extras.
    /// `scheme` sets light or dark through the arguments domain (testPlaceholderContrast, testOpenRow).
    private func launch(_ extra: [String] = [], scheme: String = "light") throws {
        guard let bundle = env["HERMES_E2E_BUNDLE"], !bundle.isEmpty else { throw XCTSkip("HERMES_E2E_BUNDLE not set") }
        app = XCUIApplication(bundleIdentifier: bundle)
        var args = ["-vory-demo", "-companionPromptShown", "YES", "-launchTab", "chats", "-colorSchemePreference", scheme]
        if !base57 { args += ["-vory-fake-dictation", fakeWords] }
        // The probe: HoldToDictate's HOLDG stamps in the perf log, and with R59_NO_PRESS=1 no press scale.
        if env["R59_PROBE"] == "1", !extra.contains("-vory-geometry-log") { args += ["-vory-geometry-log"] }
        if env["R59_NO_PRESS"] == "1" { args += ["-vory-hold-no-pressing"] }
        if let size = env["R59_SIZE"], !size.isEmpty { args += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments = args + extra
        app.launch()
    }

    /// The demo's first chat, opened by its row; the bar at rest (the pill, or 57's card).
    private func openChat() throws {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Packing list' AND NOT (identifier BEGINSWITH 'chat.')")).firstMatch
        guard row.waitForExistence(timeout: 30) else { say("VOID SETUP: the demo's first chat row is not there"); throw XCTSkip("no demo row") }
        row.tap()
        let rest = base57 ? el("composer.text") : el("composer.pill")
        guard rest.waitForExistence(timeout: 20) else { say("VOID SETUP: no \(base57 ? "composer.text" : "composer.pill") after the row"); throw XCTSkip("no bar") }
        pause(1.0)
        say("SETUP chat open; dock \(f(el("chat.dock").frame)) window \(f(app.windows.firstMatch.frame))")
    }

    /// The on-screen keyboard must be there for the tests that need it; without it the run stops (a hardware keyboard).
    private func requireKeyboard(_ what: String) {
        if !keyboardUp { say("STOP no software keyboard at \(what) (a hardware keyboard attached?)") }
        XCTAssertTrue(keyboardUp, "no software keyboard at \(what)")
    }

    private func focusFromPill() {
        el("composer.pill").tap()
        pause(1.0)   // the morph settles before the keyboard is read
    }

    /// The tap that focuses (59: the pill; 57: its card's field), timed: from the tap to `composer.text` there, and to the
    /// keyboard up, polled every 20 ms for up to 3 s (each read costs XCUITest's own query time, the same on both builds).
    @discardableResult private func timedFocus(_ label: String) -> (field: Double, keyboard: Double) {
        let target = base57 ? el("composer.text") : el("composer.pill")
        let t0 = Date(); target.tap()
        var tf = -1.0, tk = -1.0
        while Date().timeIntervalSince(t0) < 3, tf < 0 || tk < 0 {
            if tf < 0, el("composer.text").exists, base57 || !el("composer.pill").exists { tf = Date().timeIntervalSince(t0) }
            if tk < 0, keyboardUp { tk = Date().timeIntervalSince(t0) }
            pause(0.02)
        }
        say(String(format: "TAPTIME %@ base=%@ field=%.3f keyboard=%.3f", label, base57 ? "57" : "59", tf, tk))
        pause(max(0, 1.0 - Date().timeIntervalSince(t0)))   // the morph settles
        return (tf, tk)
    }

    /// A reply must be running at the moment of a read: Stop (the pill's or the card's), or the card's Queue message.
    /// If not, the read is VOID, never a failure: the demo's reply (DemoContent.everyday, about 5 s) may have ended.
    private func requireRunning(_ what: String) throws {
        let running = app.buttons["Stop"].firstMatch.exists || app.buttons["Queue message"].firstMatch.exists
        say("RUNNINGCHECK \(what) running=\(running)")
        if !running { say("VOID \(what): the reply had ended"); throw XCTSkip("the reply had ended before \(what)") }
    }

    /// The app's own close (KeyboardClose, #350): a tap in the thread, between the header's bottom and the dock's top,
    /// beside a message of your own: 8 pt in from the leading edge of the last `thread.row.user` row whose middle is in
    /// that band, at its middle. That row is a Spacer of at least 56 pt and then the bubble (TranscriptRow's `.user`
    /// case), so the point is blank and toggles nothing. The reading column's margin isn't (at x = 2 the demo's Reasoning
    /// row opens, on 57 too; ReasoningDisclosure is one full-width hit target, edge to edge), and a toggle keeps the
    /// keyboard up by design (#634). No user row in the band: VOID. No drag: a drag scrolls the thread.
    /// After the tap: the keyboard still up is the tap point's miss, never the app's: DISMISS no close, VOID. The chat must
    /// still be open, or VOID. A close with no pill after it is the caller's FAIL. The perf log's GEO lines show any
    /// change in the thread's height near the tap, so a card hit shows.
    private func dismissKeyboard() throws {
        let headerEl = el("chat.header"), dock = el("chat.dock").frame, win = app.windows.firstMatch.frame
        let header = headerEl.exists ? headerEl.frame : .zero
        let top = max(win.minY, header.maxY) + 4, bottom = dock.minY - 4
        let rows = app.descendants(matching: .any).matching(identifier: "thread.row.user").allElementsBoundByIndex
        guard let row = rows.last(where: { $0.frame.midY > top && $0.frame.midY < bottom && $0.frame.width > 64 }) else {
            say("DISMISS no user row in the band \(Int(top))...\(Int(bottom)) (\(rows.count) user rows): VOID")
            throw XCTSkip("no user row in the band to tap beside")
        }
        let x = row.frame.minX + 8, y = row.frame.midY
        let line = "DISMISS tap at (\(Int(x)),\(Int(y))) beside user row \(f(row.frame)) header \(headerEl.exists ? f(header) : "none") dock \(f(dock))"
        say(line)
        underPoint(CGPoint(x: x, y: y))   // what the chat holds under the point, just before the tap
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - win.minX, dy: y - win.minY)).tap()
        say("DISMISS tapped")
        pause(1.0)
        guard el("chat.dock").exists, el("composer.pill").exists || el("composer.text").exists else {
            say("VOID \(line): the chat isn't open after the tap"); throw XCTSkip("the dismiss tap left the chat")
        }
        if keyboardUp {
            say("DISMISS no close at (\(Int(x)),\(Int(y))): VOID (the tap point's miss, not the app's)")
            throw XCTSkip("the dismiss tap didn't close the keyboard")
        }
    }

    /// Every element of the visible chat whose frame holds `p`, from one snapshot of the
    /// transcript's own scroll view (the one holding thread.row.user; a whole-app walk read hidden tabs). Each as "UNDER
    /// <type> id=<id> label=<label> frame=<frame> depth=<d>", smallest first, so the row, a card or a leftover view shows.
    private func underPoint(_ p: CGPoint) {
        let scroll = app.scrollViews.containing(.any, identifier: "thread.row.user").firstMatch
        guard scroll.exists, let root = try? scroll.snapshot() else { say("UNDER (\(Int(p.x)),\(Int(p.y))): no transcript scroll view"); return }
        var hits: [(Int, XCUIElementSnapshot)] = []
        func walk(_ s: XCUIElementSnapshot, _ d: Int) {
            if s.frame.contains(p) { hits.append((d, s)) }
            for c in s.children { walk(c, d + 1) }
        }
        walk(root, 0)
        say("UNDER (\(Int(p.x)),\(Int(p.y))) in the transcript \(f(root.frame)): \(hits.count) elements")
        for (d, s) in hits.sorted(by: { $0.1.frame.width * $0.1.frame.height < $1.1.frame.width * $1.1.frame.height }).prefix(8) {
            say("UNDER \(s.elementType.rawValue) id=\(s.identifier.isEmpty ? "-" : s.identifier) label=\(String(s.label.prefix(50))) frame=\(f(s.frame)) depth=\(d)")
        }
    }

    /// The chat brought to its end by drags up the thread (no tap: a drag scrolls), until the last row's bottom
    /// stops moving (two reads within 1 pt), up to four drags; each logged. True when it stood still.
    private func scrollToEnd() -> Bool {
        let win = app.windows.firstMatch.frame, dock = el("chat.dock").frame, origin = app.coordinate(withNormalizedOffset: .zero)
        let header = el("chat.header").exists ? el("chat.header").frame.maxY : win.minY
        let rows = { self.app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'thread.row.'")).allElementsBoundByIndex }
        var last: CGFloat = -1
        for i in 1...4 {
            let from = origin.withOffset(CGVector(dx: win.midX, dy: dock.minY - 40))
            let to = origin.withOffset(CGVector(dx: win.midX, dy: max(header + 40, dock.minY - 240)))
            from.press(forDuration: 0.05, thenDragTo: to); pause(0.8)
            let bottom = rows().map { $0.frame.maxY }.max() ?? -1
            say("ENDSCROLL \(i) the last row's bottom \(Int(bottom)) the dock's top \(Int(dock.minY))")
            if abs(bottom - last) < 1 { return true }
            last = bottom
        }
        return false
    }

    private func sentCount(_ words: String) -> Int {
        // The words as a sent bubble (static text), not in the field (a text view).
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", words)).count
    }

    // MARK: 1. The rest place

    func testRestPlace() throws {
        try launch(); try openChat()
        let dock = el("chat.dock").frame, win = app.windows.firstMatch.frame
        // `chat.dock` is the stack inside BottomDock's own 8 pt padding, so its frame is the pill itself (on an
        // iPhone 17 Pro, (12,803,378,50)): the gap is the window's bottom less the dock's.
        let gap = win.maxY - dock.maxY
        say("REST dock \(f(dock)) window \(f(win)) cardGap \(String(format: "%.1f", gap)) tabbar \(el("tabbar").exists ? f(el("tabbar").frame) : "none")")
        if let want = env["R59_REST_GAP"].flatMap(Double.init) { XCTAssertEqual(gap, want, accuracy: 1, "the card's gap above the window's edge") }
    }

    // MARK: 2. The pill and the card, 5 times, then after the + panel

    func testPillAndCard() throws {
        try launch(); try openChat()
        XCTAssertTrue(el("composer.attach").exists && el("composer.voiceMode").exists, "the pill's controls")
        XCTAssertFalse(el("composer.modelChip").exists, "no model chip on the pill")
        for pass in 1...5 {
            timedFocus("pass \(pass)")
            requireKeyboard("pass \(pass)")
            let focused = (el("composer.text").value(forKey: "hasKeyboardFocus") as? Bool) ?? false
            say("PILLCARD pass=\(pass) keyboard=\(keyboardUp) focus=\(focused) chip=\(el("composer.modelChip").exists)")
            XCTAssertTrue(focused, "pass \(pass): composer.text has focus")
            XCTAssertTrue(el("composer.modelChip").exists, "pass \(pass): the card's model chip")
            try dismissKeyboard()
            XCTAssertTrue(el("composer.pill").waitForExistence(timeout: 5), "pass \(pass): the pill again")
            XCTAssertFalse(keyboardUp, "pass \(pass): no keyboard at rest")
        }
        el("composer.attach").tap(); pause(1.0)
        say("PANEL open (attach label \(el("composer.attach").label))")
        el("composer.attach").tap(); pause(1.0)
        focusFromPill()
        requireKeyboard("after the + panel")
        let focused = (el("composer.text").value(forKey: "hasKeyboardFocus") as? Bool) ?? false
        say("PILLCARD after-panel keyboard=\(keyboardUp) focus=\(focused)")
        XCTAssertTrue(focused, "after the + panel: composer.text has focus")
    }

    // MARK: 3. The frames, read from the geometry log

    func testExpandFrames() throws {
        try launch(["-vory-geometry-log"]); try openChat()
        // R59_SHOW_ONLY=1: one focus from rest and 1.5 s, nothing else (like for like with 57: 57's card field, 59's
        // pill). The full test also runs on 57 (the dismiss beside a user row needs no flag): three shows and three
        // dismisses on 57's card field, and the hold only on 59's pill.
        if env["R59_SHOW_ONLY"] == "1" {
            say("MARK show-only")
            if base57 { el("composer.text").tap() } else { el("composer.pill").tap() }
            pause(1.5)
            say("MARK done keyboard=\(keyboardUp)")
            return
        }
        for n in 1...3 {
            say("MARK show-\(n)")
            if base57 { el("composer.text").tap(); pause(1.0) } else { focusFromPill() }
            requireKeyboard("show \(n)")
            say("MARK dismiss-\(n)"); try dismissKeyboard()
        }
        if !base57 { say("MARK hold-end"); el("composer.pill").press(forDuration: 1.2); pause(1.5) }
        say("MARK done")
    }

    // MARK: 4 and 5. The hold

    func testHoldFillsTheField() throws {
        // R59_SEND_AFTER=YES launches with Send after dictation on, through the arguments domain (nothing is saved).
        try launch(env["R59_SEND_AFTER"] == "YES" ? ["-voice.sendAfterDictation", "YES"] : []); try openChat()
        let words = fakeWords
        el("composer.pill").press(forDuration: 1.2)
        let field = el("composer.text")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the card after the hold")
        pause(1.0)
        let value = field.value as? String ?? ""
        let focused = (field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
        say("HOLD words=\(value) focus=\(focused) keyboard=\(keyboardUp) sent=\(sentCount(words)) starts=\(el("debug.dictationStarts").value ?? "-")")
        XCTAssertEqual(value, words, "the words in the field")
        XCTAssertTrue(focused, "the field has focus")
        requireKeyboard("after the hold")
        XCTAssertEqual(sentCount(words), 0, "nothing sent")
    }

    func testHoldEmptyWords() throws {
        // Needs R59_EMPTY=1; without it the fake would have words and the test would mean nothing: VOID.
        say("HOLDEMPTY received R59_EMPTY=\(env["R59_EMPTY"] ?? "unset") words='\(fakeWords)'")
        guard env["R59_EMPTY"] == "1", fakeWords.isEmpty else { say("VOID HOLDEMPTY: the words aren't empty"); throw XCTSkip("no empty words") }
        try launch(); try openChat()
        el("composer.pill").press(forDuration: 1.2)
        pause(1.5)
        say("HOLDEMPTY pill=\(el("composer.pill").exists) holdBar=\(el("composer.holdBar").exists) text=\(el("composer.text").exists) keyboard=\(keyboardUp)")
        XCTAssertTrue(el("composer.pill").exists, "the pill again")
        XCTAssertFalse(el("composer.holdBar").exists, "the hold ended (the release was seen)")
        XCTAssertFalse(keyboardUp, "no keyboard: the button's tap didn't also fire")
    }

    // MARK: 6. No hold with the keyboard up

    func testNoHoldWithTheKeyboardUp() throws {
        try launch(); try openChat()
        focusFromPill(); requireKeyboard("focused")
        let field = el("composer.text")
        field.typeText("hello")
        let before = el("debug.dictationStarts").value as? String ?? "-"
        field.press(forDuration: 0.8); pause(1.0)
        let menu = editMenu()
        say("NOHOLD words holdBar=\(el("composer.holdBar").exists) starts \(before)->\(el("debug.dictationStarts").value ?? "-") menu=\(menu) text=\(field.value ?? "-")")
        XCTAssertFalse(el("composer.holdBar").exists, "no hold bar")
        XCTAssertEqual(el("debug.dictationStarts").value as? String, before, "no dictation started")
        XCTAssertFalse(menu.isEmpty, "the edit menu came up")
        XCTAssertEqual(field.value as? String, "hello", "the words stay")
        // The second case: the field emptied, still focused; a long press shows Paste and starts nothing.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()   // the menu away, above the bar
        // Paste is offered only with something on the pasteboard: set from the test (a fresh simulator's may be empty).
        // The menu's Paste reads nothing until tapped, and it isn't tapped, so no paste question comes up.
        UIPasteboard.general.string = "59 paste check"
        say("PASTEBOARD set to '59 paste check'")
        field.tap(); field.clearText(); pause(0.5)
        requireKeyboard("emptied")
        let before2 = el("debug.dictationStarts").value as? String ?? "-"
        field.press(forDuration: 0.8); pause(1.0)
        let menu2 = editMenu()
        say("NOHOLD empty holdBar=\(el("composer.holdBar").exists) starts \(before2)->\(el("debug.dictationStarts").value ?? "-") menu=\(menu2)")
        XCTAssertFalse(el("composer.holdBar").exists, "no hold bar on the empty field")
        XCTAssertEqual(el("debug.dictationStarts").value as? String, before2, "no dictation started on the empty field")
        // Paste on an empty field isn't ours to promise (iOS 27 showed no menu there): logged above, not asserted.
    }

    /// The edit menu's items: `menuItems`, and Paste, Select or Copy as buttons too (iOS 27's edit menu may draw them so);
    /// both reads logged.
    private func editMenu() -> [String] {
        let items = app.menuItems.allElementsBoundByIndex.map(\.label)
        let buttons = ["Paste", "Select", "Select All", "Copy"].filter { app.buttons[$0].firstMatch.exists }
        say("EDITMENU menuItems=\(items) buttons=\(buttons)")
        return Array(Set(items + buttons)).sorted()
    }

    // MARK: 7. The latched mic

    func testLatchedMic() throws {
        try launch(); try openChat()
        let words = fakeWords
        app.buttons["Dictate"].firstMatch.tap(); pause(0.5)
        XCTAssertTrue(el("composer.dictationBar").waitForExistence(timeout: 5), "the latched bar")
        XCTAssertFalse(el("composer.send").exists, "no send in the latched bar")
        el("composer.dictation.cancel").tap(); pause(1.0)
        say("LATCHED cancel pill=\(el("composer.pill").exists) sent=\(sentCount(words))")
        XCTAssertTrue(el("composer.pill").exists, "the pill after ✕")
        app.buttons["Dictate"].firstMatch.tap(); pause(0.5)
        app.buttons["Stop dictating"].firstMatch.tap(); pause(1.5)
        let value = el("composer.text").value as? String ?? ""
        say("LATCHED stop words=\(value) sent=\(sentCount(words))")
        XCTAssertEqual(value, words, "the words in the field")
        XCTAssertEqual(sentCount(words), 0, "not sent (Send after dictation off)")
    }

    // MARK: 8 and 9. Voice mode, and the running pill

    func testVoiceModeButton() throws {
        try launch(); try openChat()
        el("composer.voiceMode").tap()
        let hide = app.buttons["Hide voice mode"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 10), "voice mode's screen")
        app.buttons["End voice mode"].firstMatch.tap(); pause(1.0)
        sendDemoMessage()
        let stop = app.buttons["Stop"].firstMatch
        say("VOICE running voiceMode=\(el("composer.voiceMode").exists) stop=\(stop.exists)")
        XCTAssertFalse(el("composer.voiceMode").exists, "no voice mode while a reply runs")
        XCTAssertTrue(stop.exists, "the reply's stop")
        stop.tap(); pause(1.0)
    }

    func testRunningPill() throws {
        try launch(["-vory-demo-slow"]); try openChat()   // a reply of about 25 s (DEBUG, DemoLive's slowness)
        sendDemoMessage()
        try requireRunning("the pill's placeholder")
        let placeholder = el("composer.pill").value as? String ?? ""
        say("RUNNING placeholder=\(placeholder)")
        XCTAssertEqual(placeholder, "Sends after this reply")
        // Straight on, while the reply (about 5 s, DemoContent.everyday) still runs.
        el("composer.pill").tap()
        _ = el("composer.text").waitForExistence(timeout: 2)
        el("composer.text").typeText("w")
        try requireRunning("the card's queue")
        say("RUNNING card queue=\(app.buttons["Queue message"].exists) steer=\(app.buttons["Steer now"].exists)")
        XCTAssertTrue(app.buttons["Queue message"].exists && app.buttons["Steer now"].exists, "the card's queue and steer")
    }

    /// A demo message sent from the card; the demo keeps the keyboard down after a send, so the bar is back at rest
    /// (59's pill, 57's card), the reply running.
    /// Before the tap, Send's frame the same across two reads 0.1 s apart (up to 2 s, logged), since a tap while the
    /// card settles is lost now and then on the iPad, 57 and 59 alike (#711). The fast tap keeps its own record in
    /// testSendProbe's A0 cases.
    private func sendDemoMessage(_ words: String = "Hello") {
        if base57 { el("composer.text").tap(); pause(1.0) } else { focusFromPill() }
        el("composer.text").typeText(words)
        let send = el("composer.send"), t0 = Date()
        var last = send.exists ? send.frame : .null, settled = false
        while Date().timeIntervalSince(t0) < 2 {
            pause(0.1)
            let now = send.exists ? send.frame : .null
            if !now.isNull, now == last { settled = true; break }
            last = now
        }
        say("SEND settle \(settled ? "same frame" : "not settled in 2 s") after \(String(format: "%.2f", Date().timeIntervalSince(t0)))s at \(last.isNull ? "-" : f(last))")
        send.tap()
        _ = (base57 ? el("composer.text") : el("composer.pill")).waitForExistence(timeout: 5)
        pause(0.2)
    }

    // MARK: 10. The audit (59, or 57's card with REPLYBAR_BASE=57)

    func testAudit() throws {
        try launch(["-vory-demo-slow"]); try openChat()   // the running states' replies still running
        // The placeholder's words (both states), to find what the audit sees as a text of its own.
        let words = ["Reply or hold to talk", "Sends after this reply"]
        func audit(_ state: String) {
            // Every element carrying the placeholder's words, by label or value, before the audit.
            let same = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@ OR value IN %@", words, words)).allElementsBoundByIndex
            say("AUDIT \(state) PLACEHOLDER \(same.count): " + same.map {
                "type \($0.elementType.rawValue) id=\($0.identifier.isEmpty ? "-" : $0.identifier) label=\($0.label) frame=\(f($0.frame))"
            }.joined(separator: "; "))
            // With the inner Text hidden, composer.pill alone carries the words.
            let others = same.filter { $0.identifier != "composer.pill" }
            if !others.isEmpty {
                say("AUDIT \(state) PLACEHOLDER DUPLICATE: \(others.count) element(s) beside composer.pill still carry the words")
                // Where the duplicate sits: composer.pill's own tree (its children), and its parent's, one line each.
                let flat = { (s: String) in s.replacingOccurrences(of: "\n", with: " | ") }
                say("AUDIT \(state) TREE pill: " + flat(el("composer.pill").debugDescription))
                say("AUDIT \(state) TREE dup: " + flat(others[0].debugDescription))
                let parent = app.descendants(matching: .any).containing(.any, identifier: "composer.pill")
                    .matching(NSPredicate(format: "identifier != 'composer.pill'")).allElementsBoundByIndex.last
                say("AUDIT \(state) TREE parent: " + (parent.map { flat($0.debugDescription) } ?? "none"))
            }
            else if same.count == 1 { say("AUDIT \(state) PLACEHOLDER ok: composer.pill alone") }
            do {
                try app.performAccessibilityAudit { issue in
                    let e = issue.element
                    let who = e.map { "\($0.identifier.isEmpty ? "-" : $0.identifier)/\($0.label.isEmpty ? "-" : $0.label)" } ?? "no element"
                    self.say("AUDIT \(state) ISSUE \(issue.auditType) | \(who) | \(issue.compactDescription)")
                    // The full description (the measured ratio or size, if it gives one) and the element's frame,
                    // for the placeholder's issues and for any clipped or contrast issue with no element.
                    let mine = e.map { words.contains($0.label) } ?? false
                    let typed = issue.auditType == .contrast || issue.auditType == .textClipped
                    if typed, mine || e == nil {
                        let place = e.map { "type \($0.elementType.rawValue) frame \(self.f($0.frame))" } ?? "no element"
                        self.say("AUDIT \(state) DETAIL \(issue.auditType.rawValue) | \(place) | "
                                 + issue.detailedDescription.replacingOccurrences(of: "\n", with: " "))
                    }
                    return true
                }
            } catch { say("AUDIT \(state) ERROR \(error)") }
            say("AUDIT \(state) done")
        }
        audit(base57 ? "card-rest" : "pill")
        if base57 { el("composer.text").tap(); pause(1.0) } else { focusFromPill() }
        audit("card")
        try dismissKeyboard()
        if !base57 {
            app.buttons["Dictate"].firstMatch.tap(); pause(0.5); audit("latched"); el("composer.dictation.cancel").tap(); pause(0.5)
        }
        sendDemoMessage()
        audit(base57 ? "card-running" : "pill-running")
        // The running audit takes longer than the demo's reply, so the queue gets a reply of its own; VOID, not a stop.
        sendDemoMessage()
        do { try queueOne(); audit("queued") } catch { say("AUDIT queued VOID: \(error)") }
        _ = app.buttons["Stop"].firstMatch.waitForExistence(timeout: 2) ? app.buttons["Stop"].firstMatch.tap() : ()
        pause(1.0)
        // The demo's one approval: a message about disk space asks for it (DemoLive.approvalDue).
        sendDemoMessage("Please clean up some disk space")
        if app.buttons["Allow once"].firstMatch.waitForExistence(timeout: 30) { audit("approval") } else { say("AUDIT approval VOID: no card in 30 s") }
        if app.buttons["Deny"].firstMatch.exists { app.buttons["Deny"].firstMatch.tap(); pause(1.0) }
        // The Voice page's audit only on the Voice page.
        if openSettingsVoice() { audit("settings-voice") } else { say("AUDIT settings-voice VOID: not on the Voice page") }
    }

    /// One message queued behind the running reply: typed in the card, sent with "Queue message".
    private func queueOne() throws {
        (base57 ? el("composer.text") : el("composer.pill")).tap()
        _ = el("composer.text").waitForExistence(timeout: 2)
        el("composer.text").typeText("Later")
        try requireRunning("the queue")
        // "Queue message" itself, not just a running reply (Stop can be there while Queue message isn't).
        let queue = app.buttons["Queue message"].firstMatch
        if !queue.waitForExistence(timeout: 1) {
            let labels = el("chat.dock").descendants(matching: .button).allElementsBoundByIndex.map { $0.label.isEmpty ? $0.identifier : $0.label }
            say("VOID the queue: no Queue message in 1 s; the dock's buttons \(labels)")
            throw XCTSkip("no Queue message button")
        }
        queue.tap(); pause(1.0)
        say("QUEUED strip=\(el("queue.edit").exists)")
    }

    /// Settings › Voice, through the tab bar's Settings and its Voice row. True only on the Voice page.
    private func openSettingsVoice() -> Bool {
        // From a chat, its own Back first (the phone's tab bar is hidden in a pushed chat, with tab.settings below the
        // window).
        let back = app.buttons.matching(identifier: "chat.back").firstMatch
        if back.exists, !el("tab.settings").isHittable { back.tap(); pause(1.0) }
        // The Settings tab once it's hittable (up to 2 s), then the Voice row by its own id, `settings.row.voice`
        // (SettingsView: `Row(id: "voice", ...)` with `.accessibilityIdentifier("settings.row.\(row.id)")`), up to 3 s. No
        // label search: a CONTAINS search can find the chat list's Voice chat (if the tab hasn't opened) and tap it.
        let tab = el("tab.settings"), t0 = Date()
        while !tab.isHittable, Date().timeIntervalSince(t0) < 2 { pause(0.1) }
        say("SETTINGS tab hittable=\(tab.isHittable) \(f(tab.frame))")
        // Nothing is tapped unless the tab is hittable.
        guard tab.isHittable else { say("VOID settings: tab.settings not hittable after 2 s; nothing tapped"); return false }
        tab.tap(); pause(1.0)
        // The Settings page's own mark first (its first row, `settings.row.gateways`), up to 3 s. Then the Voice row:
        // it's the ninth of the App section, below the Gateway and Hermes sections, so on a phone it's below the fold
        // and the List may not have made it yet. Up to six swipes up on the list, a drag only (no tap), until it's
        // hittable. The list is the one that holds the Settings page's own first row (on the iPad,
        // collectionViews.firstMatch can be the sidebar's); none, VOID, with no swipe anywhere else.
        guard el("settings.row.gateways").waitForExistence(timeout: 3) else {
            say("VOID settings: no settings.row.gateways (the Settings page didn't open); nothing else tapped"); return false
        }
        let row = el("settings.row.voice")
        // The list is found once, before any swipe, and its frame kept: the query re-resolves on each use, and once
        // settings.row.gateways scrolls away the List may drop it, so `containing` would find no list after a swipe. Each
        // swipe is a drag inside that frame, from 75% of its height to 25%, at its middle.
        let list = app.collectionViews.containing(.any, identifier: "settings.row.gateways").firstMatch
        guard list.exists else {
            say("VOID settings: no list holding settings.row.gateways to swipe; nothing else tapped"); return false
        }
        let lf = list.frame, origin = app.coordinate(withNormalizedOffset: .zero)
        say("SETTINGS list \(f(lf))")
        var swipes = 0
        while !(row.exists && row.isHittable), swipes < 6 {
            let from = origin.withOffset(CGVector(dx: lf.midX, dy: lf.minY + lf.height * 0.75))
            let to = origin.withOffset(CGVector(dx: lf.midX, dy: lf.minY + lf.height * 0.25))
            from.press(forDuration: 0.05, thenDragTo: to)
            swipes += 1; pause(0.5)
        }
        guard row.exists, row.isHittable else {
            say("VOID settings: settings.row.voice not hittable after \(swipes) swipes; nothing else tapped"); return false
        }
        say("SETTINGS row found after \(swipes) swipes")
        say("SETTINGS row \(row.identifier) label=\(row.label) \(f(row.frame))")
        row.tap(); pause(1.0)
        // The Voice page's own mark, up to 3 s: without it the page isn't Voice's, so no footer read and no audit of it.
        // Its first section's "Read replies aloud" switch (VoiceSettingsView, the Chats section, the same section as
        // the footer read below). The Live provider menu (`voice.liveProvider`) is in its third section, below the
        // phone's fold, where the List may not have made it.
        guard app.switches["Read replies aloud"].firstMatch.waitForExistence(timeout: 3) else {
            say("VOID settings: no Read replies aloud switch after settings.row.voice (not the Voice page)"); return false
        }
        say("SETTINGS on the Voice page (Read replies aloud found)")
        say("SETTINGS voice footer=\(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Holding the message bar'")).count)")
        return true
    }

    // MARK: 11. The largest text

    func testLargeText() throws {
        try launch(["-vory-demo-slow"]); try openChat()   // slow demo reply; run with R59_SIZE=UICTContentSizeCategoryAccessibilityXXXL
        let dock = el("chat.dock").frame
        for id in ["composer.attach", "composer.voiceMode", "composer.pill"] {
            let e = el(id)
            say("LARGE \(id) exists=\(e.exists) hittable=\(e.isHittable) frame=\(f(e.frame)) inDock=\(dock.contains(e.frame))")
            XCTAssertTrue(e.exists && e.isHittable, "\(id) hittable at AX5")
        }
        XCTAssertTrue(app.buttons["Dictate"].firstMatch.isHittable, "the mic hittable at AX5")
        // A message queued, then another typed: Send ("Queue message") hittable, no worse than on 57.
        sendDemoMessage(); try queueOne()
        // The queue puts the keyboard away in the demo (#490), so the bar is the pill again: tap it before typing.
        if !base57, el("composer.pill").exists { el("composer.pill").tap(); _ = el("composer.text").waitForExistence(timeout: 2) }
        el("composer.text").typeText("More")
        try requireRunning("the second queue")
        let queueSend = app.buttons["Queue message"].firstMatch
        say("LARGE queueSend exists=\(queueSend.exists) hittable=\(queueSend.isHittable) frame=\(f(queueSend.frame))")
        // The approval: Allow once visible and hittable, from a fresh launch. The demo asks once per launch
        // (DemoLive.approvalDue: the first message about space or a cleanup, or a chat's second message, then
        // approvalAsked), so in this launch an earlier turn ("Hello" or the queued "Later") could take it, and a Stop tap
        // would cut that turn, leaving the cleanup message the everyday turn. No Stop is tapped. The relaunch keeps the
        // slow flag and the size; its first message is the cleanup ask, sent from the pill.
        try launch(["-vory-demo-slow"]); try openChat()
        sendDemoMessage("Please clean up some disk space")
        let allow = app.buttons["Allow once"].firstMatch
        // Right after the send, what the bar and thread show (a reply running, the last user row), then up to 60 s
        // (the slow demo's turn takes about five times as long to reach its approval).
        let lastUser = app.descendants(matching: .any).matching(identifier: "thread.row.user").allElementsBoundByIndex.last
        // The slow flag stays for this test: queueOne's requireRunning("the queue") and the second queue's
        // requireRunning need a reply still running (without the flag the reply ends first and they VOID).
        say("LARGE after the send: stop=\(app.buttons["Stop"].firstMatch.exists) queue=\(app.buttons["Queue message"].firstMatch.exists) last user row=\(lastUser.map { $0.label.prefix(60) } ?? "none") dock \(f(el("chat.dock").frame))")
        let came = allow.waitForExistence(timeout: 60)
        say("LARGE allowOnce came=\(came) hittable=\(came && allow.isHittable) frame=\(came ? f(allow.frame) : "-")")
        XCTAssertTrue(came && allow.isHittable, "Allow once visible and hittable at AX5")
        if app.buttons["Deny"].firstMatch.exists { app.buttons["Deny"].firstMatch.tap() }
    }

    // MARK: 12. The placeholder fits

    /// At the default size the words fit on one line (asserted). At an accessibility size (R59_SIZE) the FIT line is a recorded read: the words end in an ellipsis inside the
    /// placeholder's own frame (lineLimit(1), truncationMode(.tail)). There, the read is the frames of the pill, attach,
    /// voice mode and the mic, and two checks: the pill overlaps neither the mic nor voice mode (A), and the pill's
    /// value is the full words (B).
    func testPlaceholderFits() throws {
        try launch(["-vory-pill-fit"]); try openChat()
        let fit = el("debug.pillFit").value as? String ?? "unread"
        let pill = el("composer.pill")
        say("FIT \(fit) placeholder=\(pill.value ?? "-")")
        guard !(env["R59_SIZE"] ?? "").isEmpty else {
            XCTAssertTrue(fit.hasPrefix("fits"), "the resting placeholder on one line: \(fit)")
            return
        }
        let attach = el("composer.attach"), voice = el("composer.voiceMode"), mic = app.buttons["Dictate"].firstMatch
        func fr(_ e: XCUIElement) -> String { e.exists ? f(e.frame) : "-" }
        say("FIT AX frames pill=\(fr(pill)) attach=\(fr(attach)) voiceMode=\(fr(voice)) mic=\(fr(mic))")
        let overlapsMic = pill.exists && mic.exists && pill.frame.intersects(mic.frame)
        let overlapsVoice = pill.exists && voice.exists && pill.frame.intersects(voice.frame)
        say("FIT AX check A: pill overlaps mic=\(overlapsMic) voiceMode=\(overlapsVoice)")
        XCTAssertTrue(pill.exists && mic.exists && voice.exists, "the pill, the mic and voice mode at the accessibility size")
        XCTAssertFalse(overlapsMic || overlapsVoice, "the pill clear of the mic and voice mode at the accessibility size")
        let value = pill.value as? String ?? ""
        let full = "Reply or hold to talk"   // ReplyBarRules.restPlaceholder (the app's; a UI test can't import it)
        say("FIT AX check B: pill value=\"\(value)\" full=\(value == full)")
        XCTAssertEqual(value, full, "the pill's value is the full words at the accessibility size")
    }

    // MARK: 16. The approval card's follow (#437)

    /// The dock's approval card. The show chat (the demo's first, taller than the screen) at its end, 2 s at rest after
    /// it's shown (the SHOWN line comes before the first MARK). The pill tapped, the message that asks for the demo's one
    /// approval typed and sent; the keyboard goes down and the card takes the pill's place. Allow once and Deny there,
    /// then 1.5 s with no touch; then the answer (R59_APPROVAL: deny or allow, one launch each), 1.5 s, and after Allow
    /// once the turn's end too. MARKs at card-in and card-out with the dock's frame. No assertion: the read is each DOCK
    /// change, the GEO lines in its update and the next 150 ms, and every POS and SETTLE line between the MARKs.
    func testApprovalFollow() throws {
        let answer = env["R59_APPROVAL"] == "allow" ? "Allow once" : "Deny"
        try launch(["-vory-geometry-log"]); try openChat()
        pause(2.0)
        say("MARK rest dock \(f(el("chat.dock").frame))")
        sendDemoMessage("Please clean up some disk space")
        let allow = app.buttons["Allow once"].firstMatch, deny = app.buttons["Deny"].firstMatch
        guard allow.waitForExistence(timeout: 30), deny.exists else { say("VOID approval: no card in 30 s"); throw XCTSkip("no approval card") }
        say("MARK card-in dock \(f(el("chat.dock").frame)) keyboard=\(keyboardUp)")
        pause(1.5)
        say("MARK answer \(answer)")
        app.buttons[answer].firstMatch.tap()
        // Polled, every 0.1 s: the card gone (up to 3 s); after Allow once, the turn's Stop gone (up to 30 s).
        func waitGone(_ e: XCUIElement, _ limit: Double) { let t0 = Date(); while e.exists, Date().timeIntervalSince(t0) < limit { pause(0.1) } }
        waitGone(allow, 3)
        say("MARK card-out dock \(f(el("chat.dock").frame)) card=\(allow.exists)")
        pause(1.5)
        if answer == "Allow once" {
            let stop = app.buttons["Stop"].firstMatch
            waitGone(stop, 30)
            say("MARK turn-end running=\(stop.exists)")
        }
        say("MARK done dock \(f(el("chat.dock").frame))")
    }

    // MARK: 17. A reader scrolled up stays put when the dock grows

    /// The thread dragged well away from its end (down 300 pt), then the pill tapped: the card grows the dock and the
    /// keyboard comes up. The reader isn't pulled to the end: the GEO offset between the MARKs must hold, and no POS
    /// comes from the inset follow. Here, a row's place before and after, logged as a second read. No assertion: it
    /// should hold either way, since the inset follow's first guard is stickToBottom.
    func testScrolledUpHolds() throws {
        try launch(["-vory-geometry-log"]); try openChat()
        let win = app.windows.firstMatch, dock = el("chat.dock").frame
        let from = win.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: win.frame.midX, dy: dock.minY - 380))
        let to = win.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: win.frame.midX, dy: dock.minY - 80))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        pause(1.0)
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'thread.row.'")).allElementsBoundByIndex
        // The topmost row whose top is in the band (below the header, 40 pt above the dock), whatever its height (the
        // demo's reply row can be 676 pt tall and run past the dock).
        let header = el("chat.header").exists ? el("chat.header").frame.maxY : 140
        guard let row = rows.filter({ $0.frame.minY > header && $0.frame.minY < dock.minY - 40 }).min(by: { $0.frame.minY < $1.frame.minY }) else {
            say("VOID scrolled-up: no row below \(Int(header)) and above \(Int(dock.minY)); rows: "
                + rows.map { "\($0.identifier) \(f($0.frame))" }.joined(separator: "; "))
            throw XCTSkip("no row to watch")
        }
        let before = row.frame
        say("MARK scrolled-up row \(row.identifier) \(f(before))")
        el("composer.pill").tap(); pause(1.5)
        let after = row.frame
        say("MARK scrolled-up after-tap row \(row.identifier) \(f(after)) moved \(String(format: "%.1f", after.minY - before.minY)) keyboard=\(keyboardUp)")
    }

    // MARK: 18. The placeholder's element, bisected

    /// One launch per variant of the pill's accessibility (R59_PILL_AX, 0 for today's, 1 to 4 for the app's DEBUG
    /// `-vory-pill-ax <n>`): the chat at rest, then every element carrying the words, the pill's own tree, its label and
    /// value, and an audit of the pill state with the issues that name the words. No assertion: the variant whose line reads
    /// "PLACEHOLDER ok" with label Message and the words still in the value (or the hint, for 3) is the fix.
    func testPillAXProbe() throws {
        let n = env["R59_PILL_AX"] ?? "0"
        try launch(n == "0" ? [] : ["-vory-pill-ax", n]); try openChat()
        let words = ["Reply or hold to talk", "Sends after this reply"]   // the rest words
        let same = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@ OR value IN %@", words, words)).allElementsBoundByIndex
        let others = same.filter { $0.identifier != "composer.pill" }
        let pill = el("composer.pill")
        say("AXPROBE \(n) PLACEHOLDER \(others.isEmpty && same.count == 1 ? "ok" : "DUPLICATE \(others.count)") pill exists=\(pill.exists) label=\(pill.label) value=\(pill.value ?? "-") type \(pill.elementType.rawValue)")
        say("AXPROBE \(n) TREE pill: " + pill.debugDescription.replacingOccurrences(of: "\n", with: " | "))
        do {
            try app.performAccessibilityAudit { issue in
                let label = issue.element?.label ?? ""
                if words.contains(label) || issue.element?.identifier == "composer.pill" {
                    self.say("AXPROBE \(n) ISSUE \(issue.auditType.rawValue) | \(issue.element?.identifier ?? "-")/\(label) | \(issue.compactDescription)")
                }
                return true
            }
        } catch { say("AXPROBE \(n) AUDIT ERROR \(error)") }
        say("AXPROBE \(n) done")
    }

    // MARK: 19. The keyboard with a draft: the card stays a card

    /// A draft in the field, so the bar is the card up and down (no pill swap): the keyboard up and down three times, each
    /// MARKed, for a read of the GEO, POS, DOCK, SETTLE and KB lines between them (dist 0 in one step, as 57 or better).
    /// On 59 and on 57 (REPLYBAR_BASE=57). No assertion.
    func testDraftKeyboard() throws {
        try launch(["-vory-geometry-log"]); try openChat()
        let restTop = el("chat.dock").frame.minY
        if base57 { el("composer.text").tap(); pause(1.0) } else { focusFromPill() }
        requireKeyboard("the draft")
        el("composer.text").typeText("Draft")
        // The dock at its keyboard place before the dismiss reads it (read at its resting place with the keyboard up, the
        // tap would land under the keyboard). Polled every 0.1 s, up to 2 s.
        let t0 = Date()
        while el("chat.dock").frame.minY > restTop - 100, Date().timeIntervalSince(t0) < 2 { pause(0.1) }
        say("DRAFT dock before the dismiss \(f(el("chat.dock").frame)) rest top \(Int(restTop)) keyboard=\(keyboardUp)")
        try dismissKeyboard()
        say("MARK draft-rest dock \(f(el("chat.dock").frame)) pill=\(el("composer.pill").exists)")
        pause(1.0)
        for n in 1...3 {
            say("MARK draft-up-\(n)"); el("composer.text").tap(); pause(1.5)
            say("MARK draft-down-\(n) dock \(f(el("chat.dock").frame)) keyboard=\(keyboardUp)"); try dismissKeyboard(); pause(1.0)
        }
        say("MARK done dock \(f(el("chat.dock").frame)) pill=\(el("composer.pill").exists)")
    }

    // MARK: 20. The keyboard from a reply-to strip and an edit strip

    /// R59_STRIP=reply: a user bubble's menu, Reply (the quote strip over the card). R59_STRIP=edit: the last user
    /// bubble's menu, Edit & resend (the editing strip, its words in the field). The bubble pressed 1 s at its trailing
    /// part (40 pt in from the row's trailing edge, at its middle); the menu's item tapped; then the keyboard up and down
    /// twice, each MARKed, for the log's read. The card stays a card throughout (a quote or the editing strip). On 59 and
    /// on 57. A missing menu item is a VOID with the menu's buttons listed. No assertion.
    func testStripKeyboard() throws {
        let kind = env["R59_STRIP"] == "edit" ? "edit" : "reply"
        let item = kind == "edit" ? "Edit & resend" : "Reply"
        try launch(["-vory-geometry-log"]); try openChat()
        let rows = app.descendants(matching: .any).matching(identifier: "thread.row.user").allElementsBoundByIndex
            .filter { $0.frame.minY > 130 && $0.frame.maxY < el("chat.dock").frame.minY }
        guard let row = (kind == "edit" ? rows.max(by: { $0.frame.minY < $1.frame.minY }) : rows.first) else {
            say("VOID strip: no user row on screen"); throw XCTSkip("no user row")
        }
        let win = app.windows.firstMatch
        win.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: row.frame.maxX - 40 - win.frame.minX, dy: row.frame.midY - win.frame.minY))
            .press(forDuration: 1.0)
        let button = app.buttons[item].firstMatch
        guard button.waitForExistence(timeout: 3) else {
            say("VOID strip \(kind): no \(item) in the menu; buttons \(app.buttons.allElementsBoundByIndex.prefix(20).map { $0.label })")
            throw XCTSkip("no \(item)")
        }
        button.tap(); pause(1.5)
        let strip = kind == "edit" ? el("composer.editing") : el("composer.cancelReply")
        say("MARK strip-in \(kind) strip=\(strip.exists) dock \(f(el("chat.dock").frame)) keyboard=\(keyboardUp)")
        if keyboardUp { try dismissKeyboard(); pause(1.0) }
        for n in 1...2 {
            say("MARK strip-up-\(n)"); el("composer.text").tap(); pause(1.5)
            say("MARK strip-down-\(n) dock \(f(el("chat.dock").frame)) keyboard=\(keyboardUp)"); try dismissKeyboard(); pause(1.0)
        }
        say("MARK done dock \(f(el("chat.dock").frame)) strip=\(strip.exists)")
    }

    // MARK: 21. The half-open Duo (#669's laptop pose): the dock and the fold

    /// The Duo half open, upright (opened, then half). The fold from the app's own readout
    /// (`-vory-geometry-probe`, `geometry.regions`, as Fold669UITests reads it); none across the window is a VOID. At rest:
    /// the dock and its gap from the fold. The pill tapped: the dock's top sampled until the keyboard is up (no lift
    /// before the keyboard). Up: the dock and its gap (lifted over the fold). The keyboard down by the user-row dismiss:
    /// the dock back at its resting place (no lift). MARKed for a read of the DOCK, GEO, POS and KB lines. No assertion.
    func testFoldLift() throws {
        try launch(["-vory-geometry-log", "-vory-geometry-probe"]); try openChat()
        let readout = app.staticTexts["geometry.regions"].firstMatch
        guard readout.waitForExistence(timeout: 20) else { say("VOID fold: no geometry.regions readout"); throw XCTSkip("no readout") }
        guard let fold = FoldPoseUITests.activeFolds(in: readout.label).first(where: { $0.width > $0.height }) else {
            say("VOID fold: no active fold across the window (the Duo isn't half open, upright)"); throw XCTSkip("no fold")
        }
        func gap(_ r: CGRect) -> Int { Int(max(fold.minY - r.maxY, r.minY - fold.maxY)) }
        func on(_ r: CGRect) -> String { r.intersects(fold) ? " ON THE FOLD" : "" }
        say("FOLD fold \(f(fold)) window \(f(app.windows.firstMatch.frame))")
        // The chat at its end before the pill's tap, so the keyboard's rise is read from the end.
        say("MARK fold-end at end=\(scrollToEnd())")
        pause(1.0)
        let rest = el("chat.dock").frame
        say("MARK fold-rest dock \(f(rest)) gap \(gap(rest))\(on(rest))")
        say("MARK fold-tap")
        el("composer.pill").tap()
        var tops: [String] = []; let t0 = Date()
        while !keyboardUp, Date().timeIntervalSince(t0) < 2 {
            tops.append(String(format: "%.2f:%d", Date().timeIntervalSince(t0), Int(el("chat.dock").frame.minY))); pause(0.05)
        }
        say("FOLD before the keyboard: dock tops \(tops.joined(separator: " "))")
        pause(1.0)
        let up = el("chat.dock").frame
        say("MARK fold-up dock \(f(up)) gap \(gap(up)) keyboard=\(keyboardUp)\(on(up))")
        try dismissKeyboard()
        pause(1.0)
        let down = el("chat.dock").frame
        say("MARK fold-down dock \(f(down)) gap \(gap(down)) at rest=\(abs(down.minY - rest.minY) < 1)\(on(down))")
        say("MARK done")
    }

    // MARK: 22. The keyboard at the chat's end

    /// The chat brought to its end first (drags until the last row stands still), then one rise and one dismiss: the
    /// thread at its end stays there, dist 0 in one step. `-vory-geometry-log` for the GEO, DOCK, KB and SETTLE lines;
    /// every step MARKed, so the lines between the MARKs show the "KB skip at end" count. No assertion.
    func testKeyboardAtEnd() throws {
        try launch(["-vory-geometry-log"]); try openChat()
        let atEnd = scrollToEnd()
        pause(1.0)
        say("MARK end at end=\(atEnd) dock \(f(el("chat.dock").frame))")
        if base57 { el("composer.text").tap() } else { el("composer.pill").tap() }
        say("MARK rise-tap")
        let t0 = Date()
        while !keyboardUp, Date().timeIntervalSince(t0) < 3 { pause(0.05) }
        requireKeyboard("the rise at the end")
        pause(1.5)
        say("MARK risen dock \(f(el("chat.dock").frame)) keyboard=\(keyboardUp) \(keyboardRead)")   // the keyboard's frame
        try dismissKeyboard()
        pause(1.0)
        say("MARK dismissed dock \(f(el("chat.dock").frame)) keyboard=\(keyboardUp)")
        say("MARK done")
    }

    // MARK: 15. The placeholder's contrast: measured, not asserted

    /// The audit no longer looks at the placeholder's words once they're hidden as a text of their own (as with 57's
    /// field), so their contrast is measured here: light and dark, over the thread at rest (stuck to its end, nothing
    /// behind the pill) and over a busy backdrop (the thread dragged down 160 pt so its last rows sit behind the pill; the
    /// rows behind it are logged). From a screenshot, cropped to the words: the background is the median pixel by
    /// luminance, the text the pixel farthest from it in luminance (the strokes' core); the WCAG ratio from sRGB
    /// linearized. The crop goes to the result bundle only (an attachment, kept local). No assertion: the ratios are read.
    func testPlaceholderContrast() throws {
        for scheme in ["light", "dark"] {
            try launch(scheme: scheme); try openChat()
            measureContrast(scheme, "plain")
            let win = app.windows.firstMatch, dock = el("chat.dock").frame
            let from = win.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: win.frame.midX, dy: dock.minY - 260))
            let to = win.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: win.frame.midX, dy: dock.minY - 100))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            pause(1.0)
            let behind = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'thread.row.'"))
                .allElementsBoundByIndex.filter { $0.frame.intersects(dock) }.map { "\($0.identifier) \(f($0.frame))" }
            say("CONTRAST \(scheme) busy behind the dock: \(behind.isEmpty ? "no row" : behind.joined(separator: "; "))")
            measureContrast(scheme, "busy")
        }
    }

    private func measureContrast(_ scheme: String, _ backdrop: String) {
        // On 57 (REPLYBAR_BASE=57) the card's field, its placeholder drawn at the field's leading edge, one line.
        let target = base57 ? "composer.text" : "composer.pill"
        let pill = el(target).frame, winW = app.windows.firstMatch.frame.width
        guard pill.width > 20, let shot = XCUIScreen.main.screenshot().image.cgImage else {
            say("CONTRAST \(scheme) \(backdrop) VOID: no \(target) or no screenshot"); return
        }
        // Points to pixels by the screenshot's own width against the window's.
        let s = CGFloat(shot.width) / winW
        // The words: 59's from the text's 4 pt padding, 57's from the field's leading edge; 150 pt along (59's words are
        // about 164 wide), 20 pt tall about the middle (57's field is one line at rest).
        let lead: CGFloat = base57 ? 0 : 4
        let area = CGRect(x: pill.minX + lead, y: pill.midY - 10, width: min(150, pill.width - 2 * lead), height: 20)
        say("CONTRAST \(scheme) \(backdrop) target \(target) \(f(pill))")
        let px = CGRect(x: area.minX * s, y: area.minY * s, width: area.width * s, height: area.height * s).integral
        guard let crop = shot.cropping(to: px) else { say("CONTRAST \(scheme) \(backdrop) VOID: no crop \(f(px))"); return }
        let w = crop.width, h = crop.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buf in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn, w * h > 0 else { say("CONTRAST \(scheme) \(backdrop) VOID: no pixels"); return }
        func lin(_ c: UInt8) -> Double { let v = Double(c) / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func lum(_ i: Int) -> Double { 0.2126 * lin(bytes[i]) + 0.7152 * lin(bytes[i + 1]) + 0.0722 * lin(bytes[i + 2]) }
        let pixels = (0..<(w * h)).map { (i: $0 * 4, l: lum($0 * 4)) }.sorted { $0.l < $1.l }
        let bg = pixels[pixels.count / 2]
        let text = abs(pixels.first!.l - bg.l) >= abs(pixels.last!.l - bg.l) ? pixels.first! : pixels.last!
        let ratio = (max(bg.l, text.l) + 0.05) / (min(bg.l, text.l) + 0.05)
        func rgb(_ i: Int) -> String { "(\(bytes[i]),\(bytes[i + 1]),\(bytes[i + 2]))" }
        say(String(format: "CONTRAST %@ %@ ratio=%.2f text=%@ bg=%@ crop=%@ scale=%.2f", scheme, backdrop, ratio, rgb(text.i), rgb(bg.i), f(area), s))
        let shotOf = XCTAttachment(image: UIImage(cgImage: crop))
        shotOf.name = "contrast-\(scheme)-\(backdrop)"; shotOf.lifetime = .keepAlways
        add(shotOf)
    }

    // MARK: 14. The tap probe: the focusing tap's speed, and whether the thread's tap closes

    /// One focusing tap, timed (TAPTIME), then the thread's dismiss tap once, and whether the keyboard closed (TAPCLOSE).
    /// Run on 59 and on 57. No assertion: a recorded read. A tap that doesn't close is the dismiss's VOID.
    func testTapProbe() throws {
        try launch(); try openChat()
        for n in 1...3 {
            timedFocus("probe \(n)")
            say("KEYBOARD probe \(n) base=\(base57 ? 57 : 59) dock \(f(el("chat.dock").frame)) \(keyboardRead)")
            try dismissKeyboard()
            say("TAPCLOSE probe \(n) base=\(base57 ? 57 : 59) closed=\(!keyboardUp)")
        }
    }

    // MARK: 13. The model chip as 57's

    func testModelChipAsFiftySeven() throws {
        try launch(); try openChat()
        if base57 { el("composer.text").tap(); pause(1.0) } else { focusFromPill() }
        let chip = el("composer.modelChip"), dock = el("chat.dock").frame
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the model chip in the card")
        let r = chip.frame.offsetBy(dx: -dock.minX, dy: -dock.minY)
        say("CHIP base=\(base57 ? 57 : 59) inDock=\(f(r)) label=\(chip.label)")
        chip.tap(); pause(0.8)
        say("CHIP menu model=\(app.staticTexts["Model"].exists || app.buttons["Model"].exists)")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
    }

    // MARK: 15. The send probe: whether a typed message sends, and how soon after typing

    /// On the iPad, Send tapped right after typing (sendDemoMessage's typeText, then the tap) can send nothing, while
    /// taps several seconds after typing send (the app's "slash: send <text>"). Five messages, each on a fresh launch's
    /// card:
    ///   A0a, A0b, A0c: the tests' own path, typeText then the tap with no wait (three times);
    ///   A: the tap 1.2 s after typeText returns; B: 3.0 s after.
    /// A0a and A0b keep sendDemoMessage's pace exactly, typeText then the tap with no query between (one query can push
    /// the tap past Send's first-second move). A0c, A and B read Send's frame after typeText ("typed"; Send can sit well
    /// above its settled place then); A and B read it once more at their wait, then tap.
    /// Every case reads it again right after the tap ("tapped"), so a frame that moved during the tap shows. Everything
    /// else (hittable, enabled, the dock, the keyboard, the field, the pill, the rows) comes after the tap's +1 s. No
    /// retry, no assertion: each gap shows in XCTest's Type and Tap lines, and a send in the app's "slash: send Hello
    /// <id>" line. On 59 the focus is the pill's; on 57 (REPLYBAR_BASE=57) its own field's.
    /// With R59_SLOW=1 each launch adds `-vory-demo-slow`, as testAudit and testLargeText do, and only the A0 cases run.
    /// Before each focus, whether the dock shows Stop or "Queue message" (a slowed demo turn still running at the open),
    /// and its buttons.
    /// Two more A0-only variants, for what testAudit and testLargeText do before their first send and the plain probe
    /// doesn't: R59_SIZE (AX5, as testLargeText; `launch` applies it), and R59_PROBE_AUDIT=1 (one
    /// performAccessibilityAudit on the pill state before the focus, as testAudit's first).
    func testSendProbe() throws {
        let slow = env["R59_SLOW"] == "1"
        let ax5 = !(env["R59_SIZE"] ?? "").isEmpty, audit = env["R59_PROBE_AUDIT"] == "1"
        let cases: [(String, Double, Bool)] = [("A0a", 0.0, false), ("A0b", 0.0, false), ("A0c", 0.0, true), ("A", 1.2, true), ("B", 3.0, true)]
        for (id, wait, typedRead) in (slow || ax5 || audit ? Array(cases.prefix(3)) : cases) {
            try launch(slow ? ["-vory-demo-slow"] : []); try openChat()
            let users = { self.app.descendants(matching: .any).matching(identifier: "thread.row.user").allElementsBoundByIndex }
            if audit {
                var n = 0
                do { try app.performAccessibilityAudit { _ in n += 1; return true } } catch { say("PROBE \(id) audit ERROR \(error)") }
                say("PROBE \(id) audit done: \(n) issues (kept, not printed)")
            }
            let before = users().count
            let dockButtons = el("chat.dock").descendants(matching: .button).allElementsBoundByIndex.map { $0.label.isEmpty ? $0.identifier : $0.label }
            say("PROBE \(id) before focus: slow=\(slow) ax5=\(ax5) audit=\(audit) stop=\(app.buttons["Stop"].firstMatch.exists) queue=\(app.buttons["Queue message"].firstMatch.exists) dock buttons \(dockButtons)")
            say("PROBE MARK focus \(id) base=\(base57 ? 57 : 59) userRows=\(before)")
            if base57 { el("composer.text").tap(); pause(1.0) } else { focusFromPill() }
            let field = el("composer.text"), send = el("composer.send")
            guard field.waitForExistence(timeout: 3) else { say("VOID probe \(id): no composer.text after the focus"); continue }
            field.typeText("Hello \(id)")
            let typedAt = Date()
            if typedRead { say("PROBE \(id) typed: send=\(f(send.frame))") }
            if wait > 0 {
                let left = wait - Date().timeIntervalSince(typedAt)
                if left > 0 { pause(left) }
                say("PROBE \(id) at wait: send=\(f(send.frame))")
            }
            say("PROBE MARK send \(id) +\(String(format: "%.2f", Date().timeIntervalSince(typedAt)))s after typeText")
            send.tap()
            say("PROBE \(id) tapped: send=\(send.exists ? f(send.frame) : "-")")
            var sent = false
            for s in [1.0, 3.0] {
                pause(s == 1.0 ? 1.0 : 2.0)
                let value = field.exists ? (field.value as? String ?? "?") : "(no field)"
                let rows = users()
                let last = rows.last.map { String($0.label.prefix(60)) } ?? "none"
                sent = rows.count > before || (field.exists && value.isEmpty) || el("composer.pill").exists
                say("PROBE \(id) +\(Int(s))s field=\"\(value)\" pill=\(el("composer.pill").exists) userRows=\(rows.count) last=\"\(last)\" stop=\(app.buttons["Stop"].firstMatch.exists)")
                if s == 1.0 {
                    say("PROBE \(id) +1s reads: hittable=\(send.exists && send.isHittable) enabled=\(send.exists && send.isEnabled) dock=\(f(el("chat.dock").frame)) keyboard=\(keyboardUp)")
                }
            }
            say("PROBE \(id) result sent=\(sent) (the test's read; the runner's is the slash line)")
        }
        say("PROBE MARK end")
    }

    // MARK: 17. The queue probe: a second message while the first's reply runs

    /// While a reply runs, Send queues: the field clears, the message shows as queued (the strip, `queue.edit`), and the
    /// pill says "Sends after this reply". At the demo's normal speed, on 59 and 57: "Hello Q1" sent at A0's pace; once
    /// Stop shows (up to 2 s, the wait logged), the device's focus, "Later Q2" typed and composer.send tapped at A0's
    /// pace. Three runs, each on its own launch. No assertion: the read is the app's lines naming "Later Q2".
    func testQueueProbe() throws {
        for run in 1...3 {
            try launch(); try openChat()
            let users = { self.app.descendants(matching: .any).matching(identifier: "thread.row.user").allElementsBoundByIndex }
            let field = el("composer.text"), send = el("composer.send"), stop = app.buttons["Stop"].firstMatch
            say("QUEUE MARK focus Q1 run \(run) base=\(base57 ? 57 : 59) userRows=\(users().count)")
            if base57 { field.tap(); pause(1.0) } else { focusFromPill() }
            guard field.waitForExistence(timeout: 3) else { say("VOID queue run \(run): no composer.text for Q1"); continue }
            field.typeText("Hello Q1")
            send.tap()
            say("QUEUE MARK Q1 tapped run \(run)")
            let t0 = Date()
            let running = stop.waitForExistence(timeout: 2)
            say("QUEUE run \(run) Stop \(running ? "came" : "did not come") after \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
            say("QUEUE run \(run) before Q2's focus: stop=\(stop.exists) queueMessage=\(app.buttons["Queue message"].firstMatch.exists) send=\(send.exists ? send.label : "-") pill=\(el("composer.pill").exists)")
            if base57 { field.tap(); pause(1.0) } else if el("composer.pill").exists { focusFromPill() } else { field.tap(); pause(1.0) }
            guard field.waitForExistence(timeout: 3) else { say("VOID queue run \(run): no composer.text for Q2"); continue }
            field.typeText("Later Q2")
            send.tap()
            say("QUEUE MARK Q2 tapped run \(run)")
            for s in [1.0, 3.0] {
                pause(s == 1.0 ? 1.0 : 2.0)
                let value = field.exists ? (field.value as? String ?? "?") : "(no field)"
                let pill = el("composer.pill")
                say("QUEUE run \(run) +\(Int(s))s field=\"\(value)\" strip=\(el("queue.edit").exists) pill=\(pill.exists) pillValue=\"\(pill.exists ? (pill.value as? String ?? "?") : "-")\" userRows=\(users().count) stop=\(stop.exists)")
            }
        }
        say("QUEUE MARK end")
    }

    // MARK: 18. The chat list's gaps and open row

    /// The Chats page as launched (the demo, the Chats tab): the search field's frame, the Scheduled card's (the cell
    /// holding chats.scheduled) and the first chat card's (the next cell below it in the same column: hidden tabs keep
    /// their cells in the tree, so a cell counts only at the Scheduled cell's x and width), and the two gaps, search to
    /// Scheduled and Scheduled to the first chat (the two should be equal). Then "Packing list" opened:
    /// beside a detail column (the iPad, the open Duo) its cell's frame against its label's, for the open row's tint.
    /// Each state's screenshot is kept as an attachment (the demo's own chats). No assertion: a read before and after.
    func testListGaps() throws {
        try launch()
        let sched = el("chats.scheduled")
        guard sched.waitForExistence(timeout: 30) else { say("VOID gaps: no chats.scheduled"); return }
        pause(1.0)
        let search = app.searchFields.firstMatch
        let schedCell = app.cells.containing(.any, identifier: "chats.scheduled").firstMatch
        let sf = search.exists ? search.frame : .zero, sc = schedCell.exists ? schedCell.frame : sched.frame
        let below = app.cells.allElementsBoundByIndex.map { $0.frame }
            .filter { $0.minY >= sc.maxY - 0.5 && abs($0.minX - sc.minX) < 1 && abs($0.width - sc.width) < 1 }
            .min { $0.minY < $1.minY }
        say("GAPS search=\(search.exists ? f(sf) : "-") scheduled=\(f(sc)) (cell \(schedCell.exists)) firstChat=\(below.map(f) ?? "-")")
        if search.exists { say("GAPS search to scheduled \(String(format: "%.1f", sc.minY - sf.maxY))") }
        if let b = below { say("GAPS scheduled to first chat \(String(format: "%.1f", b.minY - sc.maxY))") }
        // The rule: G within 1 pt of S (read, not asserted: 57 has 35 against 10).
        if search.exists, let b = below {
            let s = sc.minY - sf.maxY, g = b.minY - sc.maxY
            say("GAPS check G-S \(String(format: "%.1f", g - s)): \(abs(g - s) <= 1 ? "equal within 1 pt" : "NOT equal")")
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "gaps-list"; shot.lifetime = .keepAlways; add(shot)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Packing list' AND NOT (identifier BEGINSWITH 'chat.')")).firstMatch
        guard row.exists else { say("GAPS no Packing list row"); return }
        row.tap(); pause(1.5)
        // The row's cell in the list's own column; on a phone the pushed chat's header carries the same title, so
        // "list shown" needs that cell too (else the header reads as the row).
        let rowCell = listCell("Packing list", column: sc)
        say("GAPS open row: list shown=\(rowCell.exists && row.isHittable) detail=\(el("composer.pill").exists || el("composer.text").exists) cell=\(rowCell.exists ? f(rowCell.frame) : "-") label=\(row.exists ? f(row.frame) : "-")")
        // The list's elements with isSelected: exactly the open chat's row beside a detail column. Only elements inside
        // one of the list's own cells (the Scheduled cell's x and width) count, so a symbol from another view on the iPad
        // or the chat's own view on the phone doesn't.
        say("GAPS selected in the list: \(selectedInList(column: sc))")
        let shot2 = XCTAttachment(screenshot: app.screenshot()); shot2.name = "gaps-open-row"; shot2.lifetime = .keepAlways; add(shot2)
    }

    /// The elements with isSelected inside the list's own cells (the column's x and width, on screen), as
    /// "count [id/label, ...]". The count is rows only, an isSelected element whose frame matches a list cell's frame
    /// within 2 pt (the row's Button fills its cell: on 57's iPad, label = cell = 8,227,328,106).
    /// Every row counted gets a "SELECTED row" line with its debugDescription; any other isSelected element inside a list
    /// cell (a symbol, say) gets an "OTHER selected" line with its own, apart from the count.
    private func selectedInList(column c: CGRect) -> String {
        let cells = app.cells.allElementsBoundByIndex.map { $0.frame }
            .filter { abs($0.minX - c.minX) < 1 && abs($0.width - c.width) < 1 && $0.height > 0 }
        let inCells = app.descendants(matching: .any).matching(NSPredicate(format: "isSelected == true")).allElementsBoundByIndex
            .filter { e in let r = e.frame; return r.height > 0 && cells.contains { $0.insetBy(dx: -1, dy: -1).contains(r) } }
        func rowSized(_ r: CGRect) -> Bool {
            cells.contains { abs($0.minX - r.minX) <= 2 && abs($0.minY - r.minY) <= 2 && abs($0.width - r.width) <= 2 && abs($0.height - r.height) <= 2 }
        }
        func flat(_ s: String) -> String { String(s.replacingOccurrences(of: "\n", with: " | ").prefix(400)) }
        let rows = inCells.filter { rowSized($0.frame) }, others = inCells.filter { !rowSized($0.frame) }
        for e in rows { say("SELECTED row \(f(e.frame)) \(flat(e.debugDescription))") }
        for e in others { say("OTHER selected \(f(e.frame)) \(flat(e.debugDescription))") }
        return "\(rows.count) \(rows.map { "\($0.identifier.isEmpty ? "-" : $0.identifier)/\($0.label.prefix(30))" }) (other \(others.count))"
    }

    /// The cell holding `title` in the list's own column (the Scheduled cell's x and width), or a missing element.
    private func listCell(_ title: String, column c: CGRect) -> XCUIElement {
        let all = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).allElementsBoundByIndex
        return all.first { abs($0.frame.minX - c.minX) < 1 && abs($0.frame.width - c.width) < 1 } ?? app.cells.matching(identifier: "none.sentinel").firstMatch
    }

    // MARK: 19. The chat list's audit

    /// performAccessibilityAudit on the Chats page as launched, then with "Packing list" open (beside the list where a
    /// detail column shows it: the iPad, the open Duo), each issue printed as testAudit's are, and the list's isSelected
    /// count with the chat open. No assertion: the issues are read against 57's.
    func testChatListAudit() throws {
        try launch()
        let sched = el("chats.scheduled")
        guard sched.waitForExistence(timeout: 30) else { say("VOID list audit: no chats.scheduled"); return }
        pause(1.0)
        let schedCell = app.cells.containing(.any, identifier: "chats.scheduled").firstMatch
        let sc = schedCell.exists ? schedCell.frame : sched.frame
        func audit(_ state: String) {
            var n = 0
            do {
                try app.performAccessibilityAudit { issue in
                    n += 1
                    let e = issue.element
                    let who = e.map { "\($0.identifier.isEmpty ? "-" : $0.identifier)/\($0.label.isEmpty ? "-" : $0.label)" } ?? "no element"
                    self.say("AUDIT \(state) ISSUE \(issue.auditType) | \(who) | \(issue.compactDescription)")
                    return true
                }
            } catch { say("AUDIT \(state) ERROR \(error)") }
            say("AUDIT \(state) done: \(n) issues")
        }
        audit("chatlist")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Packing list' AND NOT (identifier BEGINSWITH 'chat.')")).firstMatch
        guard row.exists else { say("VOID list audit: no Packing list row"); return }
        row.tap(); pause(1.5)
        let listShown = listCell("Packing list", column: sc).exists && row.isHittable   // the row's cell in the list's column
        say("AUDIT chatlist-open list shown=\(listShown) selected in the list: \(selectedInList(column: sc))")
        if listShown { audit("chatlist-open") } else { say("AUDIT chatlist-open skipped: the chat covers the list here") }
    }

    // MARK: 20. The open row

    /// Where the list stands beside the open chat (the iPad, the open Duo; on a phone the chat covers the list, VOID), in
    /// light and then dark, each on its own launch:
    ///   A, the demo's pinned chat ("Packing list for the lake weekend", DemoContent's one `pinned: true`), opened: the
    ///     top row of its section. Its cell's screenshot (the corners, the lines), its title's
    ///     contrast against the row's background, the list's isSelected count.
    ///   B, a middle row ("Newsletter intro, take two"), opened after A: B's cell's screenshot (square edges, no lines)
    ///     and contrast, A's cell again (no tint: its background's color is printed beside B's), and the count (one, B).
    /// The contrast as testPlaceholderContrast's (the screen's pixels, WCAG): in each title band, the median pixel is the
    /// background and the one farthest from it the text. The face's reaction to the row's tap has nothing a test can
    /// read (BotAmbient.tap only stamps dates; the DEBUG blink probe logs the fold's blink, not a tap's), so it's checked
    /// by hand. No assertion: a read on 57 (the old tint) and on 59.
    func testOpenRow() throws {
        for scheme in ["light", "dark"] {
            try launch(scheme: scheme)
            let sched = el("chats.scheduled")
            guard sched.waitForExistence(timeout: 30) else { say("VOID open row \(scheme): no chats.scheduled"); return }
            pause(1.0)
            let schedCell = app.cells.containing(.any, identifier: "chats.scheduled").firstMatch
            let sc = schedCell.exists ? schedCell.frame : sched.frame
            func rowButton(_ title: String) -> XCUIElement {
                app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND NOT (identifier BEGINSWITH 'chat.')", title)).firstMatch
            }
            func cell(_ title: String) -> XCUIElement { listCell(title, column: sc) }   // the list's own column
            func shoot(_ e: XCUIElement, _ name: String) {
                guard e.exists else { say("OPENROW \(scheme) no element for \(name)"); return }
                let a = XCTAttachment(screenshot: e.screenshot()); a.name = "openrow-\(scheme)-\(name)"; a.lifetime = .keepAlways; add(a)
            }
            let a = "Packing list", b = "Newsletter intro"
            guard rowButton(a).exists else { say("VOID open row \(scheme): no \(a) row"); return }
            rowButton(a).tap(); pause(1.5)
            guard cell(a).exists, rowButton(a).isHittable else { say("VOID open row \(scheme): the chat covers the list here"); return }
            let ca = cell(a)
            say("OPENROW \(scheme) A open: cell=\(ca.exists ? f(ca.frame) : "-") top of section=\(ca.exists && abs(ca.frame.minY - (app.cells.allElementsBoundByIndex.map { $0.frame }.filter { abs($0.minX - sc.minX) < 1 && abs($0.width - sc.width) < 1 && $0.minY > sc.maxY }.map { $0.minY }.min() ?? -1)) < 1) selected \(selectedInList(column: sc))")
            if ca.exists { say("OPENROW \(scheme) A open title \(titleContrast(in: ca.frame, name: "\(scheme)-A-open"))") }
            shoot(ca, "A-open")
            guard rowButton(b).exists else { say("VOID open row \(scheme): no \(b) row"); return }
            rowButton(b).tap(); pause(1.5)
            let cb = cell(b), ca2 = cell(a)
            say("OPENROW \(scheme) B open: cell=\(cb.exists ? f(cb.frame) : "-") selected \(selectedInList(column: sc))")
            if cb.exists { say("OPENROW \(scheme) B open title \(titleContrast(in: cb.frame, name: "\(scheme)-B-open"))") }
            if ca2.exists { say("OPENROW \(scheme) A after B title \(titleContrast(in: ca2.frame, name: "\(scheme)-A-after"))") }
            shoot(cb, "B-open"); shoot(ca2, "A-after")
        }
    }

    /// The contrast in a row's title band (8 to 30 pt below the cell's top, from a quarter to 85% across, past the face),
    /// as testPlaceholderContrast measures: "ratio=… text=(r,g,b) bg=(r,g,b) crop=…", the crop kept as an attachment.
    private func titleContrast(in cell: CGRect, name: String) -> String {
        let winW = app.windows.firstMatch.frame.width
        guard let shot = XCUIScreen.main.screenshot().image.cgImage, winW > 0 else { return "VOID: no screenshot" }
        let s = CGFloat(shot.width) / winW
        let area = CGRect(x: cell.minX + cell.width * 0.25, y: cell.minY + 8, width: cell.width * 0.6, height: 22)
        let px = CGRect(x: area.minX * s, y: area.minY * s, width: area.width * s, height: area.height * s).integral
        guard let crop = shot.cropping(to: px) else { return "VOID: no crop \(f(px))" }
        let w = crop.width, h = crop.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buf in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn, w * h > 0 else { return "VOID: no pixels" }
        func lin(_ c: UInt8) -> Double { let v = Double(c) / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func lum(_ i: Int) -> Double { 0.2126 * lin(bytes[i]) + 0.7152 * lin(bytes[i + 1]) + 0.0722 * lin(bytes[i + 2]) }
        let pixels = (0..<(w * h)).map { (i: $0 * 4, l: lum($0 * 4)) }.sorted { $0.l < $1.l }
        let bg = pixels[pixels.count / 2]
        let text = abs(pixels.first!.l - bg.l) >= abs(pixels.last!.l - bg.l) ? pixels.first! : pixels.last!
        let ratio = (max(bg.l, text.l) + 0.05) / (min(bg.l, text.l) + 0.05)
        func rgb(_ i: Int) -> String { "(\(bytes[i]),\(bytes[i + 1]),\(bytes[i + 2]))" }
        let att = XCTAttachment(image: UIImage(cgImage: crop)); att.name = "title-\(name)"; att.lifetime = .keepAlways; add(att)
        return String(format: "ratio=%.2f text=%@ bg=%@ crop=%@", ratio, rgb(text.i), rgb(bg.i), f(area))
    }

    // MARK: 16. Send's track: where Send is in the first 1.5 s

    /// On the iPad, Send can sit well above its settled place right after typing, with the dock already settled. On its
    /// own launch, the device's focus (59's pill, 57's field), ONE letter typed (the keystroke that brings Send in), then
    /// Send's frame sampled as fast as XCUITest allows (aiming at 100 ms) until 1.5 s after typeText returned; "none" while
    /// composer.send isn't there. No tap, no other query in the loop. XCUITest's frame is the accessibility frame: mid
    /// animation it may not be where Send is drawn, or where a touch lands.
    func testSendTrack() throws {
        try launch(); try openChat()
        say("TRACK MARK focus base=\(base57 ? 57 : 59)")
        if base57 { el("composer.text").tap(); pause(1.0) } else { focusFromPill() }
        let field = el("composer.text"), send = el("composer.send")
        guard field.waitForExistence(timeout: 3) else { say("VOID track: no composer.text after the focus"); return }
        field.typeText("H")
        let typedAt = Date()
        say("TRACK MARK typed")
        var n = 0
        while Date().timeIntervalSince(typedAt) < 1.5 {
            let at = Date()
            let where_ = send.exists ? f(send.frame) : "none"
            say("TRACK \(n) +\(String(format: "%.3f", at.timeIntervalSince(typedAt)))s send=\(where_)")
            n += 1
            let spent = Date().timeIntervalSince(at)
            if spent < 0.1 { pause(0.1 - spent) }
        }
        say("TRACK MARK end samples=\(n)")
    }
}

private extension XCUIElement {
    /// Deletes the field's words, one key each (no paste, no select-all menu).
    func clearText() {
        let n = (value as? String)?.count ?? 0
        if n > 0 { typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: n)) }
    }
}
