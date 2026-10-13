import XCTest

/// Finding 6 (#283's check): a gateway form, whose own Cancel is the way back, is not swiped away.
/// Neither the edge swipe nor the full-screen pan pops it: the swipe dropped its edits unasked.
/// The pages around it still go back by a swipe: Gateways, Status and a chat.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set. HERMES_E2E_BUNDLE=com.vorantx.vory.demo
/// drives the demo copy.
@MainActor
final class FormSwipeUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    /// With no URL, the demo starts with no gateway (onboarding).
    private func launch(url: String?, token: String, tab: String) {
        let args = ["-companionPromptShown", "YES", "-launchTab", tab, "-colorSchemePreference", "light"]
        let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"] ?? ""
        app = bundle.isEmpty ? XCUIApplication() : XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = (url.map { ["-vory-demo-gateway", $0, token, "Workshop"] } ?? []) + args
        app.launch()
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    private func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)) }

    /// From the screen's left edge, the system's back swipe.
    private func edgeSwipe() {
        let y = app.frame.height * 0.5
        at(1, y).press(forDuration: 0.05, thenDragTo: at(app.frame.width * 0.8, y), withVelocity: .fast, thenHoldForDuration: 0)
        pause(1.5)
    }

    /// From a third of the way in, the stack's own full-screen back pan.
    private func swipeAcross() {
        let y = app.frame.height * 0.55
        at(app.frame.width * 0.3, y).press(forDuration: 0.05, thenDragTo: at(app.frame.width * 0.95, y), withVelocity: .fast, thenHoldForDuration: 0)
        pause(1.5)
    }

    /// A gateway form in front: its own Cancel and Save.
    private var formUp: Bool { app.navigationBars.buttons["Cancel"].firstMatch.exists && app.navigationBars.buttons["Save"].firstMatch.exists }

    private func cancelForm() { app.navigationBars.buttons["Cancel"].firstMatch.tap(); pause(1.5) }

    /// Settings › Gateways › Edit: the form stays; Gateways still swipes back.
    func testGatewayFormsAreNotSwipedAway() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "settings")
        let gateway = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Workshop'")).firstMatch
        XCTAssertTrue(gateway.waitForExistence(timeout: 20), "no gateway row on Settings")
        pause(2)
        gateway.tap(); pause(1.5)
        XCTAssertTrue(any("page.back").waitForExistence(timeout: 5), "Gateways did not open")
        let edit = app.buttons["Edit Workshop"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit Workshop on Gateways")
        edit.tap(); pause(1.5)
        XCTAssertTrue(formUp, "Edit Gateway did not open")
        edgeSwipe(); shot("edit-after-edge-swipe")
        XCTAssertTrue(formUp, "an edge swipe took Edit Gateway away")
        swipeAcross(); shot("edit-after-swipe-across")
        XCTAssertTrue(formUp, "a swipe across took Edit Gateway away")
        cancelForm()
        XCTAssertTrue(any("settings.addGateway").exists, "Cancel did not return to Gateways")
        // Gateways itself still goes back by a swipe.
        edgeSwipe(); shot("gateways-after-edge-swipe")
        XCTAssertFalse(any("page.back").exists, "Gateways did not go back on an edge swipe")
        XCTAssertTrue(any("morph.title").waitForExistence(timeout: 5), "not back on Settings")
    }

    /// Settings › Status › Sign-in, the same form from another way in: it stays; Status still
    /// swipes back.
    func testStatusSignInIsNotSwipedAway() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "settings")
        XCTAssertTrue(any("settings.row.profile").waitForExistence(timeout: 20), "no Settings rows")
        pause(2)
        // Far down a lazy list: in the tree only once scrolled near.
        let status = any("settings.row.status")
        for _ in 0..<8 where !(status.exists && status.isHittable) { app.swipeUp(velocity: .slow); pause(0.6) }
        XCTAssertTrue(status.exists, "no Status row")
        status.tap(); pause(1.5); shot("status")
        XCTAssertTrue(any("page.back").waitForExistence(timeout: 5), "Status did not open")
        let signIn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sign-in'")).firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "no Sign-in row on Status")
        signIn.tap(); pause(1.5)
        XCTAssertTrue(formUp, "Sign-in's form did not open")
        edgeSwipe(); shot("sign-in-after-edge-swipe")
        XCTAssertTrue(formUp, "an edge swipe took Status › Sign-in's form away")
        cancelForm()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "Cancel did not return to Status")
        // Status itself still goes back by a swipe across.
        swipeAcross(); shot("status-after-swipe-across")
        XCTAssertFalse(any("page.back").exists, "Status did not go back on a swipe across")
    }

    /// A chat still goes back to the list by an edge swipe.
    func testAChatStillSwipesBack() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "chats")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 40), "no chat rows")
        pause(1.5)
        row.tap()
        XCTAssertTrue(any("chat.dock").waitForExistence(timeout: 20), "the chat did not open")
        pause(1.5)
        edgeSwipe(); shot("chat-after-edge-swipe")
        XCTAssertFalse(any("chat.dock").exists, "an edge swipe did not take the chat back to the list")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the list is not back")
    }

    /// Onboarding's gateway form: no swipe away either; its Cancel goes back.
    func testOnboardingFormIsNotSwipedAway() throws {
        guard let (_, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: nil, token: token, tab: "chats")
        let start = app.buttons["Get Started"].firstMatch
        if start.waitForExistence(timeout: 15) { start.tap(); pause(1) }
        if any("onboarding.skip").waitForExistence(timeout: 5) { any("onboarding.skip").tap(); pause(1) }
        let add = any("onboarding.addGateway")
        XCTAssertTrue(add.waitForExistence(timeout: 8), "no Add Gateway in onboarding")
        add.tap(); pause(1.5)
        XCTAssertTrue(formUp, "onboarding's gateway form did not open")
        edgeSwipe(); shot("onboarding-after-edge-swipe")
        XCTAssertTrue(formUp, "an edge swipe took onboarding's form away")
        cancelForm()
        XCTAssertTrue(any("onboarding.addGateway").waitForExistence(timeout: 5), "Cancel did not return to onboarding")
    }
}
