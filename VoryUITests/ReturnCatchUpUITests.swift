import XCTest

/// #371: away from the app during a long turn, the thread is held still (its views are left out
/// of the chat's changes) and catches up in one update on the way back. Coming back shows the
/// finished turn at once: no replay of its rows coming in, the thread at its end with no blank
/// past it, and a reader who was up the thread still where they were.
///
/// For the main thread's time around the catch-up, a trace can attach on the `C371 … RETURN-NOW`
/// line: the test waits 4 s after it before it brings the app back (scratchpad return-trace.sh),
/// and the app marks the catch-up with an "away catch-up" signpost (Points of Interest).
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set. HERMES_E2E_BUNDLE=
/// com.vorantx.vory.demo drives the demo copy. HERMES_E2E_STEPS: the marathon's steps (150);
/// HERMES_E2E_AWAY: seconds away (45; the turn ends while away at the mock's default pace).
final class ReturnCatchUpUITests: XCTestCase {
    private var app: XCUIApplication!
    private var url = ""
    private var token = ""

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private func setting(_ key: String, _ fallback: Int) -> Int {
        ProcessInfo.processInfo.environment[key].flatMap(Int.init) ?? fallback
    }

    private func mark(_ what: String) { print(String(format: "C371 %.1f %@", Date().timeIntervalSince1970, what)) }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let folder = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"].flatMap { $0.isEmpty ? nil : $0 }
        let d = folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hermes-chat-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: d.appendingPathComponent("\(name).png"))
        print("CHAT-SHOT \(d.appendingPathComponent("\(name).png").path)")
    }

    private func launch() {
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES"]
            app.launch()
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-companionPromptShown", "YES"]
            app.launch()
            connectIfNeeded()
        }
    }

    private func connectIfNeeded() {
        let start = app.buttons["onboarding.getStarted"].firstMatch
        let skip = app.buttons["onboarding.skip"].firstMatch
        let add = app.buttons["onboarding.addGateway"].firstMatch
        let newChat = app.buttons["chats.new"].firstMatch
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline, !(start.exists || skip.exists || add.exists || newChat.exists) { sleep(1) }
        guard start.exists || skip.exists || add.exists else { return }
        if start.exists { start.tap() }
        if skip.waitForExistence(timeout: 10) { skip.tap() }
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let name = app.textFields["gateway.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Workshop")
        let urlField = app.textFields["gateway.url"].firstMatch
        urlField.tap(); urlField.typeText(url)
        let tokenField = app.secureTextFields["gateway.sessionToken"].firstMatch
        for _ in 0..<8 where !(tokenField.exists && tokenField.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5), "no session token field")
        tokenField.tap(); tokenField.typeText(token)
        let test = app.buttons["gateway.test"].firstMatch
        for _ in 0..<6 where !(test.exists && test.isHittable) { app.swipeUp(velocity: .slow) }
        test.tap()
        let ready = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'gateway.ready received'")).firstMatch
        let readyBy = Date().addingTimeInterval(60)
        while !ready.exists, Date() < readyBy { app.swipeUp(velocity: .slow); _ = ready.waitForExistence(timeout: 2) }
        XCTAssertTrue(ready.exists, "WebSocket leg did not pass")
        app.buttons["gateway.save"].firstMatch.tap()
    }

    private func text(_ fragment: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
    }

    private func hittable(_ query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let e = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { return e }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }

    private var dock: XCUIElement { app.descendants(matching: .any).matching(identifier: "chat.dock").firstMatch }

    /// A new chat with `marathon <steps>` sent, back once its first steps show.
    private func startMarathon(_ steps: Int) {
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        let prompt = "marathon \(steps)"
        for _ in 0..<3 {
            composer.typeText(prompt)
            let typed = composer.value as? String ?? ""
            if typed == prompt { break }
            composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count + 2))
        }
        for _ in 0..<3 {
            guard let send = hittable(app.buttons.matching(identifier: "composer.send"), timeout: 5),
                  (composer.value as? String)?.contains("marathon") == true else { break }
            send.tap()
            if text(" of \(steps): checking shard").firstMatch.waitForExistence(timeout: 15) { break }
        }
        XCTAssertTrue(text(" of \(steps): checking shard").firstMatch.exists, "the long turn did not start")
    }

    /// Home, the time away, then back (a trace may attach on RETURN-NOW). Returns when back.
    private func away(_ seconds: Int) {
        XCUIDevice.shared.press(.home)
        mark("away")
        sleep(UInt32(seconds))
        mark("RETURN-NOW")
        sleep(4)
        mark("return")
        app.activate()
        mark("activated")
    }

    func testComingBackAfterALongTurnShowsItFinishedInOneStep() throws {
        guard let (u, t) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        url = u; token = t
        let steps = setting("HERMES_E2E_STEPS", 150)
        launch()
        startMarathon(steps)
        sleep(3)
        away(setting("HERMES_E2E_AWAY", 45))
        let back = Date()
        shot("return-0")
        // The turn's last words, on screen at once (the catch-up is one update, not a replay).
        let end = text("Everything else looked healthy")
        let seen = hittable(end, timeout: 8)
        let seenAfter = Date().timeIntervalSince(back)
        mark(String(format: "end seen after %.2f s", seenAfter))
        shot("return-1")
        XCTAssertNotNil(seen, "the finished turn's end was not on screen after coming back")
        XCTAssertLessThan(seenAfter, 3, "the finished turn took \(seenAfter) s to show after coming back")
        // No replay: the turn's end stays where it is (rows coming in would push it on).
        guard let last = seen else { return }
        let firstFrame = last.frame
        sleep(2)
        let laterFrame = last.frame
        mark("end row at \(Int(firstFrame.maxY)) then \(Int(laterFrame.maxY)), dock top \(Int(dock.frame.minY))")
        XCTAssertLessThan(abs(laterFrame.maxY - firstFrame.maxY), 4, "the thread moved after coming back (rows replayed or a late landing)")
        // At its end: the last row sits over the composer, with no blank past it.
        let gap = dock.frame.minY - laterFrame.maxY
        XCTAssertTrue((0...80).contains(gap), "the thread's end sits \(Int(gap)) pt over the composer after coming back")
        shot("return-2")
    }

    func testAReaderUpTheThreadKeepsTheirPlaceComingBack() throws {
        guard let (u, t) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        url = u; token = t
        launch()
        startMarathon(setting("HERMES_E2E_STEPS", 150))
        // Read up the thread while the turn runs on.
        sleep(6)
        for _ in 0..<3 { app.swipeDown(velocity: .slow); sleep(1) }
        let marker = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'checking shard'")).allElementsBoundByIndex
            .first { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < (dock.exists ? dock.frame.minY : 700) - 40 }
        let label = try XCTUnwrap(marker?.label, "no step on screen to keep the place by")
        let before = try XCTUnwrap(marker?.frame)
        mark("reading at \"\(label.prefix(40))\" y \(Int(before.minY))")
        shot("reader-before")
        away(setting("HERMES_E2E_AWAY", 45))
        let same = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(same.waitForExistence(timeout: 8), "the row the reader was at is gone after coming back")
        sleep(1)
        let after = same.frame
        mark("back at y \(Int(after.minY))")
        shot("reader-after")
        XCTAssertLessThan(abs(after.minY - before.minY), 40, "the reader's place moved \(Int(after.minY - before.minY)) pt coming back")
    }
}
