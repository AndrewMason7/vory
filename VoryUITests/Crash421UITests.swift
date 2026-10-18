import XCTest

/// #421 (1.5 (26) testers: the app crashed or hung "opening a tool card", "browsing reasoning/tools cards in the chat
/// as the agent works", "attempted to expand a tool call and the app hung"): tool and reasoning cards opened and closed
/// over and over while a turn streams, and with very large outputs and reasoning. Each step prints C421 lines with how
/// long the app took to answer; the host reads the app's own main-thread stalls from its perf log and looks for crash
/// reports. Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set; HERMES_E2E_BUNDLE picks the copy (the demo).
@MainActor
final class Crash421UITests: XCTestCase {
    private var app: XCUIApplication!

    private func mark(_ s: String) { print(String(format: "C421 %.2f %@", Date().timeIntervalSince1970, s)) }
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func launch(_ extra: [String] = []) throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set")
        }
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: e["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.vorantx.vory.demo")
        app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats"] + extra
        app.launch()
    }

    private func hittable(_ query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let e = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { return e }
            pause(0.2)
        } while Date() < deadline
        return nil
    }

    /// A new chat with `prompt` sent.
    private func send(_ prompt: String, started fragment: String) {
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40), "no chat list")
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "no composer")
        composer.tap()
        for _ in 0..<3 {
            composer.typeText(prompt)
            let typed = composer.value as? String ?? ""
            if typed == prompt { break }
            composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count + 2))
        }
        if let send = hittable(app.buttons.matching(identifier: "composer.send"), timeout: 5) { send.tap() }
        mark("sent \(prompt)")
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch.waitForExistence(timeout: 20)
        // The keyboard down, so the thread has the screen.
        app.swipeDown(velocity: .slow)
    }

    /// Taps `element`, and how long the app took to take the tap and settle (XCTest waits for it to go idle).
    private func timedTap(_ element: XCUIElement, _ name: String) {
        let t0 = Date()
        element.tap()
        mark(String(format: "tap %@ %.2f s", name, Date().timeIntervalSince(t0)))
    }

    /// Whether the app is still there to answer (XCTest's app.state reads foreground whatever happens on iOS 27).
    private func alive(_ name: String) {
        // The message bar is the waveform while dictation listens: the app answers, but a tap of the test's landed on
        // the bar's microphone, which it should not have (reported, so a run that does it can be told apart).
        let listening = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Listening'")).firstMatch
        let ok = app.textViews["composer.text"].firstMatch.waitForExistence(timeout: 10) || listening.exists
        if listening.exists { mark("\(name): DICTATION started by a stray tap") }
        mark("\(name): app \(ok ? "answers" : "GONE")")
        if !ok {
            // What is on screen instead: a sheet over the chat, or nothing answering at all.
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "alive-failed"; a.lifetime = .keepAlways; add(a)
            shot("alive-failed")
            let t0 = Date()
            let sheet = app.buttons["Done"].exists || app.buttons["Open the full call"].exists
            mark(String(format: "ALIVE-FAILED tree answered in %.2f s; a sheet or open card's buttons %@", Date().timeIntervalSince(t0), sheet ? "up" : "not up"))
        }
        XCTAssertTrue(ok, "the app stopped answering after \(name)")
    }

    /// The thread's tool cards and the top of the dock, read from one copy of the tree: a card found there cannot
    /// leave between the find and the tap, as rows do when the lazy stack takes them during a stream, and an element
    /// bound by index then pointed at another card or at none (27's gate). `key` keeps the cards whose label has it.
    private func cardsOnScreen(_ key: String? = nil) -> (cards: [(label: String, frame: CGRect)], dockTop: CGFloat, ended: Bool, step: Int) {
        guard let snap = try? app.snapshot() else { return ([], 0, false, 0) }
        var cards: [(String, CGRect)] = []
        var dockTop = snap.frame.maxY - 140
        var ended = false
        var step = 0
        func walk(_ s: XCUIElementSnapshot) {
            if s.identifier == "chat.dock" { dockTop = s.frame.minY }
            if s.elementType == .button, s.label.localizedCaseInsensitiveContains("terminal"), key.map({ s.label.contains($0) }) ?? true {
                cards.append((s.label, s.frame))
            }
            // The marathon's reply, which comes at its end, and the newest step it shows ("Step 68 of 90: …").
            if !ended, s.label.contains("Everything else looked healthy") { ended = true }
            if let m = s.label.firstMatch(of: /Step (\d+) of \d+/), let n = Int(m.output.1), n > step { step = n }
            for c in s.children { walk(c) }
        }
        walk(snap)
        return (cards, dockTop, ended, step)
    }

    /// A card's header row, where a tap only folds or unfolds it (the middle of an open card is its output, its
    /// "Show more lines" and "Open the full call"), if that row is between the top bar and the dock: a tap read off a
    /// frame while the list coasted, or under the dock, landed on the message bar and started dictation (27's gate).
    private func headerPoint(_ f: CGRect, dockTop: CGFloat) -> XCUICoordinate? {
        let y = f.minY + 22
        guard f.width > 0, y > 150, y < dockTop - 12 else { return nil }
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: y))
    }

    /// A tap at a point, timed (`timedTap`'s measure).
    private func timedTap(_ point: XCUICoordinate, _ name: String) {
        let t0 = Date()
        point.tap()
        mark(String(format: "tap %@ %.2f s", name, Date().timeIntervalSince(t0)))
    }

    /// The keyboard down (a drag from just above the dock to the bottom, as ChatFollowUITests does) and the thread
    /// back on its end, following the turn. `send`'s swipe left the keyboard up and the reader above the rows the
    /// stream adds: nearly every card was below the screen, out of reach.
    private func followTheEnd() {
        let dock = app.descendants(matching: .any).matching(identifier: "chat.dock").firstMatch
        if dock.exists, dock.frame.maxY < app.frame.height - 120 {
            let from = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: dock.frame.minY - 12))
            let to = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: app.frame.height - 4))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0)
            pause(1)
        }
        let jump = app.buttons.matching(NSPredicate(format: "label == 'Jump to latest'")).firstMatch
        if jump.exists, jump.isHittable { jump.tap(); pause(0.6) }
    }

    func testToolCardsOpenedAndClosedWhileALongTurnStreams() throws {
        // HERMES_E2E_421_MODE: "gate" (the default) leaves every third card open, swipes fast every fifth step and goes
        // back to the end whenever no card is in reach (an open card, revealed, can fill the screen), so the cycles add
        // up. For comparing builds (28): "found" is the same without the return to the end; "end" brings the reader
        // back to the end after every tap, with no fast swipes, every third card still left open; "closed" closes every
        // card again and keeps the reader up the thread. Each step marks the newest step the app shows, against the
        // mock's log of when it sent each one; after the loop, when the app shows the turn's end.
        let mode = ProcessInfo.processInfo.environment["HERMES_E2E_421_MODE"].flatMap { $0.isEmpty ? nil : $0 } ?? "gate"
        try launch()
        send("marathon 90", started: "of 90: checking shard")
        followTheEnd()
        if mode == "closed" { app.swipeDown(velocity: .slow); pause(1) }
        mark("MODE \(mode)")
        let end = Date().addingTimeInterval(50)
        var i = 0
        // Cycles (a card opened, and closed unless it is a third one) while the turn was still streaming: a floor, so
        // a slow copy of the tree cannot quietly turn this into a weak test.
        var whileStreaming = 0
        while Date() < end {
            i += 1
            let t0 = Date()
            let seen = cardsOnScreen()
            let inRange = seen.cards.filter { headerPoint($0.frame, dockTop: seen.dockTop) != nil }
            mark(String(format: "step %d: %d cards, %d in reach, copy %.2f s, app at step %d%@", i, seen.cards.count, inRange.count, Date().timeIntervalSince(t0), seen.step, seen.ended ? ", turn ended" : ""))
            guard let card = inRange.last, let open = headerPoint(card.frame, dockTop: seen.dockTop) else {
                if mode == "gate" { followTheEnd() }
                pause(0.5); continue
            }
            timedTap(open, "open \(i)")
            pause(0.3)
            // Every third one is left open, so open cards ride the stream. The card is found again by the shard its
            // command names, where it is now.
            let key = card.label.firstMatch(of: /shard-\d+/).map { String($0.output) } ?? card.label
            var cycled = i % 3 == 0 && mode != "closed"
            if !cycled {
                let again = cardsOnScreen(key)
                if let c = again.cards.first, let close = headerPoint(c.frame, dockTop: again.dockTop) { timedTap(close, "close \(i)"); cycled = true }
            }
            if cycled, !seen.ended { whileStreaming += 1 }
            if mode == "end" { followTheEnd() }
            if mode == "found" || mode == "gate", i % 5 == 0 {
                app.swipeDown(velocity: .fast); pause(0.3); app.swipeUp(velocity: .fast)
                // The list coasts after a fast swipe: frames read meanwhile are where the rows were.
                pause(1.5)
                followTheEnd()
            }
            pause(0.2)
        }
        mark("cycles while the turn streamed: \(whileStreaming)")
        // When the app shows the turn's end (the mock's log says when it sent it), up to four minutes more.
        let shownBy = Date().addingTimeInterval(240)
        var last = cardsOnScreen()
        while !last.ended, Date() < shownBy { pause(2); last = cardsOnScreen(); mark("waiting: app at step \(last.step)") }
        mark(last.ended ? "TURN-SHOWN-ENDED" : "TURN-NOT-SHOWN-ENDED at step \(last.step)")
        XCTAssertGreaterThanOrEqual(whileStreaming, 4, "only \(whileStreaming) open and close cycles while the turn streamed")
        alive("tool cards while streaming")
    }

    func testAToolCardWithAVeryLargeOutputOpens() throws {
        try launch()
        send("huge tool 1500000", started: "every shard is checked")
        pause(2)
        guard let card = hittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "terminal")), timeout: 15) else {
            XCTFail("no tool card"); return
        }
        for i in 1...4 { timedTap(card, "huge open/close \(i)"); pause(0.8) }
        alive("a 1.5 MB tool output")
    }

    /// The biggest of each: a 2 MB tool output opened, a reply with a 20,000-line code block, and 4 MB of reasoning
    /// opened while it streams; the host samples the app's footprint through it (C421 MEM lines mark the steps).
    func testTheLargestCardsOpen() throws {
        try launch()
        send("huge tool 2000000", started: "every shard is checked")
        pause(2)
        mark("MEM tool before open")
        if let card = hittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "terminal")), timeout: 15) {
            timedTap(card, "2 MB tool open"); pause(3); mark("MEM tool open")
            timedTap(card, "2 MB tool close"); pause(2)
        }
        alive("a 2 MB tool output")
        app.terminate(); try launch()
        send("huge code 20000", started: "Here is the whole log")
        pause(8); mark("MEM code reply")
        app.swipeDown(velocity: .fast); pause(2); app.swipeUp(velocity: .fast); pause(2)
        alive("a 20,000-line code reply")
        app.terminate(); try launch()
        send("huge reasoning 4000", started: "Reasoning")
        var opened = false
        for _ in 0..<40 {
            if !opened, let b = hittable(app.buttons.matching(NSPredicate(format: "label == %@", "Show reasoning")), timeout: 1) {
                timedTap(b, "4 MB reasoning open"); opened = true; mark("MEM reasoning open")
            }
            pause(1)
        }
        mark("MEM reasoning end")
        alive("4 MB of reasoning")
    }

    /// #421: a step's reasoning card tapped open just as its step ends (the tool call starts and the row it is in is
    /// sealed): over and over, through a turn of many steps.
    func testAReasoningCardOpenedAsItsStepEnds() throws {
        try launch()
        send("steps 12", started: "Reasoning")
        let end = Date().addingTimeInterval(45)
        var i = 0
        while Date() < end {
            let fold = app.buttons.matching(NSPredicate(format: "label == %@", "Show reasoning"))
            if let b = fold.allElementsBoundByIndex.last(where: { $0.exists && $0.isHittable }) { i += 1; timedTap(b, "step reasoning \(i)") }
            pause(0.15)
        }
        alive("reasoning cards as steps end")
    }

    /// The card that opens a tool output with no line breaks (a whole API response as one line of JSON): no line cap
    /// stops it, so the card shows its first 20,000 characters, wrapped, as one tall block (#421).
    func testAToolCardWithAOneLineOutputOpens() throws {
        try launch()
        send("huge blob 2000000", started: "every shard is checked")
        pause(2)
        guard let card = hittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "terminal")), timeout: 15) else {
            XCTFail("no tool card"); return
        }
        timedTap(card, "one-line open"); pause(2); shot("421-blob-open")
        for i in 1...3 { app.swipeDown(velocity: .slow); pause(1); shot("421-blob-up-\(i)") }
        for _ in 1...3 { app.swipeUp(velocity: .fast); pause(0.5) }
        if let c = hittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "terminal")), timeout: 5) { timedTap(c, "one-line close") }
        alive("a one-line 2 MB tool output")
    }

    /// "Show N more lines" on a 2 MB output: the block grows to its 20,000-character cap.
    func testShowMoreLinesOnAHugeOutput() throws {
        try launch()
        send("huge tool 2000000", started: "every shard is checked")
        pause(2)
        guard let card = hittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "terminal")), timeout: 15) else {
            XCTFail("no tool card"); return
        }
        timedTap(card, "2 MB open"); pause(1.5)
        guard let more = hittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show ' AND label CONTAINS 'more lines'")), timeout: 5) else {
            XCTFail("no Show more lines"); return
        }
        timedTap(more, "show more lines"); pause(2); shot("421-more-lines")
        for i in 1...3 { app.swipeDown(velocity: .slow); pause(1); shot("421-more-lines-up-\(i)") }
        if let less = hittable(app.buttons.matching(NSPredicate(format: "label == 'Show less'")), timeout: 5) { timedTap(less, "show less") }
        alive("Show more lines on a 2 MB output")
    }

    /// "Open the full call": the whole output in one text view, many lines and one line.
    func testTheFullCallSheetWithAHugeOutput() throws {
        try launch()
        for (prompt, name) in [("huge tool 2000000", "lines"), ("huge blob 2000000", "one-line")] {
            send(prompt, started: "every shard is checked")
            pause(2)
            guard let card = hittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "terminal")), timeout: 15) else {
                XCTFail("no tool card"); return
            }
            timedTap(card, "\(name) open"); pause(1.5)
            guard let full = hittable(app.buttons.matching(NSPredicate(format: "label == 'Open the full call'")), timeout: 5) else {
                XCTFail("no Open the full call"); return
            }
            timedTap(full, "\(name) full call"); pause(3); shot("421-sheet-\(name)")
            for i in 1...3 { app.swipeUp(velocity: .fast); pause(1); shot("421-sheet-\(name)-down-\(i)") }
            if let done = hittable(app.buttons.matching(NSPredicate(format: "label == 'Done'")), timeout: 5) { timedTap(done, "\(name) sheet done") }
            pause(1)
            alive("the full call sheet, \(name)")
            app.terminate(); try launch()
        }
    }

    /// Whether the full-call sheet with a 2 MB output keeps the app's main thread free by itself, or only stops
    /// answering when the accessibility tree is read: opened, then left alone (no UI queries; screenshots only) while
    /// the host reads the app's own stall log, then one query timed. `HERMES_E2E_421_KIND` picks "tool" (many lines,
    /// the default) or "blob" (one line).
    func testTheFullCallSheetLeftAlone() throws {
        try launch()
        let kind = ProcessInfo.processInfo.environment["HERMES_E2E_421_KIND"].flatMap { $0.isEmpty ? nil : $0 } ?? "tool"
        send("huge \(kind) 2000000", started: "every shard is checked")
        pause(2)
        guard let card = hittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "terminal")), timeout: 15) else {
            XCTFail("no tool card"); return
        }
        timedTap(card, "open"); pause(1.5)
        guard let full = hittable(app.buttons.matching(NSPredicate(format: "label == 'Open the full call'")), timeout: 5) else {
            XCTFail("no Open the full call"); return
        }
        full.tap()
        mark("SHEET-OPEN \(kind)")
        // No queries from here: only the screen, which does not read the app's tree.
        for i in 1...4 { pause(3); let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "421-alone-\(kind)-\(i)"; a.lifetime = .keepAlways; add(a) }
        mark("SHEET-QUERY \(kind)")
        let t0 = Date()
        let done = app.buttons["Done"].firstMatch.exists
        mark(String(format: "SHEET-ANSWERED %@ in %.2f s (Done %@)", kind, Date().timeIntervalSince(t0), done ? "found" : "missing"))
        shot("421-alone-\(kind)")
    }

    /// The full-call sheet on a big output (HERMES_E2E_421_SIZE bytes, 2 MB by default; HERMES_E2E_421_KIND "tool",
    /// many lines, or "blob", one line), with the app's stall log at 100 ms and the piece probe on (call #40: nothing
    /// on screen holds an unbounded text block). It lays out in pieces off the main thread, none past the graphics
    /// card's largest texture; XCTest's swipes, which read the whole accessibility tree, answer in time; a drag
    /// scrolls it; and Copy all and Share's Copy carry the whole output (the host reads the simulator's pasteboard at
    /// each PB-CHECK line). The host reads the stalls between SHEET-OPEN and SHEET-DONE.
    func testTheFullCallSheetStaysFree() throws {
        let e = ProcessInfo.processInfo.environment
        let kind = e["HERMES_E2E_421_KIND"].flatMap { $0.isEmpty ? nil : $0 } ?? "tool"
        let size = e["HERMES_E2E_421_SIZE"].flatMap { Int($0) } ?? 2_000_000
        try launch(["-vory-perf-stall-ms", "100", "-vory-piece-probe"])
        send("huge \(kind) \(size)", started: "every shard is checked")
        // The turn's end (a 10 MB output takes a while to come): while it runs the header says "Running terminal" too.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "every shard is checked")).firstMatch.waitForExistence(timeout: 90), "the turn did not end")
        pause(2)
        guard let card = hittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'terminal' AND NOT (identifier BEGINSWITH 'chat.')")), timeout: 30) else {
            XCTFail("no tool card"); return
        }
        timedTap(card, "open"); pause(1.5)
        // A tall card can leave its button under the dock: the thread is moved up to it.
        let fullQuery = app.buttons.matching(NSPredicate(format: "label == 'Open the full call'"))
        var found = hittable(fullQuery, timeout: 5)
        for _ in 0..<4 where found == nil { app.swipeUp(velocity: .slow); found = hittable(fullQuery, timeout: 2) }
        guard let full = found else { shot("421-free-no-full-call"); XCTFail("no Open the full call"); return }
        mark("SHEET-OPEN \(kind) \(size)")
        timedTap(full, "full call")
        // Pieces past 100 KB (`SelectableText.fitsOneView`); a small output is the text view, for the baseline.
        let probe = app.staticTexts["debug.pieces.sheet"].firstMatch
        if size > 100_000 {
            XCTAssertTrue(probe.waitForExistence(timeout: 90), "the sheet's pieces never came")
        } else {
            XCTAssertTrue(app.buttons["Copy all"].firstMatch.waitForExistence(timeout: 20), "no sheet")
        }
        mark("SHEET-LAID-OUT")
        pause(1)
        shot("421-free-\(kind)-\(size)")
        if size > 100_000 {
            // Reading order: the pieces are the sheet's texts in the tree, top to bottom, each its own element.
            let texts = app.descendants(matching: .any).matching(identifier: "sheet.pieces").firstMatch.staticTexts.allElementsBoundByIndex.prefix(12).filter { $0.exists }
            let tops = texts.map { $0.frame.minY }
            mark("PIECES \(texts.count) in the tree, tops \(tops.map { Int($0) })")
            XCTAssertGreaterThan(texts.count, 1, "the pieces are not separate elements")
            XCTAssertEqual(tops, tops.sorted(), "the pieces are not in reading order")
        }
        for i in 1...4 {
            let t0 = Date()
            app.swipeUp(velocity: .fast)
            mark(String(format: "swipe %d %.2f s", i, Date().timeIntervalSince(t0)))
            pause(0.5)
        }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)), to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let t0 = Date()
        from.press(forDuration: 0.05, thenDragTo: to)
        mark(String(format: "drag %.2f s", Date().timeIntervalSince(t0)))
        pause(1)
        shot("421-free-\(kind)-\(size)-scrolled")
        if probe.exists { mark("PROBE \(probe.label)") }
        if probe.exists, let px = probe.label.split(separator: ",").first(where: { $0.contains("px") }).flatMap({ Int($0.filter(\.isNumber)) }) {
            XCTAssertLessThan(px, 16_384, "a piece taller than the graphics card's largest texture")
        }
        // Copy all, then Share's Copy: the host reads the pasteboard's length at each line.
        if let copy = hittable(app.buttons.matching(NSPredicate(format: "label == 'Copy all'")), timeout: 5) {
            timedTap(copy, "copy all"); mark("PB-CHECK copy \(size)"); pause(4)
        } else { XCTFail("no Copy all") }
        if let share = hittable(app.buttons.matching(NSPredicate(format: "label == 'Share'")), timeout: 5) {
            timedTap(share, "share")
            // The share sheet may be drawn by the system, not the app: its Copy is looked for in both.
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let named = NSPredicate(format: "label == 'Copy'")
            if let copy = hittable(app.descendants(matching: .any).matching(named), timeout: 10) ?? hittable(springboard.descendants(matching: .any).matching(named), timeout: 5) {
                timedTap(copy, "share copy"); mark("PB-CHECK share \(size)"); pause(4)
            } else { XCTFail("no Copy in the share sheet"); shot("421-free-share-missing") }
        } else { XCTFail("no Share") }
        if let done = hittable(app.buttons.matching(NSPredicate(format: "label == 'Done'")), timeout: 5) { timedTap(done, "done") }
        pause(1)
        mark("SHEET-DONE")
        alive("the full call sheet, \(kind) \(size)")
    }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let folder = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"].flatMap { $0.isEmpty ? nil : $0 }
        let d = folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hermes-chat-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: d.appendingPathComponent("\(name).png"))
    }

    func testReasoningOpenedAndClosedWhileItStreams() throws {
        try launch()
        send("huge reasoning 1500", started: "Reasoning")
        let end = Date().addingTimeInterval(40)
        var i = 0
        while Date() < end {
            i += 1
            let fold = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Show reasoning", "Hide reasoning"))
            guard let b = fold.allElementsBoundByIndex.last(where: { $0.exists && $0.isHittable }) else { pause(0.5); continue }
            timedTap(b, "reasoning \(i)")
            pause(0.6)
        }
        alive("reasoning while streaming")
    }
}
