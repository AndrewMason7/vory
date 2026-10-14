import XCTest

/// #377: Home's 7d / 30d / 90d range is the system's segmented control (call #35), its options
/// spoken in full, beside "Overview" at the default size and on a row of its own at the
/// accessibility sizes; switching it counts the numbers over (recorded by the harness on the
/// C377 RECORD-NOW and RECORD-END lines). Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are
/// set; HERMES_E2E_BUNDLE picks the copy (the demo by default).
@MainActor
final class HomeRangeUITests: XCTestCase {
    private var app: XCUIApplication!

    private func mark(_ what: String) { print(String(format: "C377 %.2f %@", Date().timeIntervalSince1970, what)) }
    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let folder = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"].flatMap { $0.isEmpty ? nil : $0 }
        let d = folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hermes-chat-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: d.appendingPathComponent("\(name).png"))
    }

    /// Home, with the range control found and its options spoken in full.
    private func home(_ extra: [String] = []) throws -> XCUIElement {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set")
        }
        app = XCUIApplication(bundleIdentifier: e["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.vorantx.vory.demo")
        // No range in the launch arguments: the argument domain would outrank the app's writes.
        app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["chats.new"].firstMatch.waitForExistence(timeout: 40), "no chat list")
        any("tab.dashboard").tap()
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "no range control")
        for label in ["7 days", "30 days", "90 days"] {
            XCTAssertTrue(picker.buttons[label].exists, "the range option \(label) is not spoken in full: \(picker.buttons.allElementsBoundByIndex.map { $0.label })")
        }
        // From 30 days, whatever the last run left.
        picker.buttons["30 days"].tap()
        sleep(2)
        return picker
    }

    func testRangeSwitchRecorded() throws {
        let picker = try home()
        let title = app.staticTexts["Overview"].firstMatch
        mark("header: title \(title.frame) picker \(picker.frame)")
        XCTAssertLessThan(abs(picker.frame.midY - title.frame.midY), 12, "at the default size the range is not beside the title")
        shot("c377-default")
        mark("RECORD-NOW")
        sleep(2)
        for label in ["7 days", "90 days", "30 days"] {
            mark("tap \(label)")
            picker.buttons[label].tap()
            sleep(3)
            XCTAssertTrue(picker.buttons[label].isSelected, "\(label) is not selected after its tap")
        }
        mark("RECORD-END")
    }

    func testRangeHasItsOwnRowAtAnAccessibilitySize() throws {
        let picker = try home(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        let title = app.staticTexts["Overview"].firstMatch
        mark("ax header: title \(title.frame) picker \(picker.frame)")
        XCTAssertGreaterThanOrEqual(picker.frame.minY, title.frame.maxY - 1, "at an accessibility size the range is not under the title")
        shot("c377-ax")
        picker.buttons["7 days"].tap()
        sleep(2)
        XCTAssertTrue(picker.buttons["7 days"].isSelected, "7 days is not selected after its tap")
    }

    /// The accessibility audit on Home, failing only on the Overview's header (the change).
    func testHomeRangeAuditClean() throws {
        let picker = try home()
        let title = app.staticTexts["Overview"].firstMatch
        let region = title.frame.union(picker.frame).insetBy(dx: -4, dy: -4)
        var flagged: [String] = []
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .elementDetection]) { issue in
            guard let el = issue.element else { print("C377-AUDIT '\(issue.compactDescription)' no element"); return true }
            let line = "'\(issue.compactDescription)' type \(el.elementType.rawValue) id '\(el.identifier)' label '\(el.label)' frame \(el.frame)"
            print("C377-AUDIT \(line)")
            if region.intersects(el.frame), el.frame.width < region.width + 1 { flagged.append(line) }
            return true
        }
        XCTAssertTrue(flagged.isEmpty, "the audit flags the range control: \(flagged)")
    }
}
