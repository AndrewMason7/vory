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
}
