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

    private func launch() throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set")
        }
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: e["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.vorantx.vory.demo")
        app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats"]
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
        let ok = app.textViews["composer.text"].firstMatch.waitForExistence(timeout: 10)
        mark("\(name): app \(ok ? "answers" : "GONE")")
        XCTAssertTrue(ok, "the app stopped answering after \(name)")
    }

    func testToolCardsOpenedAndClosedWhileALongTurnStreams() throws {
        try launch()
        send("marathon 90", started: "of 90: checking shard")
        let end = Date().addingTimeInterval(50)
        var i = 0
        while Date() < end {
            i += 1
            let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "terminal"))
            guard let card = cards.allElementsBoundByIndex.last(where: { $0.exists && $0.isHittable }) else { pause(0.5); continue }
            timedTap(card, "open \(i)")
            pause(0.3)
            // Every third one is left open, so open cards ride the stream.
            if i % 3 != 0 { timedTap(card, "close \(i)") }
            if i % 5 == 0 { app.swipeDown(velocity: .fast); pause(0.3); app.swipeUp(velocity: .fast) }
            pause(0.2)
        }
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
