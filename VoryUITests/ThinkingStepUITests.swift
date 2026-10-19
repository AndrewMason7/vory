import XCTest

/// #424: a model that thinks before each tool call and says nothing between them (the mock's
/// `steps N`). Each step's reasoning stays as a folded card in its place while the turn runs and
/// after it (a step's card went the moment its tool began), the same after the chat is read again
/// from the gateway (back from the background), and with reasoning hidden in Settings the steps
/// leave no row at all. The cached copy and both shapes of the history are ThinkingStepTests' (the
/// mock does not list a chat started here, so a cold launch cannot reopen it from the list). Each row is an
/// element named "thread.row.<kind>"; a step's card is "thread.row.reasoning". Skipped unless
/// HERMES_E2E_URL / HERMES_E2E_TOKEN are set; HERMES_E2E_BUNDLE picks the copy (the demo).
@MainActor
final class ThinkingStepUITests: XCTestCase {
    private var app: XCUIApplication!

    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func launch(_ extra: [String] = []) throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set")
        }
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: e["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.vorantx.vory.demo")
        app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats",
                               "-colorSchemePreference", "light"] + extra
        app.launch()
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

    /// The thread's rows by kind, from one snapshot of the tree (every row of the thread's end,
    /// on screen or not).
    private func rows(_ kind: String) -> Int {
        guard let snap = try? app.snapshot() else { return -1 }
        var n = 0
        func walk(_ s: XCUIElementSnapshot) {
            if s.identifier.hasPrefix("thread.row.") { if s.identifier == "thread.row." + kind { n += 1 }; return }
            for c in s.children { walk(c) }
        }
        walk(snap)
        return n
    }

    /// Asks the mock to drop every socket it holds.
    private func dropSockets() {
        guard let base = ProcessInfo.processInfo.environment["HERMES_E2E_URL"], let u = URL(string: base + "/mock/drop-sockets") else { return }
        let done = expectation(description: "drop")
        URLSession.shared.dataTask(with: u) { data, _, _ in
            print("C424 MOCK-DROP \(data.map { String(decoding: $0, as: UTF8.self) } ?? "no answer")")
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
    }

    /// A new chat with `steps n` sent; waits for the answer.
    private func runSteps(_ n: Int, during: (() -> Void)? = nil) {
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40), "no chat list")
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "no composer")
        composer.tap()
        composer.typeText("steps \(n)")
        let send = app.buttons.matching(identifier: "composer.send").firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "no send")
        send.tap()
        during?()
        let done = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "all \(n) shards read")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 90), "no answer")
        pause(1.5)
    }

    func testEachStepsReasoningStaysAsACard() throws {
        try launch()
        var midTurn = 0
        runSteps(4) {
            // While the turn runs: once the second step's tool has begun, the first step's card is still there.
            let deadline = Date().addingTimeInterval(40)
            while Date() < deadline, self.rows("tool") < 2 { self.pause(0.3) }
            midTurn = self.rows("reasoning")
        }
        XCTAssertGreaterThanOrEqual(midTurn, 1, "a step's reasoning went when its tool began")
        XCTAssertEqual(rows("reasoning"), 4, "not one card per step after the turn")
        XCTAssertEqual(rows("tool"), 4)
        // The reply is one row; the cards are not replies.
        XCTAssertEqual(rows("reply"), 1, "a step's card counted as a reply")
        shot("424-steps-after-turn")

        // Read again from the gateway: the sockets dropped while the app is away (as iOS does to a
        // suspended app's), so it reconnects on its return and the history's rows take the live
        // ones' place. Those carry no turn statistics: the line going says the rows were replaced.
        let stats = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Turn statistics'"))
        let statsBefore = stats.count
        XCUIDevice.shared.press(.home)
        pause(2)
        dropSockets()
        pause(2)
        app.activate()
        pause(6)
        print("C424 after the re-read: turn statistics \(statsBefore) -> \(stats.count)")
        XCTAssertEqual(rows("reasoning"), 4, "the cards are not the same after the chat was read again")
        XCTAssertEqual(rows("reply"), 1)

        shot("424-steps-after-return")
    }

    func testWithReasoningHiddenTheStepsLeaveNoRow() throws {
        try launch(["-chat.showReasoning", "<false/>"])
        runSteps(4)
        XCTAssertEqual(rows("reasoning"), 0, "a step's card is laid out with reasoning hidden")
        XCTAssertEqual(rows("tool"), 4)
        XCTAssertEqual(rows("reply"), 1)
        XCTAssertFalse(app.buttons["Show reasoning"].firstMatch.exists)
        shot("424-steps-reasoning-hidden")
    }
}
