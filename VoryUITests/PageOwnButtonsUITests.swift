import XCTest

/// #426: under the phone's morph bar a few pages left their own toolbar control out, on the
/// understanding that the bar draws it. The bar draws a page's actions only where the page is a
/// tab's root, so opened from Settings (or in a sheet) they had none: Settings › Projects said
/// "Tap + to make one" with no + on the page, API Keys & Environment could not add a variable,
/// the Board pushed from Settings had no New Task, and Sessions no Options. The Scheduled Tasks
/// tab's + asked a page that is not there and did nothing; it is gone.
///
/// On the iPad (no morph bar) the pages are as they were; `testPagesOpenedFromSettings…` runs
/// there as well, for a still. Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set.
@MainActor
final class PageOwnButtonsUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private func launch(url: String, token: String, tab: String) {
        let args = ["-companionPromptShown", "YES", "-launchTab", tab, "-colorSchemePreference", "light",
                    "-tabLayout", "chats,projects,cron,settings", "-tabLayout.homeFirstApplied", "YES"]
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
    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let folder = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"], !folder.isEmpty {
            let d = URL(fileURLWithPath: folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: d.appendingPathComponent("\(name).png"))
        }
    }
    /// A button in a navigation bar (the page's own), by its label.
    private func barButton(_ label: String) -> XCUIElement {
        app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    private var wide: Bool { app.windows.firstMatch.frame.width > 700 }

    /// A pushed page's own control: under the phone's morph bar the bar draws it beside its Back, by its id
    /// (#435); elsewhere (a wide window) it is in the page's own navigation bar, by its label.
    private func control(_ id: String, _ label: String) -> XCUIElement {
        let inBar = any(id)
        return inBar.waitForExistence(timeout: 5) ? inBar : barButton(label)
    }

    /// Under the morph bar: the control is in the bar's band, after the Back (VoiceOver reads Back first),
    /// once (the page's own bar item is not there too), and the audit finds nothing in the band.
    private func checkBar(_ id: String, _ label: String, page: String) throws {
        guard any("page.back").exists else { return }
        let c = any(id), back = any("page.back")
        XCTAssertTrue(c.exists && c.frame.minY < 120, "\(page): \(label) is not in the bar: \(c.frame)")
        XCTAssertLessThan(back.frame.midX, c.frame.midX, "\(page): \(label) comes before Back")
        XCTAssertFalse(barButton(label).exists && barButton(label).isHittable, "\(page): \(label) is in the page's own bar as well")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .elementDetection]) { issue in
            print("PAGE-AUDIT \(page) '\(issue.compactDescription)' label '\(issue.element?.label ?? "")' id '\(issue.element?.identifier ?? "")'")
            return (issue.element?.frame.minY ?? 1000) > 120
        }
    }

    /// Settings' row `id`, scrolled to and opened.
    private func openSettingsRow(_ id: String) {
        let row = any("settings.row.\(id)")
        XCTAssertTrue(any("settings.row.profile").waitForExistence(timeout: 20), "no Settings rows")
        for _ in 0..<10 where !(row.exists && row.isHittable) { app.swipeUp(velocity: .slow); pause(0.5) }
        XCTAssertTrue(row.exists && row.isHittable, "no \(id) row on Settings")
        row.tap(); pause(1.5)
    }

    /// Back to Settings' root: the bar's Back on the phone, the system's elsewhere.
    private func back() {
        if any("page.back").exists { any("page.back").tap() }
        else if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
        pause(1.5)
        for _ in 0..<10 where !(any("settings.row.profile").exists && any("settings.row.profile").isHittable) { app.swipeDown(velocity: .fast); pause(0.3) }
    }

    /// The four pages opened from Settings each have their own control, and it does what it says.
    func testPagesOpenedFromSettingsKeepTheirOwnButtons() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        launch(url: url, token: token, tab: "settings")
        let device = wide ? "ipad" : "iphone"

        // Settings › Projects: its own +, which opens New Project (#426's screen).
        openSettingsRow("projects")
        let plus = control("projects.new", "New project")
        XCTAssertTrue(plus.waitForExistence(timeout: 10) && plus.isHittable, "Settings › Projects has no +")
        shot("426-\(device)-settings-projects")
        try checkBar("projects.new", "New project", page: "Projects")
        if plus.exists {
            plus.tap()
            XCTAssertTrue(app.navigationBars["New Project"].waitForExistence(timeout: 5), "the + did not open New Project")
            app.buttons["Cancel"].firstMatch.tap(); pause(1)
        }
        back()

        // Settings › API Keys & Environment: its own Add, which asks for the variable.
        openSettingsRow("env")
        let add = control("env.add", "Add")
        XCTAssertTrue(add.waitForExistence(timeout: 10) && add.isHittable, "API Keys & Environment has no Add")
        shot("426-\(device)-settings-env")
        try checkBar("env.add", "Add", page: "API Keys")
        if add.exists {
            add.tap()
            XCTAssertTrue(app.alerts["Add variable"].waitForExistence(timeout: 5), "Add did not ask for a variable")
            app.alerts.buttons["Cancel"].firstMatch.tap(); pause(1)
        }
        back()

        // Settings › Board: its own New Task (the mock has the kanban plugin).
        openSettingsRow("kanban")
        let newTask = control("board.new", "New Task")
        XCTAssertTrue(newTask.waitForExistence(timeout: 10) && newTask.isHittable, "the Board from Settings has no New Task")
        shot("426-\(device)-settings-board")
        try checkBar("board.new", "New Task", page: "Board")
        if newTask.exists {
            newTask.tap()
            XCTAssertTrue(app.navigationBars["New Task"].waitForExistence(timeout: 5), "New Task did not open its sheet")
            app.buttons["Cancel"].firstMatch.tap(); pause(1)
        }
        back()

        // Settings › Sessions: its own Options, with Advanced in it.
        openSettingsRow("sessions")
        let options = control("sessions.options", "Options")
        XCTAssertTrue(options.waitForExistence(timeout: 10) && options.isHittable, "Sessions from Settings has no Options")
        shot("426-\(device)-settings-sessions")
        try checkBar("sessions.options", "Options", page: "Sessions")
        if options.exists {
            options.tap()
            XCTAssertTrue(app.buttons["Advanced"].waitForExistence(timeout: 5), "Options has no Advanced")
            shot("426-\(device)-settings-sessions-options")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap(); pause(1)
        }
        back()
    }

    /// The Projects tab's + (the bar's) opens one New Project, on that tab, with Settings ›
    /// Projects open on the Settings tab; and the Scheduled Tasks tab has no + that does nothing.
    func testTheProjectsTabsPlusOpensOneSheetAndScheduledTasksHasNone() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "settings")
        if wide { throw XCTSkip("the morph bar is the phone's") }
        openSettingsRow("projects")
        XCTAssertTrue(control("projects.new", "New project").waitForExistence(timeout: 10), "Settings › Projects has no +")

        // The Projects tab: the bar's +, one sheet.
        any("tab.projects").tap(); pause(1.5)
        let barPlus = any("projects.new")
        XCTAssertTrue(barPlus.waitForExistence(timeout: 10) && barPlus.isHittable, "the Projects tab has no + in the bar")
        barPlus.tap()
        XCTAssertTrue(app.navigationBars["New Project"].waitForExistence(timeout: 5), "the bar's + did not open New Project")
        pause(1)
        XCTAssertEqual(app.navigationBars.matching(identifier: "New Project").count, 1, "more than one New Project")
        shot("426-projects-tab-sheet")
        app.buttons["Cancel"].firstMatch.tap(); pause(1.5)
        // Settings' copy of the page did not answer the bar too: no New Project waiting there.
        any("tab.settings").tap(); pause(2)
        XCTAssertFalse(app.navigationBars["New Project"].exists, "Settings › Projects opened a New Project for the Projects tab's +")
        shot("426-settings-after-projects-tab-plus")

        // Scheduled Tasks: no + in the bar (it asked for a page that is not there).
        any("tab.cron").tap(); pause(1.5)
        shot("426-scheduled-tasks")
        XCTAssertFalse(any("tasks.add").exists, "the Scheduled Tasks tab still has a + that does nothing")
        XCTAssertFalse(any("cron.plus").exists, "the Scheduled Tasks tab has a +")
    }

    /// Chats › Filters › Manage projects…: the sheet's page has its own +.
    func testManageProjectsSheetHasItsPlus() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "chats")
        let filters = any("chats.filters")
        XCTAssertTrue(filters.waitForExistence(timeout: 20), "no Filters on Chats")
        pause(2)
        filters.tap()
        let manage = app.buttons["Manage projects…"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5), "no Manage projects in Filters")
        manage.tap(); pause(1.5)
        let plus = barButton("New project")
        XCTAssertTrue(plus.waitForExistence(timeout: 10) && plus.isHittable, "Manage projects has no +")
        shot("426-manage-projects")
        if plus.exists {
            plus.tap()
            XCTAssertTrue(app.navigationBars["New Project"].waitForExistence(timeout: 5), "the + did not open New Project")
            app.buttons["Cancel"].firstMatch.tap(); pause(1)
        }
        app.buttons["Done"].firstMatch.tap()
    }

    /// #435 with one board (the mock's MOCK_ONE_BOARD=1, named "one-board" in HERMES_E2E_ARGS): the Board pushed from
    /// Settings has no picker and no bar of its own, so the morph bar draws its options and New Task beside its Back.
    func testTheBoardWithOneBoardHasItsControlsInTheBar() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        guard (ProcessInfo.processInfo.environment["HERMES_E2E_ARGS"] ?? "").contains("one-board") else { throw XCTSkip("the mock is not in its one-board mode") }
        launch(url: url, token: token, tab: "settings")
        if wide { throw XCTSkip("the morph bar is the phone's") }
        openSettingsRow("kanban")
        let newTask = any("board.new"), options = any("board.options")
        XCTAssertTrue(newTask.waitForExistence(timeout: 10) && newTask.isHittable, "no New Task in the bar")
        XCTAssertTrue(options.exists && options.isHittable, "no Board options in the bar")
        shot("435-iphone-settings-board-one")
        try checkBar("board.new", "New Task", page: "Board, one board")
        XCTAssertLessThan(options.frame.midX, newTask.frame.midX, "Board options comes after New Task")
        newTask.tap()
        XCTAssertTrue(app.navigationBars["New Task"].waitForExistence(timeout: 5), "New Task did not open its sheet")
        app.buttons["Cancel"].firstMatch.tap(); pause(1)
        options.tap()
        XCTAssertTrue(app.buttons["Refresh"].waitForExistence(timeout: 5), "Board options has no Refresh")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap(); pause(1)
    }
}
