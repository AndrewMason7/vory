import XCTest

/// Select mode's controls on the iPhone (#408): the morph bar draws them in its own capsules,
/// Done where the bot's circle sits, the count as the title, the selection's actions where the
/// list's + and filters sit; nothing of the list's stands under the bar. A tester's screenshot
/// had Done behind the bot circle and the actions behind + and the filters, out of reach.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set. HERMES_E2E_BUNDLE=
/// com.vorantx.vory.demo drives the demo copy. HERMES_E2E_SHOTS names a folder for the stills.
@MainActor
final class SelectModeBarUITests: XCTestCase {
    private var app: XCUIApplication!
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let folder = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"].flatMap { $0.isEmpty ? nil : $0 }
        let d = folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hermes-chat-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: d.appendingPathComponent("\(name).png"))
    }

    private func row(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).allElementsBoundByIndex.first { $0.isHittable }
            ?? app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
    }

    /// The controls in the bar's band, by label, left to right. A control's icon is listed again
    /// on its own at the control's frame: one entry per frame, the first.
    private func barControls() -> [(label: String, frame: CGRect)] {
        var seen = Set<String>()
        return app.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.frame.minY < 120 && $0.frame.height > 0 && $0.frame.height < 80 && $0.isHittable }
            .map { ($0.label, $0.frame) }
            .filter { seen.insert("\(Int($0.1.minX.rounded())),\(Int($0.1.maxX.rounded()))").inserted }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    func testSelectModesControlsStandInTheBarAlone() throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = false
        if let bundle = e["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats", "-colorSchemePreference", "dark"]
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-launchTab", "chats", "-colorSchemePreference", "dark"]
        }
        app.launch()
        XCTAssertTrue(row("Rewrite the nightly export job").waitForExistence(timeout: 40), "no chat rows")
        pause(2)

        // Select from a row's menu: that row is picked.
        row("Weekly dependency audit").press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Select"].firstMatch.waitForExistence(timeout: 5), "no Select in the row's menu")
        app.buttons["Select"].firstMatch.tap()
        pause(1.5)
        shot("select-bar-one-picked")

        let done = app.buttons["chats.select.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5) && done.isHittable, "no Done to tap")
        XCTAssertEqual(app.staticTexts["morph.title"].firstMatch.label, "1 Selected")
        // Nothing of the list's under the bar: no bot circle, no + or filters, and each control once.
        let controls = barControls()
        print("SELECT-BAR \(controls.map { "\($0.label)@\(Int($0.frame.minX))-\(Int($0.frame.maxX))" })")
        XCTAssertFalse(app.buttons["chats.profile"].firstMatch.exists, "the bot circle is still in the bar")
        for gone in ["New bot", "Sort", "Filters"] {
            XCTAssertFalse(controls.contains { $0.label == gone }, "\(gone) is still in the bar while selecting")
        }
        for (a, b) in zip(controls, controls.dropFirst()) {
            XCTAssertLessThanOrEqual(a.frame.maxX, b.frame.minX + 1, "\(a.label) and \(b.label) overlap in the bar")
        }
        // VoiceOver: Done first, then the actions.
        let labels = controls.map(\.label)
        XCTAssertEqual(labels.first, "Done")
        XCTAssertEqual(Array(labels.suffix(2)), ["Archive", "Delete"])
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .elementDetection]) { issue in
            print("SELECT-AUDIT '\(issue.compactDescription)' label '\(issue.element?.label ?? "")' id '\(issue.element?.identifier ?? "")'")
            // Fail on anything in the bar's band.
            return (issue.element?.frame.minY ?? 1000) > 120
        }

        // Nothing picked: the actions wait.
        row("Weekly dependency audit").tap()
        pause(1)
        XCTAssertEqual(app.staticTexts["morph.title"].firstMatch.label, "Select Chats")
        // Off, and said so: a button that is not enabled is read "dimmed" by VoiceOver.
        for id in ["chats.select.move", "chats.select.archive", "chats.select.delete"] where app.buttons[id].firstMatch.exists {
            XCTAssertFalse(app.buttons[id].firstMatch.isEnabled, "\(id) is on with nothing picked")
        }
        shot("select-bar-none-picked")

        // Done: the list's bar again.
        done.tap()
        pause(1.5)
        XCTAssertTrue(app.buttons["chats.profile"].firstMatch.waitForExistence(timeout: 5), "the bot circle did not come back")
        XCTAssertEqual(app.staticTexts["morph.title"].firstMatch.label, "Chats")
        XCTAssertFalse(app.buttons["chats.select.done"].firstMatch.exists, "Done stayed after Done")
        shot("select-bar-after-done")
    }

    private func launchOnChats() throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        if let bundle = e["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats", "-colorSchemePreference", "dark"]
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-launchTab", "chats", "-colorSchemePreference", "dark"]
        }
        app.launch()
        XCTAssertTrue(row("Rewrite the nightly export job").waitForExistence(timeout: 40), "no chat rows")
        pause(2)
    }

    /// The row titled `title`, scrolled clear of the bar above and the tab bar below (the mock's
    /// extra chats sit below the first screen; a row under the tab bar is "hittable" but a press
    /// there lands on the tab bar).
    private func reveal(_ title: String) -> XCUIElement {
        let height = app.windows.firstMatch.frame.height
        func clear() -> Bool { let r = row(title); return r.isHittable && r.frame.midY > 140 && r.frame.midY < height - 130 }
        for _ in 0..<8 where !clear() { app.swipeUp(velocity: .slow); pause(0.5) }
        for _ in 0..<12 where !clear() { app.swipeDown(velocity: .slow); pause(0.5) }
        return row(title)
    }

    /// Select mode from a row's menu, with that row picked.
    private func select(from title: String) {
        reveal(title).press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Select"].firstMatch.waitForExistence(timeout: 5), "no Select in \(title)'s menu")
        app.buttons["Select"].firstMatch.tap()
        pause(1.5)
        XCTAssertEqual(app.staticTexts["morph.title"].firstMatch.label, "1 Selected")
    }

    /// (a) and (b) of the tester's follow-up on 26 ("selecting chats doesn't actually select
    /// them", and a long press opened the row's usual menu): in Select mode a tap picks and
    /// unpicks a row, the count and the actions follow it, and a long press or a swipe opens no
    /// menu of the row's own.
    func testInSelectModeATapPicksAndALongPressOpensNoMenu() throws {
        continueAfterFailure = true
        try launchOnChats()
        select(from: "Weekly dependency audit")
        let archive = app.buttons["chats.select.archive"].firstMatch

        reveal("Backup verification").tap(); pause(1)
        XCTAssertEqual(app.staticTexts["morph.title"].firstMatch.label, "2 Selected", "a tap did not pick the row")
        XCTAssertTrue(archive.isEnabled, "Archive is off with two picked")
        reveal("Backup verification").tap(); pause(1)
        XCTAssertEqual(app.staticTexts["morph.title"].firstMatch.label, "1 Selected", "a second tap did not unpick the row")
        shot("select-tap-toggles")

        // A long press: no Open, Pin, Select or Ask Siri of the row's own.
        reveal("Rotate the API keys").press(forDuration: 1.2); pause(1)
        shot("select-long-press")
        // The bar's own Move to Project (chats.select.move) is the selection's, not the row's.
        for item in ["Open", "Select", "Pin", "Ask Siri", "Move to Project"] {
            let rowItem = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'chats.select')", item)).firstMatch
            XCTAssertFalse(rowItem.exists, "a long press in Select mode opened the row's menu (\(item))")
        }
        let title = app.staticTexts["morph.title"].firstMatch.label
        XCTAssertTrue(["1 Selected", "2 Selected"].contains(title), "Select mode left after the long press: \(title)")
        if title == "2 Selected" { reveal("Rotate the API keys").tap(); pause(1) }

        // A swipe: no Delete or Archive of the row's own (the bar's are the selection's).
        reveal("Rotate the API keys").swipeLeft(); pause(1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Delete'")).count, 1, "a swipe in Select mode showed the row's Delete")
        shot("select-swipe")
        app.buttons["chats.select.done"].firstMatch.tap(); pause(1)
    }

    /// (c): the bar's Archive acts on exactly the chats picked, and the others stay.
    func testTheSelectionsArchiveTakesThePickedChatsOnly() throws {
        continueAfterFailure = true
        try launchOnChats()
        select(from: "Standup notes")
        reveal("Trim the CI cache").tap(); pause(1)
        XCTAssertEqual(app.staticTexts["morph.title"].firstMatch.label, "2 Selected")
        shot("select-two-picked")
        app.buttons["chats.select.archive"].firstMatch.tap(); pause(3)
        shot("select-after-archive")
        // The picked two are archived (the list shows archived chats by default, marked
        // "Archived"); the rest are not.
        for picked in ["Standup notes", "Trim the CI cache"] {
            let label = reveal(picked).label
            XCTAssertTrue(label.hasPrefix("Archived"), "\(picked) was not archived: \(label)")
        }
        for kept in ["Rotate the API keys", "Backup verification", "Weekly dependency audit", "Rewrite the nightly export job"] {
            let label = reveal(kept).label
            XCTAssertFalse(label.hasPrefix("Archived"), "\(kept) was archived with the selection: \(label)")
        }
    }

    /// The selection's Delete takes the picked chats off the gateway: gone from the list, and still gone once the list is
    /// read again. A Hermes that fences its edits (#467; the mock's MOCK_FENCE=1) refused a delete without the chat's
    /// revision, the app swallowed the refusal, and the chats came back with the next list.
    func testTheSelectionsDeleteTakesThePickedChatsForGood() throws {
        continueAfterFailure = true
        try launchOnChats()
        select(from: "Standup notes")
        reveal("Trim the CI cache").tap(); pause(1)
        XCTAssertEqual(app.staticTexts["morph.title"].firstMatch.label, "2 Selected")
        app.buttons["chats.select.delete"].firstMatch.tap()
        let confirm = app.alerts.firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete did not ask first")
        confirm.buttons["Delete"].tap(); pause(3)
        shot("select-after-delete")
        XCTAssertFalse(app.alerts.firstMatch.exists, "the delete was refused: \(app.alerts.firstMatch.label)")
        // The list read again from the gateway, in a new launch.
        app.terminate()
        try launchOnChats()
        for gone in ["Standup notes", "Trim the CI cache"] {
            XCTAssertFalse(reveal(gone).exists, "\(gone) came back after it was deleted")
        }
        XCTAssertTrue(reveal("Rotate the API keys").exists, "a chat that was not picked went too")
    }

    /// A delete the gateway refuses says why, in words, and the chat stays. Needs the mock refusing every fenced edit
    /// with session_busy (MOCK_FENCE=1 MOCK_FENCE_REFUSE=session_busy), named in HERMES_E2E_ARGS as
    /// "fence-refuse=session_busy"; skipped otherwise.
    func testARefusedDeleteSaysWhyAndKeepsTheChat() throws {
        guard (ProcessInfo.processInfo.environment["HERMES_E2E_ARGS"] ?? "").contains("fence-refuse=session_busy") else {
            throw XCTSkip("needs the mock refusing fenced edits with session_busy")
        }
        continueAfterFailure = true
        try launchOnChats()
        select(from: "Standup notes")
        app.buttons["chats.select.delete"].firstMatch.tap()
        let confirm = app.alerts.firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete did not ask first")
        confirm.buttons["Delete"].tap()
        let refusal = app.alerts.matching(NSPredicate(format: "label BEGINSWITH %@", "Could not delete")).firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 10), "the refused delete said nothing")
        let why = refusal.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "A turn is running")).firstMatch
        XCTAssertTrue(why.exists, "the refusal is not in plain words")
        shot("select-delete-refused")
        if refusal.buttons["OK"].exists { refusal.buttons["OK"].tap() }
        pause(2)
        XCTAssertTrue(reveal("Standup notes").exists, "the refused chat left the list")
    }
}
