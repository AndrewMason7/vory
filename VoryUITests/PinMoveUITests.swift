import XCTest

/// #372 (Matt on 24: "the pinned chats at the top has poor animations and stutters"): pinning a
/// chat moves its row up into the pinned rows once its swipe or its menu has closed, with nothing
/// left behind in its old place; unpinning moves it back down the same way; and the swipe on a
/// pinned row opens as any other. The marks are wall-clock, to line up with a recording of the run.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set. HERMES_E2E_BUNDLE=
/// com.vorantx.vory.demo drives the demo copy, pointed at the gateway by launch argument.
@MainActor
final class PinMoveUITests: XCTestCase {
    private var app: XCUIApplication!
    private let titles = ["Disk cleanup", "Rewrite the nightly export job", "Weekly dependency audit"]
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    private func mark(_ s: String) { print("PIN-AT \(s) \(String(format: "%.3f", Date().timeIntervalSince1970))") }

    private func launch() throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = false
        if let bundle = e["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats", "-colorSchemePreference", "light"]
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-launchTab", "chats", "-colorSchemePreference", "light"]
        }
        app.launch()
        XCTAssertTrue(row("Rewrite the nightly export job").waitForExistence(timeout: 40), "no chat rows")
        pause(3)
    }

    private func row(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).allElementsBoundByIndex.first { $0.isHittable }
            ?? app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
    }

    /// Rows top to bottom, by their titles.
    private func order() -> [String] {
        titles.compactMap { t -> (String, CGFloat)? in
            let r = row(t)
            return r.exists ? (t, r.frame.minY) : nil
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    func testPinAndUnpinMoveTheRow() throws {
        try launch()
        let before = order()
        print("PIN-ORDER before \(before)")

        // Pin: the leading swipe, then Pin.
        mark("pin swipe")
        row("Weekly dependency audit").swipeRight()
        let pin = app.buttons["Pin"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "no Pin action")
        mark("pin tap")
        pin.tap()
        pause(2.4)
        let pinned = order()
        print("PIN-ORDER pinned \(pinned)")
        XCTAssertEqual(pinned.firstIndex(of: "Weekly dependency audit").map { $0 < 2 }, true, "the pinned row did not move up into the pinned rows")

        // The swipe on a pinned row, opened and held.
        mark("reveal")
        row("Weekly dependency audit").swipeRight()
        let unpin = app.buttons["Unpin"].firstMatch
        XCTAssertTrue(unpin.waitForExistence(timeout: 5), "no Unpin action")
        pause(1.5)

        // Unpin: back down.
        mark("unpin tap")
        unpin.tap()
        pause(2.5)
        let after = order()
        print("PIN-ORDER after \(after)")
        XCTAssertEqual(after, before, "unpinning did not put the row back where it was")
        mark("done")
    }

    /// The same move from the row's menu (no swipe): pressed and held, Pin; then Unpin the same way.
    func testPinFromTheMenu() throws {
        try launch()
        let before = order()
        mark("menu press")
        row("Weekly dependency audit").press(forDuration: 1.0)
        let pin = app.buttons["Pin"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "no Pin in the menu")
        mark("menu pin")
        pin.tap()
        pause(2.4)
        let pinned = order()
        print("PIN-ORDER menu pinned \(pinned)")
        XCTAssertEqual(pinned.firstIndex(of: "Weekly dependency audit").map { $0 < 2 }, true, "the pinned row did not move up into the pinned rows")

        row("Weekly dependency audit").press(forDuration: 1.0)
        let unpin = app.buttons["Unpin"].firstMatch
        XCTAssertTrue(unpin.waitForExistence(timeout: 5), "no Unpin in the menu")
        mark("menu unpin")
        unpin.tap()
        pause(2.4)
        XCTAssertEqual(order(), before, "unpinning from the menu did not put the row back where it was")
        mark("done")
    }
}
