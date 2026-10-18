import XCTest

/// #409: VoiceOver read SF Symbols' own descriptions ("globe", "mostly cloudy") where an icon sits beside the words
/// that say what it is. Where they were read: the tour's connect page (each way to connect), a chat (a tool card's state
/// as "Checkmark Circle", a to-do list's steps, a system line's "Info"), and Settings pages' header tiles ("Mostly Cloudy"
/// for Bots, "Cpu Chip" for Model). On each, no element on screen is read as one of those descriptions, alone or at the
/// head of a row's words, and the states are read as words.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set (the mock). HERMES_E2E_BUNDLE=com.vorantx.vory.demo drives
/// the demo copy.
@MainActor
final class SymbolLabelsUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private func launch(url: String, token: String, extra: [String] = []) {
        let args = ["-companionPromptShown", "YES", "-launchTab", "chats", "-colorSchemePreference", "light",
                    "-tabLayout", "dashboard,chats,bots,settings", "-tabLayout.homeFirstApplied", "YES"] + extra
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop"] + args
        } else {
            app = XCUIApplication()
            app.launchArguments = args
        }
        app.launch()
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    /// How XCUITest (and VoiceOver) read the symbols that were read on these screens.
    static let spokenSymbols = ["Globe", "Mostly Cloudy", "Wi-Fi", "Wifi", "Three Connected Points With A Dotted Triangular Path",
                                "Cpu Chip", "Checkmark Circle", "Xmark Circle", "Arrow Right Circle", "Info", "Up Chevron",
                                "Down Chevron", "Gearshape 2", "Checkmark In A Shield", "Sparkle", "Checkmark Shield",
                                "Exclamationmark Triangle", "Warning"]

    private func isSymbolWord(_ label: String) -> Bool {
        let l = label.lowercased()
        return Self.spokenSymbols.contains { l == $0.lowercased() || l.hasPrefix($0.lowercased() + ", ") }
    }

    /// What VoiceOver stops on now, from the app's DEBUG oracle (`-vory-ax-oracle`, VoiceOverOracle): each stop's label
    /// and frame. XCUITest's own tree lists what VoiceOver skips (a hidden image, a combined row's parts), so the app is
    /// asked instead.
    private func stops() -> [(label: String, frame: String)] {
        let oracle = any("debug.voiceover")
        guard oracle.waitForExistence(timeout: 5) else { return [] }
        let text = (oracle.value as? String) ?? ""
        return text.split(separator: "\n").map { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts.first ?? ""), parts.count > 1 ? String(parts[1]) : "")
        }
    }

    /// The stops read as a symbol's description, alone or at the head of the stop's words.
    private func symbolsRead(_ screen: String) -> [String] {
        pause(1.2)
        let all = stops()
        let hits = all.filter { isSymbolWord($0.label) }.map { "'\($0.label.prefix(80))' at \($0.frame)" }
        print("SYMBOL-SWEEP \(screen): \(hits.count) of \(all.count) stops")
        for h in hits { print("SYMBOL-READ \(screen): \(h)") }
        return hits
    }

    func testTheToursConnectPageReadsItsWordsNotItsIcons() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        launch(url: url, token: token, extra: ["-vory-show-tour", "-vory-ax-oracle"])
        let skip = any("onboarding.skip")
        XCTAssertTrue(skip.waitForExistence(timeout: 30), "no tour")
        skip.tap(); pause(1.5)
        XCTAssertTrue(any("onboarding.addGateway").waitForExistence(timeout: 10), "not on the connect page")
        for words in ["Local network. Same Wi", "Tailscale. From anywhere", "Cloudflare Access. A public hostname", "Other. Any https address"] {
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", words)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "the row '\(words)…' is not read as its words")
        }
        let read = symbolsRead("Tour: connect")
        XCTAssertTrue(read.isEmpty, "the connect page reads symbols: \(read)")
    }

    func testAChatAndSettingsReadNoSymbolNames() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        launch(url: url, token: token, extra: ["-vory-ax-oracle"])
        XCTAssertTrue(any("chats.new").waitForExistence(timeout: 40))
        var read: [String] = []

        // A chat with tool cards (done) and a to-do list.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Disk cleanup")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap(); pause(2.5)
        // A turn of its own, for its tool cards and to-do list (the mock's stored history has none): an ordinary
        // message runs a terminal step and a to-do list, then asks for an approval, denied here.
        let composer = app.textViews["composer.text"].firstMatch
        if !composer.waitForExistence(timeout: 8), app.buttons["Deny"].waitForExistence(timeout: 10) { app.buttons["Deny"].tap(); pause(1.5) }
        if composer.waitForExistence(timeout: 15) {
            composer.tap(); composer.typeText("Check the disk again")
            app.buttons.matching(identifier: "composer.send").firstMatch.tap()
            if app.buttons["Deny"].waitForExistence(timeout: 60) { app.buttons["Deny"].tap(); pause(2) }
        }
        // Up to the turn's tool cards and to-do list (the chat opens at its latest message), found by what is spoken.
        func cardSpoken() -> Bool { stops().contains { $0.label.contains("terminal") || $0.label.lowercased().contains("todo") } }
        for _ in 0..<10 where !cardSpoken() { app.swipeDown(velocity: .slow); pause(0.8) }
        read += symbolsRead("Chat")
        let stated = stops().filter { $0.label.hasPrefix("Done, ") }
        for s in stated.prefix(4) { print("SYMBOL-STATE '\(s.label.prefix(120))'") }
        XCTAssertFalse(stated.isEmpty, "no tool card or step read with its state as 'Done'")
        if app.buttons["chat.back"].exists { app.buttons["chat.back"].tap(); pause(1) }

        // Settings: the pages whose header tile was read by its own description.
        any("tab.settings").tap(); pause(1.5)
        read += symbolsRead("Settings")
        for page in ["model", "bots"] {
            let r = any("settings.row.\(page)")
            // The list is lazy: a row further down is in the tree once it is scrolled to.
            for _ in 0..<6 where !(r.exists && r.isHittable) { app.swipeUp(velocity: .slow); pause(0.6) }
            guard r.waitForExistence(timeout: 5) else { XCTFail("no Settings row \(page)"); continue }
            r.tap(); pause(1.5)
            read += symbolsRead("Settings › \(page)")
            if app.buttons["page.back"].exists { app.buttons["page.back"].tap() } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
            }
            pause(1.2)
        }
        XCTAssertTrue(read.isEmpty, "VoiceOver reads \(read.count) symbol description(s): \(read.prefix(10).joined(separator: " | "))")
    }

    // MARK: The audit on the touched screens

    /// Runs the accessibility audit on this screen and returns what it flags inside `region` (the part this change
    /// touched); what it flags elsewhere is printed only, as other screens already have issues of their own.
    private func audit(_ screen: String, region: CGRect) -> [String] {
        var flagged: [String] = []
        do {
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .elementDetection]) { issue in
                guard let el = issue.element else { print("SYMBOL-AUDIT \(screen): '\(issue.compactDescription)' no element"); return true }
                let line = "'\(issue.compactDescription)' type \(el.elementType.rawValue) id '\(el.identifier)' label '\(el.label.prefix(60))' frame \(el.frame)"
                print("SYMBOL-AUDIT \(screen): \(line)")
                if region.intersects(el.frame) { flagged.append("\(screen): \(line)") }
                return true
            }
        } catch { flagged.append("\(screen): the audit failed: \(error)") }
        return flagged
    }

    func testTheTouchedScreensPassTheAudit() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        var flagged: [String] = []

        // The tour's connect page: its four rows.
        launch(url: url, token: token, extra: ["-vory-show-tour"])
        XCTAssertTrue(any("onboarding.skip").waitForExistence(timeout: 30))
        any("onboarding.skip").tap(); pause(1.5)
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Local network.' OR label BEGINSWITH 'Other.'"))
        let first = rows.element(boundBy: 0).frame, last = rows.element(boundBy: rows.count - 1).frame
        flagged += audit("Tour: connect", region: first.union(last))
        app.terminate()

        // Settings › Model and › Bots: their header tiles.
        launch(url: url, token: token)
        XCTAssertTrue(any("chats.new").waitForExistence(timeout: 40))
        any("tab.settings").tap(); pause(1.5)
        for page in ["model", "bots"] {
            let r = any("settings.row.\(page)")
            for _ in 0..<6 where !(r.exists && r.isHittable) { app.swipeUp(velocity: .slow); pause(0.6) }
            guard r.waitForExistence(timeout: 5) else { XCTFail("no Settings row \(page)"); continue }
            r.tap(); pause(1.5)
            // The header card: the tile, the title and its line, at the top of the page.
            flagged += audit("Settings › \(page)", region: CGRect(x: 0, y: 100, width: app.frame.width, height: 220))
            if app.buttons["page.back"].exists { app.buttons["page.back"].tap() } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
            }
            pause(1.2)
        }
        XCTAssertTrue(flagged.isEmpty, "the audit flags the touched parts: \(flagged)")
    }
}
