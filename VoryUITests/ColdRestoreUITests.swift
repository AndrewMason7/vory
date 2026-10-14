import XCTest

/// #371: the system ends a suspended app when another needs the memory, and the next open is a
/// cold launch. It comes back to the chat that was open, not the chat list (which testers read as
/// "it crashed in the background"); a chat that was closed before leaving stays closed.
///
/// The app is ended while it is in the background, as the system ends it (see
/// `endedInTheBackgroundAndOpenedAgain`), then launched again.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set. HERMES_E2E_BUNDLE=
/// com.vorantx.vory.demo drives the demo copy, pointed at the gateway by launch argument.
final class ColdRestoreUITests: XCTestCase {
    private var app: XCUIApplication!
    private var url = ""
    private var token = ""

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private var demo: String? {
        ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 }
    }

    private func launch() {
        if let demo {
            app = XCUIApplication(bundleIdentifier: demo)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES"]
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-companionPromptShown", "YES"]
        }
        app.launch()
        if demo == nil { connectIfNeeded() }
    }

    /// On the list to start with: a test before may have left a chat for the restore to reopen.
    private func fromTheList() {
        if dock.waitForExistence(timeout: 4) {
            let back = app.buttons.matching(identifier: "chat.back").firstMatch
            if back.waitForExistence(timeout: 5) { back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        }
        XCTAssertTrue(app.buttons["chats.new"].firstMatch.waitForExistence(timeout: 15), "not on the list")
    }

    private func connectIfNeeded() {
        let start = app.buttons["onboarding.getStarted"].firstMatch
        let skip = app.buttons["onboarding.skip"].firstMatch
        let add = app.buttons["onboarding.addGateway"].firstMatch
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline, !(start.exists || skip.exists || add.exists || rows.exists || dock.exists) { sleep(1) }
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

    private var dock: XCUIElement { app.descendants(matching: .any).matching(identifier: "chat.dock").firstMatch }

    private func openDiskCleanup() {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 40), "no Disk cleanup row")
        sleep(1)
        row.tap()
        XCTAssertTrue(dock.waitForExistence(timeout: 20), "the chat did not open")
        sleep(2)
    }

    /// Home, then ended in the background as the system ends it, then opened again. With
    /// HERMES_E2E_HOSTKILL=1 the host ends it (a SIGKILL on the test's KILL-NOW line, the usual way
    /// to check state restoration, which keeps the scene's storage as a system end does);
    /// otherwise XCTest's terminate, which may count as the person swiping the app away.
    private func endedInTheBackgroundAndOpenedAgain() {
        XCUIDevice.shared.press(.home)
        sleep(3)
        if ProcessInfo.processInfo.environment["HERMES_E2E_HOSTKILL"] == "1" {
            print(String(format: "C371 %.1f KILL-NOW", Date().timeIntervalSince1970))
            sleep(8)
        } else {
            app.terminate()
            sleep(1)
        }
        launch()
    }

    func testTheChatOpenWhenTheAppWasEndedInTheBackgroundComesBack() throws {
        guard let (u, t) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        url = u; token = t
        launch()
        fromTheList()
        openDiskCleanup()
        endedInTheBackgroundAndOpenedAgain()
        XCTAssertTrue(dock.waitForExistence(timeout: 30), "a cold launch after the app was ended in the background did not reopen the chat")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch.waitForExistence(timeout: 10)
                      || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch.exists,
                      "the reopened chat is not the one that was open")
    }

    func testAChatClosedBeforeLeavingStaysClosed() throws {
        guard let (u, t) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        url = u; token = t
        launch()
        fromTheList()
        openDiskCleanup()
        let back = app.buttons.matching(identifier: "chat.back").firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["chats.new"].firstMatch.waitForExistence(timeout: 10), "not back on the list")
        sleep(1)
        endedInTheBackgroundAndOpenedAgain()
        XCTAssertTrue(app.buttons["chats.new"].firstMatch.waitForExistence(timeout: 30), "no chat list after the cold launch")
        sleep(3)
        XCTAssertFalse(dock.exists, "a chat closed before leaving was opened again")
    }

    /// Away and back, then ended in front (a crash there, or a test ending the app): what the
    /// time away saved is not this end's, and the relaunch is on the list.
    func testAnEndInFrontDoesNotReopenWhatWasOpenAway() throws {
        guard let (u, t) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        url = u; token = t
        launch()
        fromTheList()
        openDiskCleanup()
        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        XCTAssertTrue(dock.waitForExistence(timeout: 10), "not back in the chat")
        sleep(2)
        app.terminate()
        sleep(1)
        launch()
        XCTAssertTrue(app.buttons["chats.new"].firstMatch.waitForExistence(timeout: 30), "no chat list after the cold launch")
        sleep(3)
        XCTAssertFalse(dock.exists, "a chat saved by an earlier time away was reopened after an end in front")
    }
}
