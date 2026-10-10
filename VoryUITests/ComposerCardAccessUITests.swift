import XCTest

/// The card composer (#320) at a large Dynamic Type size and in VoiceOver's order: the card
/// still fits with its control row reachable, and a swipe through it goes text, +, model chip,
/// mic or send. Pictures for the planner; the order asserted from the accessibility tree.
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set.
@MainActor
final class ComposerCardAccessUITests: XCTestCase {
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

    private func launch(url: String, token: String, size: String?) {
        var args = ["-colorSchemePreference", "light", "-launchTab", "chats"]
        if let size { args += ["-UIPreferredContentSizeCategoryName", size] }
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES"] + args
        } else {
            app = XCUIApplication()
            app.launchArguments = args
        }
        app.launch()
    }

    private func settle(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func openNewChat() {
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()
        XCTAssertTrue(app.textViews["composer.text"].firstMatch.waitForExistence(timeout: 30))
        settle(1.5)
    }

    /// The composer's pieces in accessibility order, by identifier or label.
    private func cardOrder() -> [String] {
        guard let snap = try? app.snapshot() else { return [] }
        var out: [String] = []
        func walk(_ s: XCUIElementSnapshot) {
            let id = s.identifier
            if ["composer.text", "composer.attach", "composer.modelChip", "composer.send"].contains(id) { out.append(id) }
            else if s.elementType == .button, ["Dictate", "Stop", "Send"].contains(where: { s.label.hasPrefix($0) }) { out.append(s.label) }
            for c in s.children { walk(c) }
        }
        walk(snap)
        return out
    }

    func testTheCardReadsInOrderAndFitsAtLargeType() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        launch(url: url, token: token, size: nil)
        openNewChat()
        let order = cardOrder()
        print("CARD-ORDER \(order)")
        let text = order.firstIndex(of: "composer.text") ?? -1
        let attach = order.firstIndex(of: "composer.attach") ?? -1
        let chip = order.firstIndex(of: "composer.modelChip") ?? -1
        XCTAssertTrue(text >= 0 && attach > text && chip > attach, "VoiceOver order is not text, +, chip: \(order)")
        app.terminate()

        // Accessibility large: the card and its row still on screen, the composer reachable.
        launch(url: url, token: token, size: "UICTContentSizeCategoryAccessibilityL")
        openNewChat()
        shot("card-access-1-large-empty")
        let composer = app.textViews["composer.text"].firstMatch
        let chipButton = app.buttons["composer.modelChip"].firstMatch
        XCTAssertTrue(composer.isHittable, "the composer is not reachable at the large size")
        XCTAssertTrue(chipButton.exists && app.windows.firstMatch.frame.contains(chipButton.frame), "the chip is off the window at the large size")
        composer.tap()
        composer.typeText("Large type, a few words that wrap in the card.")
        settle(2.5)
        shot("card-access-2-large-typed")
        XCTAssertTrue(app.buttons["composer.attach"].firstMatch.isHittable, "+ is not reachable at the large size with the keyboard up")
    }
}
