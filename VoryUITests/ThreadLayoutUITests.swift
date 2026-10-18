import XCTest

/// Rows of the thread must never be drawn over one another, while a turn streams or after it:
/// testers sent screenshots of a reply drawn over their own bubble and of tool cards stacked
/// over the reply's text mid-turn. The mock gateway answers a prompt starting "tools" with a long
/// turn that is mostly tool calls (a dozen cards, words between some of them, a long answer);
/// three of them in a row make a thread long enough for its older rows to go lazy while the
/// newest one streams. Every row is an element named "thread.row.<kind>" (the typing bubble and
/// the status line are "thread.typing" and "thread.status"), so each check compares the frames
/// of neighbours in thread order: the next one must start below the one before it ends.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set. HERMES_E2E_BUNDLE=com.vorantx.vory.demo
/// drives the demo copy (Tools/dev/make-demo-app-sim.sh), pointed at the gateway by launch
/// argument. HERMES_E2E_SHOTS names a folder for the screenshots.
@MainActor
final class ThreadLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

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

    private func launch(url: String, token: String) {
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES"]
        } else {
            app = XCUIApplication()
        }
        app.launch()
    }

    private func cell(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    private struct Row { var id: String; var frame: CGRect; var words = "" }

    /// The thread's rows in thread order, from one snapshot of the app, each with the start of
    /// its first text (for the report).
    private func threadRows() -> [Row] {
        guard let snap = try? app.snapshot() else { return [] }
        var out: [Row] = []
        func firstText(_ s: XCUIElementSnapshot) -> String? {
            if s.elementType == .staticText, !s.label.isEmpty { return String(s.label.prefix(24)) }
            for c in s.children { if let t = firstText(c) { return t } }
            return nil
        }
        func walk(_ s: XCUIElementSnapshot) {
            if s.identifier.hasPrefix("thread.") { out.append(Row(id: s.identifier, frame: s.frame, words: firstText(s) ?? "")); return }
            for c in s.children { walk(c) }
        }
        walk(snap)
        return out
    }

    /// Neighbours that are drawn over each other: the later row starts above the end of the one
    /// before it (a point of slack for rounding).
    private func overlaps(_ rows: [Row]) -> [String] {
        zip(rows, rows.dropFirst()).compactMap { a, b in
            guard a.frame.height > 0, b.frame.height > 0, b.frame.minY < a.frame.maxY - 1 else { return nil }
            return "\(a.id) '\(a.words)' y \(Int(a.frame.minY))...\(Int(a.frame.maxY)) then \(b.id) '\(b.words)' y \(Int(b.frame.minY))...\(Int(b.frame.maxY))"
        }
    }

    private var problems: [String] = []
    private var overlapShots = 0
    private var checks = 0

    /// The band's fade above the dock and below the header (`ChatStyle.bandFade`), with a point
    /// of slack for rounding.
    private let bandFade: CGFloat = 28
    private var dock: XCUIElement { app.otherElements["chat.dock"].firstMatch }
    private var header: XCUIElement { app.otherElements["chat.header"].firstMatch }

    /// At the end of the thread, its last row (a card, the typing bubble "thread.typing", the
    /// status line "thread.status") ends clear of the bar (an 8 pt margin): nothing is hidden
    /// at rest; only while scrolling does text pass behind the field's glass.
    private func checkEndClearsTheDock(_ label: String) {
        let rows = threadRows().filter { $0.frame.height > 0 }
        guard let last = rows.max(by: { $0.frame.maxY < $1.frame.maxY }), dock.exists else { XCTFail("\(label): no rows or no dock"); return }
        let gap = dock.frame.minY - last.frame.maxY
        if gap < 6 { shot("thread-end-under-dock-\(label)") }
        XCTAssertGreaterThanOrEqual(gap, 6, "\(label): \(last.id) ends \(Int(gap)) pt above the dock: under the bar")
    }

    /// At the top of the thread, its first row starts below the header band's fade.
    private func checkTopClearsTheHeader(_ label: String) {
        let rows = threadRows().filter { $0.frame.height > 0 }
        guard let first = rows.min(by: { $0.frame.minY < $1.frame.minY }), header.exists else { XCTFail("\(label): no rows or no header"); return }
        let gap = first.frame.minY - header.frame.maxY
        if gap < bandFade - 1 { shot("thread-top-under-band-\(label)") }
        XCTAssertGreaterThanOrEqual(gap, bandFade - 1, "\(label): \(first.id) starts \(Int(gap)) pt below the header, inside the \(Int(bandFade)) pt fade")
    }

    /// On-screen overlaps that held from one check to the next (#410): what a person sees. A
    /// lone snapshot taken mid-layout can put a row a few points into its neighbour, and the
    /// lazy stack's rows far above the screen sit at its guesses; neither is drawn over anything.
    private var lasting: [String] = []
    private var lastOnScreen: Set<String> = []

    private func noteOnScreen(_ rows: [Row], _ label: String) {
        let top = header.exists ? header.frame.maxY : 0
        let bottom = dock.exists ? dock.frame.minY : app.frame.maxY
        var now: Set<String> = []
        for (a, b) in zip(rows, rows.dropFirst()) where a.frame.height > 0 && b.frame.height > 0 && b.frame.minY < a.frame.maxY - 1 {
            // The band where they overlap, on screen between the header and the dock.
            guard min(a.frame.maxY, b.frame.maxY) > top, max(a.frame.minY, b.frame.minY) < bottom else { continue }
            let key = "\(a.id) '\(a.words)' then \(b.id) '\(b.words)'"
            now.insert(key)
            if lastOnScreen.contains(key), !lasting.contains(where: { $0.hasSuffix(key) }) {
                lasting.append("\(label): \(key)")
                shot("thread-lasting-\(lasting.count)")
            }
        }
        lastOnScreen = now
    }

    private func check(_ label: String) {
        let rows = threadRows()
        checks += 1
        noteOnScreen(rows, label)
        let bad = overlaps(rows)
        guard !bad.isEmpty else { return }
        problems += bad.map { "\(label): \($0)" }
        for b in bad { print("THREAD-OVERLAP \(label): \(b)") }
        if overlapShots < 8 { overlapShots += 1; shot("thread-overlap-\(overlapShots)-\(label)") }
    }

    /// Sends a "tools" turn and checks the rows over and over while it streams, until its last
    /// words are on screen.
    private func streamTurn(_ n: Int, prompt: String = "tools", dockCheck: Bool = true) {
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText("\(prompt): check the whole host, pass \(n)")
        // The turn runs while the composer offers Stop; it is over once Stop has come and gone.
        let stop = app.buttons["Stop"].firstMatch
        let send = app.buttons["composer.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        send.tap()
        var sentAt = Date()
        let deadline = Date().addingTimeInterval(90)
        var lastShot = Date.distantPast
        var frame = 0
        var running = false
        while Date() < deadline {
            check("turn\(n)")
            if Date().timeIntervalSince(lastShot) > 3 { frame += 1; shot("thread-turn\(n)-\(frame)"); lastShot = Date() }
            if stop.exists { running = true } else if running { break }
            // A tap that landed while the button was still changing from the mic: once more.
            if !running, Date().timeIntervalSince(sentAt) > 8, send.exists, send.isHittable { send.tap(); sentAt = Date() }
        }
        XCTAssertTrue(running, "turn \(n) never started")
        XCTAssertTrue(cell("start with the first two").exists, "turn \(n) did not finish")
        // The rest after a turn is when older rows move into the lazy stack: checked through it.
        let rest = Date().addingTimeInterval(2.5)
        while Date() < rest { check("turn\(n)-settling") }
        shot("thread-turn\(n)-done")
        guard dockCheck else { return }
        // Settled at the end: the last row clears the dock's band, keyboard up and down.
        checkEndClearsTheDock("turn\(n)-keyboard-up")
        if app.keyboards.buttons["Hide keyboard"].firstMatch.exists {
            app.keyboards.buttons["Hide keyboard"].firstMatch.tap()
            sleep(1)
            checkEndClearsTheDock("turn\(n)-keyboard-down")
        }
    }

    /// The same, with every tool call carrying the same id, as from a provider that numbers its
    /// calls per response and a gateway that passes the id through (#410): each call is still a
    /// row of its own, and no row lands on another.
    func testRowsNeverOverlapWhenToolCallsShareAnID() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = false
        launch(url: url, token: token)
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()
        for n in 1...2 { streamTurn(n, prompt: "tools same ids", dockCheck: false) }
        let tools = threadRows().filter { $0.id == "thread.row.tool" }.count
        print("THREAD-LAYOUT same ids: checks \(checks), problems \(problems.count), tool rows \(tools)")
        XCTAssertGreaterThan(tools, 6, "the calls that share an id are not each a row")
        XCTAssertGreaterThan(checks, 10, "too few checks to mean anything")
        XCTAssertTrue(problems.isEmpty, "rows drawn over each other:\n" + problems.prefix(20).joined(separator: "\n"))
    }

    /// One turn longer than the thread's live tail holds (a step of words and a tool call, dozens
    /// of times: a coding bot's long run), with the keyboard up as the tester had it (#410): the
    /// rows the lazy stack takes over mid-turn must not leave the newest ones drawn over a reply.
    func testRowsNeverOverlapThroughATurnLongerThanTheTail() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = false
        launch(url: url, token: token)
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText("marathon 70")
        let send = app.buttons["composer.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        send.tap()
        let stop = app.buttons["Stop"].firstMatch
        let end = cell("Everything else looked healthy")
        let deadline = Date().addingTimeInterval(240)
        var running = false
        var lastShot = Date.distantPast
        var frame = 0
        // To the report's last words: the whole turn, the rows crossing into the lazy stack included.
        while Date() < deadline, !end.exists {
            check("marathon")
            if Date().timeIntervalSince(lastShot) > 4 { frame += 1; shot("thread-marathon-\(frame)"); lastShot = Date() }
            if stop.exists { running = true }
        }
        XCTAssertTrue(running, "the long turn never started")
        XCTAssertTrue(end.exists, "the long turn did not finish")
        let rest = Date().addingTimeInterval(2.5)
        while Date() < rest { check("marathon-settling") }
        shot("thread-marathon-done")
        print("THREAD-LAYOUT marathon: checks \(checks), any overlap \(problems.count), lasting on screen \(lasting.count)")
        for l in lasting { print("THREAD-LASTING \(l)") }
        XCTAssertGreaterThan(checks, 10, "too few checks to mean anything")
        XCTAssertTrue(lasting.isEmpty, "rows drawn over each other on screen:\n" + lasting.prefix(20).joined(separator: "\n"))
    }

    func testRowsNeverOverlapWhileATurnOfToolCardsStreams() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = false
        launch(url: url, token: token)
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()

        for n in 1...3 { streamTurn(n) }
        XCTAssertGreaterThan(threadRows().filter { $0.id == "thread.row.tool" }.count, 6, "the tool cards are not on screen as rows")

        // Up the thread and back: rows the lazy stack draws for the first time must not land on
        // their neighbours either.
        for i in 1...6 {
            app.swipeDown(velocity: .fast)
            sleep(1)
            check("up\(i)")
        }
        shot("thread-scrolled-up")
        // On to the very top (the first row stops moving), where the first row clears the header's band.
        var topY = threadRows().map(\.frame.minY).min() ?? 0
        for _ in 0..<10 {
            app.swipeDown(velocity: .fast)
            sleep(1)
            let y = threadRows().map(\.frame.minY).min() ?? 0
            if abs(y - topY) < 1 { break }
            topY = y
        }
        shot("thread-top")
        checkTopClearsTheHeader("top")
        for i in 1...8 {
            app.swipeUp(velocity: .fast)
            sleep(1)
            check("down\(i)")
        }
        shot("thread-back-down")
        print("THREAD-LAYOUT checks \(checks), problems \(problems.count)")
        XCTAssertGreaterThan(checks, 30, "too few checks to mean anything")
        XCTAssertTrue(problems.isEmpty, "rows drawn over each other:\n" + problems.prefix(20).joined(separator: "\n"))
    }
}
