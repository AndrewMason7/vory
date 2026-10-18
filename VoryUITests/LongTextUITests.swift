import XCTest

/// #361: texts too long to draw as one picture, drawn in pieces. With the mock's `huge …` prompts: a 100 KB
/// single-paragraph reasoning opened, scrolled, shown whole on its titled sheet and closed; a reply with a 2,000-line
/// code block scrolled; a tool card with 20,000 characters of output opened and shown in full. Then, with the reasoning
/// open, the text size goes to the largest accessibility size (the host changes it when the test asks, see
/// `askHost`) and the reasoning must still be in view. The debug probe (`-vory-piece-probe`) reports the tallest
/// text drawn; it must stay under the graphics card's 16,384 px. Frames land where HERMES_E2E_SHOTS says, and each
/// step prints a `LONGTEXT` line with the time, for the host's memory samples.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set; HERMES_E2E_BUNDLE=com.vorantx.vory.demo drives the demo
/// copy, pointed at the gateway by launch argument.
@MainActor
final class LongTextUITests: XCTestCase {
    private var app: XCUIApplication!
    private let textureLimit: Double = 16_384

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }
    private var folder: URL {
        let f = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"].flatMap { $0.isEmpty ? nil : $0 }
        let d = f.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hermes-chat-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func mark(_ step: String) {
        print(String(format: "LONGTEXT %.3f %@ | %@", Date().timeIntervalSince1970, step, probe()))
    }
    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        try? s.pngRepresentation.write(to: folder.appendingPathComponent("longtext-\(name).png"))
        mark("shot \(name)")
    }
    /// The probe's line: "tallest <pt> pt, <px> px, <n> texts".
    private func probe() -> String {
        let e = app.staticTexts["debug.pieces"].firstMatch
        return e.exists ? e.label : "no probe"
    }
    private func tallestPixels() -> Double {
        let parts = probe().components(separatedBy: CharacterSet(charactersIn: " ,"))
        guard let i = parts.firstIndex(of: "px"), i > 0 else { return .nan }
        return Double(parts[i - 1]) ?? .nan
    }
    /// Asks the host to do something (change the text size) and waits until it says it did: a file each way in the
    /// shots folder, which the simulator's processes share with the host.
    private func askHost(_ request: String, timeout: TimeInterval = 60) -> Bool {
        let done = folder.appendingPathComponent("longtext-done-\(request)")
        try? FileManager.default.removeItem(at: done)
        try? request.write(to: folder.appendingPathComponent("longtext-ask-\(request)"), atomically: true, encoding: .utf8)
        mark("asked host: \(request)")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: done.path) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    private func text(_ fragment: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
    }
    private func button(_ fragment: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
    }
    private func hittable(_ query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let e = query.allElementsBoundByIndex.last(where: { $0.exists && $0.isHittable }) { return e }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    /// Sends a prompt and waits for its turn to end (no Stop button), then puts the keyboard away.
    private func send(_ prompt: String) {
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText(prompt)
        if let send = hittable(app.buttons.matching(identifier: "composer.send"), timeout: 5) { send.tap() }
        mark("sent \(prompt)")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline, button("Stop").firstMatch.exists { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        // The keyboard away: a drag from the field down past it (the thread lets it go interactively).
        if app.keyboards.firstMatch.exists {
            let from = composer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        mark("answered \(prompt); keyboard up: \(app.keyboards.firstMatch.exists)")
    }

    func testLongTextsDrawInPiecesUnderTheTextureLimit() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"] ?? ""
        app = bundle.isEmpty ? XCUIApplication() : XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = ["-vory-piece-probe", "-companionPromptShown", "YES", "-colorSchemePreference", "light"]
        if !bundle.isEmpty { app.launchArguments += ["-vory-demo-gateway", url, token, "Workshop"] }
        app.launch()
        mark("launched")

        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()
        mark("chat open")

        // The reasoning: 100 KB in one paragraph.
        send("huge reasoning 100")
        let show = try XCTUnwrap(hittable(button("Show reasoning"), timeout: 10), "no Show reasoning")
        show.tap(); RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertTrue(text("The export retried shard 1 ").firstMatch.waitForExistence(timeout: 10) || text("The export retried shard").firstMatch.exists, "the reasoning's text is not there")
        shot("reasoning-open")
        // Show all: a titled sheet with the whole text, Done reachable.
        var all = hittable(button("Show all"), timeout: 5)
        for _ in 0..<8 where all == nil { app.swipeUp(); all = hittable(button("Show all"), timeout: 2) }
        let showAll = try XCTUnwrap(all, "no Show all under the capped reasoning")
        mark("Show all: \(showAll.label)")
        let all_ = showAll
        all_.tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS[c] 'Reasoning'")).firstMatch.waitForExistence(timeout: 10)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '· Reasoning'")).firstMatch.exists, "the sheet's title does not say Reasoning")
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5), "the sheet has no text")
        XCTAssertTrue(app.buttons["Done"].firstMatch.exists, "the sheet has no Done")
        shot("reasoning-sheet")
        // The sheet audited: every finding logged (the run does not fail on the screen behind it).
        var findings: [String] = []
        try? app.performAccessibilityAudit { issue in
            findings.append("\(issue.auditType) \(issue.element?.label.prefix(40) ?? "") — \(issue.compactDescription)")
            return true
        }
        mark("audit with the sheet open: \(findings.count) findings")
        for f in findings { print("LONGTEXT-AUDIT \(f)") }
        app.textViews.firstMatch.swipeUp(); RunLoop.current.run(until: Date().addingTimeInterval(1)); shot("reasoning-sheet-scrolled")
        app.buttons["Done"].firstMatch.tap(); RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertFalse(app.textViews.matching(NSPredicate(format: "value CONTAINS 'shard 900 '")).firstMatch.exists, "the sheet did not close")
        app.swipeDown(); RunLoop.current.run(until: Date().addingTimeInterval(1)); shot("reasoning-scrolled")
        // The text size goes to the largest accessibility size with the reasoning open: still in view.
        if askHost("ax5") {
            RunLoop.current.run(until: Date().addingTimeInterval(3))
            shot("reasoning-ax5")
            let visible = text("The export retried shard").allElementsBoundByIndex.contains { $0.exists && app.windows.firstMatch.frame.intersects($0.frame) }
            XCTAssertTrue(visible, "the reasoning left the screen when the text size changed")
            mark("ax5 reasoning in view: \(visible)")
            _ = askHost("default")
            RunLoop.current.run(until: Date().addingTimeInterval(3))
        } else {
            mark("host did not change the text size")
        }
        if let hide = hittable(button("Hide reasoning"), timeout: 5) { hide.tap() }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5)); shot("reasoning-closed")

        // The code: a reply with a 2,000-line block.
        send("huge code 2000")
        shot("code-end")
        // The block shows its start; Show all puts the whole log on a titled sheet.
        var codeAll = hittable(button("Show all"), timeout: 3)
        for _ in 0..<6 where codeAll == nil { app.swipeUp(); codeAll = hittable(button("Show all"), timeout: 1) }
        if let codeAll {
            mark("code Show all: \(codeAll.label)")
            codeAll.tap()
            XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Code'")).firstMatch.waitForExistence(timeout: 10), "the code sheet's title does not say Code")
            shot("code-sheet")
            app.buttons["Done"].firstMatch.tap(); RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        } else {
            XCTFail("no Show all under the capped code block")
        }
        for _ in 0..<4 { app.swipeDown() }
        RunLoop.current.run(until: Date().addingTimeInterval(1)); shot("code-scrolled")

        // The tool: 20,000 characters of output, opened and shown in full.
        send("huge tool 20000")
        if let card = hittable(button("export.log"), timeout: 10) {
            card.tap(); RunLoop.current.run(until: Date().addingTimeInterval(2))
            let more = button("more lines").firstMatch
            mark("tool card open; Show more lines reachable: \(more.exists)")
            if more.exists { more.tap(); RunLoop.current.run(until: Date().addingTimeInterval(2)) }
            shot("tool-open")
            app.swipeDown(); RunLoop.current.run(until: Date().addingTimeInterval(1)); shot("tool-scrolled")
        } else {
            mark("no tool card")
        }

        // A long paragraph with a link, drawn in pieces read as one element: the link is still a link to VoiceOver.
        send("huge link 6")
        let link = app.links.matching(NSPredicate(format: "label CONTAINS[c] 'status page'")).firstMatch
        mark("long paragraph's link reachable: \(link.waitForExistence(timeout: 5))")
        shot("link")

        let px = tallestPixels()
        mark("final")
        XCTAssertTrue(px.isFinite, "the probe did not report (\(probe()))")
        XCTAssertLessThan(px, textureLimit, "a text was drawn taller than the graphics card allows: \(probe())")
    }

    /// An ordinary chat pictured for a pixel compare between two builds (short text is still one Text, so it must
    /// match): the showcase chat's end (lists, a bash block), a table reply, a reply with mention chips. Frames go to
    /// HERMES_E2E_SHOTS with the tag in HERMES_E2E_TAG.
    func testAnOrdinaryChatPictured() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        let tag = ProcessInfo.processInfo.environment["HERMES_E2E_TAG"] ?? "run"
        let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"] ?? ""
        app = bundle.isEmpty ? XCUIApplication() : XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = ["-companionPromptShown", "YES", "-colorSchemePreference", "light"]
        if !bundle.isEmpty { app.launchArguments += ["-vory-demo-gateway", url, token, "Workshop"] }
        app.launch()
        let row = text("Disk cleanup on the log host").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 40))
        row.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        if let deny = hittable(app.buttons.matching(identifier: "Deny"), timeout: 3) { deny.tap(); RunLoop.current.run(until: Date().addingTimeInterval(3)) }
        shot("\(tag)-showcase")
        send("table of the shards please")
        shot("\(tag)-table")
        send("mention the others")
        shot("\(tag)-mention")
    }
}
