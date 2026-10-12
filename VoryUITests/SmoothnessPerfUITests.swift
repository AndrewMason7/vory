import XCTest

/// Hitches in the moments that have to be smooth (1.5, Matt: "absolutely smooth"): the push
/// into a chat and the pop back, the + panel, the bot card, the model chip, the list's View
/// menu, a settings sheet, a long thread's scroll and a whole turn. Each flow is measured with
/// XCTest's os_signpost hitch metrics (hitch time per second, the hitch count and the frame
/// rate) over the app's `Smooth` animation intervals, or the system's navigation and scroll
/// intervals. The numbers are the table for the planner; the simulator's are a rough guide,
/// the device's are the bar. Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set.
final class SmoothnessPerfUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private func launch(url: String, token: String, tab: String = "chats", extra: [String] = []) {
        // HERMES_E2E_ARGS: extra launch arguments, space-separated (the measurement switches).
        let args = ["-companionPromptShown", "YES", "-launchTab", tab, "-colorSchemePreference", "light", "-chat.showBots", "YES", "-chats.allBots", "YES"] + extra
            + (ProcessInfo.processInfo.environment["HERMES_E2E_ARGS"] ?? "").split(separator: " ").map(String.init)
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop"] + args
        } else {
            app = XCUIApplication()
            app.launchArguments = args
        }
        app.launch()
    }

    private func smooth(_ name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: "Vory", category: "Smooth", name: name)
    }

    /// Ten rounds for the quick flows (a single hitch in five rounds is noise; the planner wants
    /// a mean and a worst that mean something), five for the long ones (a fling is 2.4 s each).
    private func rounds(_ n: Int) -> XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = n
        o.invocationOptions = [.manuallyStop]
        return o
    }
    private var options: XCTMeasureOptions { rounds(10) }
    private var longOptions: XCTMeasureOptions { rounds(5) }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    /// A system permission alert left over the app (the phone put up "add to your photo library"
    /// once between runs and every tap went to it): answered, so the flow goes on.
    private func clearSystemAlert() {
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "OK", "Don’t Allow"] {
            let b = board.buttons[name]
            if b.waitForExistence(timeout: 1) { b.tap(); pause(0.5); return }
        }
    }

    private func openFirstChat() {
        clearSystemAlert()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 40), "no chat row")
        row.tap()
        XCTAssertTrue(any("chat.dock").waitForExistence(timeout: 20), "the chat did not open")
    }

    private func back() {
        // The header's own Back circle, or the system back button when the chat shows the
        // real navigation bar (the morph prototype, `-vory-morph-header`).
        var b = any("chat.back")
        if !b.waitForExistence(timeout: 3) { b = app.navigationBars.buttons.firstMatch }
        XCTAssertTrue(b.waitForExistence(timeout: 10), "no Back")
        // A touch at its centre, not the element tap: on the device the element tap activates
        // through accessibility and a glass-hosted button did not answer it.
        b.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch.waitForExistence(timeout: 10), "the list did not come back")
    }

    /// list → chat → back: the system's navigation transition intervals.
    func testListToChatAndBack() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch.waitForExistence(timeout: 40))
        pause(2)
        measure(metrics: [XCTOSSignpostMetric.navigationTransitionMetric], options: options) {
            openFirstChat(); pause(1)
            back(); pause(1)
            stopMeasuring()
        }
    }

    /// Diagnostic, not a measurement: one back swipe and one button Back, for the order of
    /// the app's "pop:" notes in the log (when the path empties against the transition's end).
    func testSwipeBackOrder() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch.waitForExistence(timeout: 10), "the swipe did not go back")
        pause(1.5)
        openFirstChat(); pause(1.5)
        back(); pause(1.5)
    }

    /// A chat this device has never opened (no transcript or settings cache), pushed and popped:
    /// for a frame check of what the page shows before its history lands.
    func testColdOpen() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        // A fresh install on the phone asks about the local network first; the list waits on it.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 8) { allow.tap() }
        waitForList()
        pause(2.5)
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Weekly dependency audit'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20), "no audit chat")
        let row = try XCTUnwrap(rows.allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY }, "no audit chat on screen")
        row.tap()
        XCTAssertTrue(any("chat.dock").waitForExistence(timeout: 20), "the chat did not open")
        pause(3)
        back(); pause(1.5)
    }

    /// A fast back swipe out of a chat, for a frame check of the bar and the list's top coming
    /// back (Matt, 2026-10-12: "swiping back fast the nav bar pops up kinda choppy").
    func testFastSwipeBack() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(2)
        for _ in 0..<3 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)), withVelocity: .fast, thenHoldForDuration: 0)
            // The list's first row on screen, not the hidden copy the Chats tab leaves in the
            // accessibility tree (#326): a cancelled flick passed this check before.
            let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'"))
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the swipe did not go back")
            XCTAssertTrue(rows.allElementsBoundByIndex.contains { $0.isHittable }, "the list is not on screen")
            pause(1.5)
            openFirstChat(); pause(2)
        }
        back(); pause(1.5)
    }

    /// Pull to refresh with the search drawer hidden, then reveal the drawer and pull again,
    /// for a frame check that the refresh spinner does not draw inside the search field (the
    /// 2026-10-10 bug the old pinned field caused; Matt, 2026-10-12 moved to the native drawer).
    func testSearchDrawerAndRefresh() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList()
        // Drawer hidden: a slow pull from the top refreshes (and flashes the drawer on the way).
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 0.1)
        pause(2.5)
        // Reveal the drawer and leave it shown: a short pull.
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 0.2)
        pause(1.5)
        // Drawer shown: pull to refresh again.
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 0.1)
        pause(2.5)
    }

    /// Every root page's heading and its pull-to-refresh (Home, Files, Settings, then Chats): a
    /// screenshot at rest and one mid-refresh each, for a look at the wheel beside the title.
    func testPageHeadings() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList()
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        let slots = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tab.'")).allElementsBoundByIndex
        let tabs = slots.map { String($0.identifier.dropFirst(4)) }.filter { $0 != "chats" } + ["chats"]
        for tab in tabs {
            let slot = app.descendants(matching: .any).matching(identifier: "tab.\(tab)").firstMatch
            if slot.waitForExistence(timeout: 5) { slot.tap(); pause(1.5) }
            shot("\(tab)-rest")
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 0.1)
            // The wheel's spinner is the one accessible part of the pull ("Refreshing"): its
            // presence after the release is the page's verdict, not a screenshot's timing.
            let spinning = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Refreshing'")).firstMatch.waitForExistence(timeout: 1.5)
            print("PULL-WHEEL \(tab) \(spinning ? "spinning" : "none")")
            shot("\(tab)-refreshing")
            pause(1.5)
        }
    }

    /// Hidden tab pages stay out of the accessibility tree (#326): on Chats, each chat row is
    /// found once (Home lists the recent chats too), and none of Home's activity blocks show.
    func testHiddenPagesOutOfTheTree() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "dashboard")
        pause(3)
        let home = app.descendants(matching: .any).matching(identifier: "tab.chats").firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10)); home.tap(); pause(2)
        waitForList()
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).count
        let blocks = app.otherElements.matching(NSPredicate(format: "label CONTAINS ' sessions'")).count
        print("AX-TREE chats rows=\(rows) home-blocks=\(blocks)")
        XCTAssertEqual(rows, 1, "the chat row is in the tree \(rows) times")
        XCTAssertEqual(blocks, 0, "Home's activity blocks are in the Chats tree")
    }

    /// The pull-to-refresh wheel on every root that can refresh (Matt, 2026-10-12: "the pull to
    /// refresh wheel doesn't appear on some of the pages"): the bar is relaunched with each group
    /// of four tabs, every page pulled, and the wheel's "Refreshing" looked for after the release.
    func testPullWheelEveryRoot() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        // Four slots on the bar, Chats and Settings always among them: two pages per launch.
        let groups = [["dashboard", "bots"], ["files", "projects"], ["kanban", "sessions"], ["cron", "status"], ["approvals", "system", "settings"]]
        let canRefresh: Set<String> = ["chats", "dashboard", "bots", "files", "projects", "kanban", "sessions", "cron", "status"]
        var missing: [String] = []
        for group in groups {
            // The once-per-phone Home-first write would replace the layout: mark it done.
            launch(url: url, token: token, extra: ["-tabLayout", (["chats"] + group).joined(separator: ","), "-tabLayout.homeFirstApplied", "YES"])
            waitForList()
            for tab in group + ["chats"] {
                let slot = app.descendants(matching: .any).matching(identifier: "tab.\(tab)").firstMatch
                // A page the gateway cannot show (the Board without its plugin) has no slot.
                guard slot.waitForExistence(timeout: 5) else { print("PULL-WHEEL \(tab) no-slot"); continue }
                slot.tap(); pause(1.5)
                let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 0.1)
                let wheel = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Refreshing'")).firstMatch
                let spinning = wheel.waitForExistence(timeout: 1.5)
                print("PULL-WHEEL \(tab) \(spinning ? "spinning at \(wheel.frame.origin)" : "none")")
                shot("\(tab)-refreshing")
                if canRefresh.contains(tab), !spinning { missing.append(tab) }
                pause(1.5)
            }
            app.terminate()
        }
        XCTAssertTrue(missing.isEmpty, "no pull wheel on: \(missing.joined(separator: ", "))")
    }

    /// Every way back out of a chat, for a clip and a hitch trace: a slow swipe let go past the
    /// middle, a fast flick, a swipe let go early (cancelled), and the Back button.
    func testSwipeBackKinds() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        func edge(_ y: CGFloat = 0.5) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: y)) }
        func at(_ x: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)) }
        func listBack() {
            let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'"))
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10) && rows.allElementsBoundByIndex.contains { $0.isHittable }, "the list is not back")
            pause(1.5)
        }
        openFirstChat(); pause(2)
        // 1. A slow swipe, let go past the middle.
        edge().press(forDuration: 0.1, thenDragTo: at(0.7), withVelocity: .slow, thenHoldForDuration: 0.3)
        listBack()
        openFirstChat(); pause(2)
        // 2. A fast flick (to 0.9: at 0.8 the device sometimes decided a cancel).
        edge().press(forDuration: 0.05, thenDragTo: at(0.9), withVelocity: .fast, thenHoldForDuration: 0)
        listBack()
        openFirstChat(); pause(2)
        // 3. A swipe let go early: cancelled, the chat stays.
        edge().press(forDuration: 0.1, thenDragTo: at(0.22), withVelocity: .slow, thenHoldForDuration: 0.3)
        pause(1.5)
        XCTAssertTrue(any("chat.dock").exists, "the cancelled swipe left the chat")
        // 4. The Back button.
        back(); pause(1.5)
    }


    /// Diagnostic for the morph prototype's Back on the device: where the Back element is, whether
    /// it is hittable, and what is on screen after the tap.
    func testMorphBackDiag() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(2)
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        let backs = app.descendants(matching: .any).matching(identifier: "chat.back").allElementsBoundByIndex
        var lines = ["chat.back count=\(backs.count)"]
        for (i, b) in backs.enumerated() { lines.append("[\(i)] frame=\(b.frame) hittable=\(b.isHittable) type=\(b.elementType.rawValue) label=\(b.label)") }
        lines.append("navBars=\(app.navigationBars.count)")
        let t = XCTAttachment(string: lines.joined(separator: "\n")); t.name = "back-diag"; t.lifetime = .keepAlways; add(t)
        shot("before-tap")
        if let b = backs.first { b.tap() }
        pause(1.5)
        shot("after-tap")
        let dockStill = any("chat.dock").exists
        let t2 = XCTAttachment(string: "dock still there after tap: \(dockStill)"); t2.name = "back-diag-2"; t2.lifetime = .keepAlways; add(t2)
        if dockStill, let b = backs.first { b.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); pause(1.5); shot("after-coord-tap") }
    }

    /// Diagnostic: a cancelled swipe, then Back (the morph prototype's Back died after a cancel).
    func testMorphCancelThenBack() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(2)
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        func note(_ name: String, _ s: String) { let a = XCTAttachment(string: s); a.name = name; a.lifetime = .keepAlways; add(a) }
        func backState() -> String {
            let b = any("chat.back")
            return "exists=\(b.exists) hittable=\(b.exists ? b.isHittable : false) frame=\(b.exists ? b.frame : .zero) dock=\(any("chat.dock").exists)"
        }
        note("before-cancel", backState())
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.3)
        pause(1.5)
        note("after-cancel", backState())
        shot("after-cancel")
        any("chat.back").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        pause(1.5)
        note("after-back", backState())
        shot("after-back")
        // If the element's centre missed, a touch on the circle itself (its place at rest).
        if any("chat.dock").exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 38.0 / 402.0, dy: 89.0 / 874.0)).tap()
            pause(1.5)
            note("after-circle-tap", backState())
            shot("after-circle-tap")
        }
    }

    /// The morph prototype's controls, each activated through accessibility (the element tap,
    /// which is VoiceOver's path), not by a touch at its coordinates: a glass-hosted control
    /// on the device answered a touch but not that path until it was given an explicit action.
    func testMorphControlsActivate() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList(); clearSystemAlert()
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        func dismissMenu() { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap(); pause(0.8) }
        func menu(_ id: String, shows item: String) {
            let c = any(id)
            XCTAssertTrue(c.waitForExistence(timeout: 5), "\(id) is not there")
            c.tap(); pause(1)
            let found = app.buttons[item].waitForExistence(timeout: 3) || app.staticTexts[item].exists || app.switches[item].exists
            if !found { shot("\(id)-after-tap") }
            XCTAssertTrue(found, "\(id): '\(item)' did not appear after an accessibility tap")
            dismissMenu()
        }
        // The list's controls.
        menu("chats.profile", shows: "All bots")
        menu("chats.sort", shows: "Recent")
        menu("chats.filters", shows: "Pinned only")
        let newBot = any("chats.newBot")
        XCTAssertTrue(newBot.waitForExistence(timeout: 5), "no + button")
        newBot.tap(); pause(1.2)
        shot("after-new-bot")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3), "the New Bot sheet did not open from an accessibility tap")
        cancel.tap(); pause(1)
        // The chat's controls.
        openFirstChat(); pause(2)
        menu("chat.more", shows: "Rename chat")
        let pill = any("chat.titlePill")
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "no title pill")
        pill.tap(); pause(1.5)
        shot("after-pill")
        // The bot's card: a sheet over the chat with a Done or a close control.
        let closed = app.buttons["Done"].waitForExistence(timeout: 3) || app.buttons["Close"].exists
        XCTAssertTrue(closed, "the bot card did not open from an accessibility tap on the pill")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() } else { app.buttons["Close"].tap() }
        pause(1)
        back(); pause(1.5)
        // The other roots' controls, where the tab is in the bar.
        func onTab(_ tab: String, _ body: () -> Void) {
            let slot = app.descendants(matching: .any).matching(identifier: "tab.\(tab)").firstMatch
            guard slot.waitForExistence(timeout: 3) else { return }
            slot.tap(); pause(1.5); body()
        }
        onTab("bots") {
            let b = any("bots.newBot"); XCTAssertTrue(b.waitForExistence(timeout: 5), "no Bots +")
            b.tap(); pause(1.2)
            if !app.buttons["Cancel"].waitForExistence(timeout: 3) {
                shot("bots-after-plus")
                let t = XCTAttachment(string: "bots.newBot frame=\(b.frame) hittable=\(b.isHittable) sheets=\(app.sheets.count) buttons=\(app.buttons.allElementsBoundByIndex.prefix(12).map { $0.label })"); t.name = "bots-plus-diag"; t.lifetime = .keepAlways; add(t)
                // A touch at the same spot: tells the accessibility path from the plumbing.
                b.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); pause(1.2)
                let t2 = XCTAttachment(string: "after coordinate tap: cancel=\(app.buttons["Cancel"].exists)"); t2.name = "bots-plus-diag-2"; t2.lifetime = .keepAlways; add(t2)
                if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap(); pause(1) }
                XCTFail("the New Bot sheet did not open from the bar's +")
            }
            app.buttons["Cancel"].tap(); pause(1)
        }
        onTab("projects") {
            let b = any("projects.new"); XCTAssertTrue(b.waitForExistence(timeout: 5), "no Projects +")
            b.tap(); pause(1.2)
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3), "the New Project sheet did not open from the bar's +")
            app.buttons["Cancel"].tap(); pause(1)
        }
        onTab("files") {
            let h = any("files.hidden"); XCTAssertTrue(h.waitForExistence(timeout: 5), "no Files hidden switch")
            let before = h.label; h.tap(); pause(1)
            XCTAssertNotEqual(any("files.hidden").label, before, "the hidden-files switch did not flip from the bar")
        }
        onTab("chats") {}
    }

    /// Tab switches by a tap, Chats → Bots → Files → Settings → Chats, for a frame check of the
    /// morph prototype's bar morphing one page's set into the next.
    func testTabTapSwitch() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList(); clearSystemAlert()
        for tab in ["bots", "files", "settings", "chats", "bots", "chats"] {
            let slot = app.descendants(matching: .any).matching(identifier: "tab.\(tab)").firstMatch
            if slot.waitForExistence(timeout: 5) { slot.tap() }
            pause(1.6)
        }
    }

    /// Diagnostic at the accessibility sizes: can a finger reach the list's first row with the
    /// search drawer tucked and shown? Frames of the row and the field, hittability, a shot
    /// each, then a touch at the row's centre.
    func testAXRowReach() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList(); clearSystemAlert(); pause(1)
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        func note(_ name: String, _ text: String) { let a = XCTAttachment(string: text); a.name = name; a.lifetime = .keepAlways; add(a) }
        func state() -> String {
            let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).allElementsBoundByIndex
            let row = rows.min { $0.frame.minY < $1.frame.minY }
            let field = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
            return "row=\(row.map { "\($0.frame) hittable=\($0.isHittable)" } ?? "none") field=\(field.exists ? "\(field.frame)" : "none") window=\(app.frame)"
        }
        note("tucked", state()); shot("tucked")
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 0.2)
        pause(1.5)
        note("shown", state()); shot("shown")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).allElementsBoundByIndex
        if let row = rows.min(by: { $0.frame.minY < $1.frame.minY }) {
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); pause(1.5)
            note("after-row-touch", "dock=\(any("chat.dock").exists)"); shot("after-row-touch")
        }
    }

    /// Diagnostic for a window changing width with a chat open (the Duo rotating): a draft typed,
    /// then upright → landscape → upright, with the Back elements counted, the draft read back
    /// and a screenshot per pose.
    func testRotateWithChatOpen() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(2)
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        func note(_ name: String, _ text: String) { let a = XCTAttachment(string: text); a.name = name; a.lifetime = .keepAlways; add(a) }
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no composer")
        field.tap(); pause(0.8); field.typeText("draft kept?"); pause(0.5)
        func state(_ pose: String) {
            let backs = app.descendants(matching: .any).matching(identifier: "chat.back").count
            let draft = (app.textViews.firstMatch.value as? String) ?? ""
            note(pose, "window=\(app.frame) backs=\(backs) dock=\(any("chat.dock").exists) draft='\(draft)'")
            shot(pose)
        }
        state("upright")
        XCUIDevice.shared.orientation = .landscapeLeft; pause(2.5); state("landscape")
        XCUIDevice.shared.orientation = .portrait; pause(2.5); state("upright-again")
    }

    /// A page pushed on another tab (Settings → a row) with the morph bar on: the bar steps aside
    /// and the pushed page keeps the system's title and Back; then Back to the root.
    func testMorphPushedPage() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "settings")
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        pause(2); shot("settings-root")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'settings.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no settings row")
        row.tap(); pause(1.5); shot("settings-pushed")
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the pushed page has no Back")
        back.tap(); pause(1.5); shot("settings-root-again")
    }

    /// The "/" list out of the field and back (type "/", then delete it).
    func testSlashMenu() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(1.5)
        let field = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no composer field")
        field.tap(); pause(1.5)
        measure(metrics: [smooth("slashMenu")], options: options) {
            field.typeText("/"); pause(1.2)
            field.typeText(XCUIKeyboardKey.delete.rawValue); pause(1.2)
            stopMeasuring()
        }
        // The + panel with the keyboard up (it stays up), once, for the recording.
        let plus = app.buttons["composer.attach"].firstMatch
        if plus.waitForExistence(timeout: 5) { plus.tap(); pause(1.5); plus.tap(); pause(1.5) }
    }

    /// Settings › Appearance flung down to the bot rows and back (Matt, 2026-10-11: "lags so
    /// hard" as the bots come in).
    func testAppearanceScroll() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "settings")
        // The row is further down the Settings root; rows off screen are not in the tree yet.
        XCTAssertTrue(any("settings.row.gateways").waitForExistence(timeout: 40), "no settings")
        var row = any("settings.row.appearance")
        for _ in 0..<5 where !row.exists { app.swipeUp(velocity: .slow); pause(0.6); row = any("settings.row.appearance") }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Appearance row")
        row.tap(); pause(2)
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: longOptions) {
            for _ in 0..<4 { app.swipeUp(velocity: .fast); pause(0.9) }
            for _ in 0..<4 { app.swipeDown(velocity: .fast); pause(0.9) }
            stopMeasuring()
        }
    }

    /// A "Background process finished" note opened and closed (the mock's nightly-export chat).
    func testInjectedNote() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList()
        // The list re-sorts as the sessions load; a row tapped before it settles is tapped where
        // it was (its reported frame lags). Let it settle, then find the row afresh.
        pause(2.5)
        // Two buttons carry this title (a hidden page's row is in the tree too, lower down);
        // the one on screen is the list's.
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rewrite the nightly export job'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20), "no nightly export chat")
        let row = rows.allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY }!
        row.tap()
        XCTAssertTrue(any("chat.dock").waitForExistence(timeout: 20), "the chat did not open")
        pause(1.5)
        // The note sits above the end of the thread; scroll up until it is on screen.
        var note = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Background process'")).firstMatch
        for _ in 0..<6 where !note.exists { app.swipeDown(velocity: .slow); pause(0.8); note = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Background process'")).firstMatch }
        XCTAssertTrue(note.waitForExistence(timeout: 5), "no background process note")
        pause(1)
        // The swipes leave the pill up under the bar, where a tap lands on the bar and the open
        // note's title ends up off screen: drag the thread down until the pill sits mid-screen.
        func findNote() -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Background process'")).firstMatch }
        func settle() {
            for _ in 0..<4 where note.frame.minY < 160 {
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 250)), withVelocity: .slow, thenHoldForDuration: 0.2)
                pause(0.8); note = findNote()
            }
        }
        settle()
        XCTAssertGreaterThan(note.frame.minY, 100, "the note stayed under the bar")
        // When and where each tap landed, for a frame check of a screen recording.
        func mark(_ what: String) { try? "\(Date().timeIntervalSince1970) \(what) \(note.frame)\n".appendLine(to: "/tmp/vory-note-taps.txt") }
        measure(metrics: [smooth("touch")], options: options) {
            settle()
            // The open note's element is the whole row: tap its title, 15 pt under the top edge.
            func tapTitle() { note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 15)).tap() }
            mark("open"); tapTitle(); pause(1.2)
            note = findNote()
            mark("close"); tapTitle(); pause(1.2)
            stopMeasuring()
        }
    }

    /// The + panel out of the + button and back.
    func testPlusPanel() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(1.5)
        let plus = app.buttons["composer.attach"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        measure(metrics: [smooth("plusPanel")], options: options) {
            plus.tap(); pause(1.2)
            plus.tap(); pause(1.2)
            stopMeasuring()
        }
    }

    /// The bot card (a sheet at full height) and its close.
    func testBotCard() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(1.5)
        // The phone's header pill (the bot sits on it); "chat.bot" is the Mac toolbar's.
        let bot = app.buttons["chat.titlePill"].firstMatch
        XCTAssertTrue(bot.waitForExistence(timeout: 10), "no title pill")
        measure(metrics: [smooth("botCard")], options: options) {
            bot.tap()
            let close = any("profile.close")
            XCTAssertTrue(close.waitForExistence(timeout: 10), "the card did not open")
            pause(1)
            close.tap(); pause(1.2)
            stopMeasuring()
        }
    }

    /// The model chip's menu.
    func testModelChip() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(1.5)
        let chip = any("composer.modelChip")
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        // A Menu swallows the tap before any gesture of ours sees it, so the interval comes
        // from the window's touch-down signpost ("touch"), which every control gets.
        measure(metrics: [smooth("touch")], options: options) {
            chip.tap(); pause(1.2)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap(); pause(1)
            stopMeasuring()
        }
    }

    /// The list's View menu (filters on a phone, the merged menu in a strip or a column).
    func testViewMenu() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch.waitForExistence(timeout: 40))
        pause(1.5)
        // The merged View menu in a strip or a column; the Filters menu on a phone. On a device
        // the toolbar menu answers to its label rather than the identifier, so both are tried.
        let candidates = [any("chats.view"), any("chats.filters"), app.buttons["Filters"].firstMatch, app.buttons["Filters (on)"].firstMatch, app.buttons["View"].firstMatch]
        _ = candidates[0].waitForExistence(timeout: 5)
        guard let view = candidates.first(where: { $0.exists }) else { return XCTFail("no View menu") }
        measure(metrics: [smooth("touch")], options: options) {
            view.tap(); pause(1.2)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap(); pause(1)
            stopMeasuring()
        }
    }

    /// Settings › Gateway › Add Gateway, a form sheet, opened and dismissed.
    func testSettingsSheet() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "settings")
        // Add Gateway lives on the Gateways page, behind the gateway's row on the Settings root.
        let gateway = any("settings.row.gateways")
        XCTAssertTrue(gateway.waitForExistence(timeout: 40), "no gateway row")
        gateway.tap()
        let add = app.buttons["settings.addGateway"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20), "no Add Gateway")
        pause(1.5)
        measure(metrics: [smooth("gatewaySheet")], options: options) {
            add.tap(); pause(1.2)
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.waitForExistence(timeout: 3) { cancel.tap() } else { app.swipeDown(velocity: .fast) }
            pause(1.2)
            stopMeasuring()
        }
    }

    /// A long thread flung up and down: the system's scroll deceleration intervals.
    func testThreadScroll() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(1)
        // One long turn first, so there is something to scroll.
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("marathon 30")
        app.buttons["composer.send"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Everything else looked healthy'")).firstMatch.waitForExistence(timeout: 90), "the turn did not finish")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        pause(1.5)
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: longOptions) {
            for _ in 0..<3 { app.swipeDown(velocity: .fast); pause(0.9) }
            for _ in 0..<3 { app.swipeUp(velocity: .fast); pause(0.9) }
            stopMeasuring()
        }
    }

    /// The keyboard up and down in a chat (Matt: "bringing up the keyboard and bringing it down
    /// is very laggy and choppy"): the dock and the thread ride with it.
    func testKeyboard() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(1.5)
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        measure(metrics: [smooth("touch")], options: options) {
            field.tap(); pause(1.5)
            // Down: a tap on the thread dismisses the keyboard.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap(); pause(1.5)
            stopMeasuring()
        }
    }

    /// The keyboard dragged down over the thread (interactive dismiss), the drag slow enough for
    /// the keyboard to track the finger (handoff item 2: 60 to 79 ms frames inside the tracking).
    func testKeyboardDrag() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(1.5)
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        measure(metrics: [smooth("touch")], options: options) {
            field.tap(); pause(1.5)
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
            pause(1.5)
            stopMeasuring()
        }
    }

    /// The tab bar's lens held on Chats and dragged slowly across to Settings and back (Matt:
    /// "holding the nav bar selector and then dragging it across to change views is a bit laggy").
    func testTabLensDrag() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList()
        let chats = app.descendants(matching: .any).matching(identifier: "tab.chats").firstMatch
        let settings = app.descendants(matching: .any).matching(identifier: "tab.settings").firstMatch
        XCTAssertTrue(chats.waitForExistence(timeout: 10) && settings.exists, "no tab bar slots")
        let from = chats.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        measure(metrics: [smooth("touch")], options: options) {
            from.press(forDuration: 0.5, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            pause(1.2)
            to.press(forDuration: 0.5, thenDragTo: from, withVelocity: .slow, thenHoldForDuration: 0.3)
            pause(1.2)
            stopMeasuring()
        }
    }

    // MARK: The heavy list (Matt: with lots of chats and bots "that is where it gets sluggish").
    // These want the mock with --extra-sessions 60 --extra-bots 12 (14 bots, 112 chats).

    private func waitForList() {
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch.waitForExistence(timeout: 40), "no chat rows")
        pause(2)
    }

    /// The long chat list flung down and back up: the system's scroll deceleration intervals.
    func testChatListScroll() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList()
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: longOptions) {
            for _ in 0..<4 { app.swipeUp(velocity: .fast); pause(0.9) }
            for _ in 0..<4 { app.swipeDown(velocity: .fast); pause(0.9) }
            stopMeasuring()
        }
    }

    /// A chat deep in the list opened and closed: the push and the pop with a long list behind.
    func testDeepRowAndBack() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList()
        for _ in 0..<3 { app.swipeUp(velocity: .fast); pause(0.8) }
        pause(1)
        measure(metrics: [XCTOSSignpostMetric.navigationTransitionMetric], options: options) {
            // Whatever row sits in the middle of the screen after the flings.
            let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'workshop' OR label CONTAINS[c] 'ago' OR label CONTAINS[c] 'yesterday'"))
            // The row nearest the middle of the screen, judged by its frame: asking an
            // off-screen row whether it is hittable throws on a device.
            let window = app.windows.firstMatch.frame
            let mid = window.midY
            let row = rows.allElementsBoundByIndex
                .filter { $0.frame.minY > window.minY + 120 && $0.frame.maxY < window.maxY - 160 }
                .min { abs($0.frame.midY - mid) < abs($1.frame.midY - mid) }
            XCTAssertNotNil(row, "no row in the middle of the screen")
            guard let row else { stopMeasuring(); return }
            print("DEEP-ROW \(row.label.prefix(60)) \(row.frame)")
            // By coordinate: the row's own tap landed beside it on a device once.
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: row.frame.midX, dy: row.frame.midY)).tap()
            XCTAssertTrue(any("chat.dock").waitForExistence(timeout: 20), "the chat did not open: \(row.label.prefix(60))")
            pause(1)
            let b = any("chat.back")
            XCTAssertTrue(b.waitForExistence(timeout: 10)); b.tap()
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
            pause(1)
            stopMeasuring()
        }
    }

    /// The All bots switch in the list's bot menu, off to on and back: the list rebuilds with
    /// every bot's chats and their faces.
    func testAllBotsSwitch() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        let args = ["-companionPromptShown", "YES", "-launchTab", "chats", "-colorSchemePreference", "light", "-chat.showBots", "YES", "-chats.allBots", "NO"]
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle); app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop"] + args
        } else { app = XCUIApplication(); app.launchArguments = args }
        app.launch()
        waitForList()
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Profile:'")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no bot menu")
        measure(metrics: [smooth("touch")], options: options) {
            for _ in 0..<2 {
                menu.tap()
                let all = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'All bots'")).firstMatch
                XCTAssertTrue(all.waitForExistence(timeout: 8), "no All bots switch")
                all.tap(); pause(2.5)
            }
            stopMeasuring()
        }
    }

    /// The Bots page with fourteen bots: the tab switch, then a fling of its grid.
    func testBotsPage() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        waitForList()
        let bots = any("tab.bots"), chats = any("tab.chats")
        XCTAssertTrue(bots.waitForExistence(timeout: 10), "no Bots tab")
        measure(metrics: [smooth("touch"), XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            bots.tap(); pause(1.5)
            app.swipeUp(velocity: .fast); pause(1)
            app.swipeDown(velocity: .fast); pause(1)
            chats.tap(); pause(1.2)
            stopMeasuring()
        }
    }

    /// A whole default turn with the bot animating (orb, bubbles, toolbox, the approval, rest).
    func testFullTurn() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openFirstChat(); pause(1)
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let o = XCTMeasureOptions(); o.iterationCount = 1; o.invocationOptions = [.manuallyStop]
        measure(metrics: [smooth("turn")], options: o) {
            field.tap(); field.typeText("think it through")
            let send = app.buttons["composer.send"].firstMatch
            send.tap()
            // While the turn runs the send button is the stop button; with the field empty
            // again it gives way to the mic, so the turn is over when it is gone.
            pause(3)
            let gone = NSPredicate(format: "exists == false")
            _ = XCTWaiter.wait(for: [expectation(for: gone, evaluatedWith: send)], timeout: 120)
            pause(2)
            stopMeasuring()
        }
    }
}

private extension String {
    /// Appends the line to a file (made if missing); the frame checks read it.
    func appendLine(to path: String) throws {
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(utf8)); h.closeFile() }
        else { try write(toFile: path, atomically: true, encoding: .utf8) }
    }
}
