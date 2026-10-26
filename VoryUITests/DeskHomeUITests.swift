import XCTest

/// Duo stage 4: Home as a desk on a window folded across (the Duo half open like a laptop): the greeting and who's
/// working above the fold, what needs you (approvals answered in place) and the rest of Home below it (`DeskSplit`).
/// Runs in whatever pose the simulator is in; the page, the panel, the cards, the fold and the loads come off Home's
/// DEBUG readout (`-vory-desk-frames`, `desk.frames`), our bars' frames off `morph.bar` and the tab buttons. Driven by
/// HERMES_E2E_DESK_CASE:
/// - "frames": Home with nothing waiting; with HERMES_E2E_EXPECT=split, the panel under our top bar's row and above the
///   fold, "Nothing needs you" below the fold and above our tab bar; with "one", Home as everywhere else. Every frame is
///   printed (DESK) for a compare with the release head's.
/// - "cards": HERMES_E2E_WAITING chats (1 or 2) left waiting on an approval (the mock's turn ends on one), then Home: the
///   cards below the fold, Allow once and Deny at least 50 pt tall and above our tab bar once scrolled to; then Allow once
///   on the first card answers it in place (it goes, and the next card takes its place).
/// - "posture": Home scrolled down, then the posture changed from outside (HERMES_E2E_SIGNAL_DIR: this test writes
///   ready-N and waits for posed-N): split, one list, split again; the scroll kept (the heading stays scrolled off, so the
///   scroll view kept its place), and no load added (the readout's count).
/// - "oracle": what VoiceOver stops on (`-vory-ax-oracle`), printed in order.
/// - "audit": performAccessibilityAudit on Home, every type: every issue printed, for the run's compare with the release
///   head's in the same pose (none, or only issues it has today; the DEBUG readout's left out).
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set (the mock).
@MainActor
final class DeskHomeUITests: XCTestCase {
    private var app: XCUIApplication!
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func hittable(_ q: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if let e = q.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { return e }
            pause(0.3)
        } while Date() < end
        return nil
    }

    /// The readout: "page x y w h;panel x y w h;cards x y w h;fold x y w h|none;split yes|no;loads n".
    private struct Readout { var page = CGRect.null, panel = CGRect.null, cards = CGRect.null, fold: CGRect?, split = false, loads = 0 }
    private func readout() -> Readout? {
        let r = any("desk.frames")
        guard r.waitForExistence(timeout: 5) else { return nil }
        var out = Readout()
        for part in r.label.split(separator: ";") {
            let w = part.split(separator: " ")
            guard let key = w.first else { continue }
            let n = w.dropFirst().compactMap { Double($0) }
            let rect = n.count == 4 ? CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) : nil
            switch key {
            case "page": out.page = rect ?? .null
            case "panel": out.panel = rect ?? .null
            case "cards": out.cards = rect ?? .null
            case "fold": out.fold = rect
            case "split": out.split = w.last == "yes"
            case "loads": out.loads = n.first.map { Int($0) } ?? 0
            default: break
            }
        }
        return out
    }

    private func signal(_ name: String) {
        guard let dir = env["HERMES_E2E_SIGNAL_DIR"], !dir.isEmpty else { return }
        FileManager.default.createFile(atPath: (dir as NSString).appendingPathComponent(name), contents: Data())
        print("DESK signal \(name)")
    }
    private func waitFor(_ name: String, timeout: TimeInterval = 90) -> Bool {
        guard let dir = env["HERMES_E2E_SIGNAL_DIR"], !dir.isEmpty else { return false }
        let path = (dir as NSString).appendingPathComponent(name), end = Date().addingTimeInterval(timeout)
        while Date() < end { if FileManager.default.fileExists(atPath: path) { return true }; pause(0.5) }
        return false
    }

    /// Our top bar's row bottom, and our tab bar's top (its buttons'), in the window.
    private func bars() -> (rowBottom: CGFloat, barTop: CGFloat) {
        let bar = any("morph.bar")
        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.'")).allElementsBoundByIndex.filter { $0.exists }
        return (bar.exists ? bar.frame.maxY : 0, tabs.map(\.frame.minY).min() ?? app.windows.firstMatch.frame.maxY)
    }

    private func choices() -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label IN {'Allow once', 'Deny'}")).allElementsBoundByIndex.filter { $0.exists }
    }

    /// The desk's frames against the fold and our bars; `scrolled`, the bottom half scrolled, so what needs you may have
    /// gone up under the fold's edge (the scroll clips it there) and isn't checked.
    private func checkDesk(_ state: String, scrolled: Bool = false) -> Readout? {
        guard let r = readout() else { XCTFail("\(state): no desk.frames readout"); return nil }
        let (rowBottom, barTop) = bars()
        print("DESK \(state) page \(r.page) panel \(r.panel) cards \(r.cards) fold \(r.fold.map { "\($0)" } ?? "none") split \(r.split) loads \(r.loads) row \(rowBottom) tabs \(barTop)")
        guard let fold = r.fold else { XCTFail("\(state): no fold across the window"); return r }
        XCTAssertTrue(r.split, "\(state): Home isn't a desk under a fold across")
        XCTAssertGreaterThanOrEqual(r.panel.minY, rowBottom - 0.5, "\(state): the panel runs under our top bar's row (\(r.panel) vs \(rowBottom))")
        XCTAssertLessThanOrEqual(r.panel.maxY, fold.minY + 0.5, "\(state): the panel reaches the fold (\(r.panel) vs \(fold))")
        if !scrolled { XCTAssertGreaterThanOrEqual(r.cards.minY, fold.maxY - 0.5, "\(state): what needs you reaches the fold (\(r.cards) vs \(fold))") }
        XCTAssertLessThanOrEqual(r.page.maxY, barTop + 0.5, "\(state): the page runs under our tab bar (\(r.page) vs \(barTop))")
        let heading = any("home.heading")
        if heading.exists {
            print("DESK \(state) heading \(heading.frame)")
            XCTAssertLessThanOrEqual(heading.frame.maxY, fold.minY + 0.5, "\(state): the greeting reaches the fold")
        }
        return r
    }

    /// Opens the chat titled `title` on Chats, asks the mock's turn, waits for its approval, and comes back to the list (at
    /// once if the chat is waiting already).
    private func leaveWaiting(_ title: String) throws {
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND identifier != 'chat.titlePill'", title))
        try XCTUnwrap(hittable(rows, timeout: 40), "no \(title) row").tap()
        let composer = app.textViews["composer.text"].firstMatch
        // A chat left waiting by an earlier run (the mock keeps it) has its card where the composer goes: it waits already.
        let allow = app.buttons["Allow once"].firstMatch
        let end = Date().addingTimeInterval(20)
        while !composer.exists && !allow.exists && Date() < end { pause(0.5) }
        if allow.exists && !composer.exists {
            print("DESK \(title) was waiting already")
            try XCTUnwrap(hittable(app.buttons.matching(identifier: "chat.back"), timeout: 10), "no Back in \(title)").tap()
            pause(1.5)
            return
        }
        XCTAssertTrue(composer.exists, "no composer in \(title)")
        composer.tap()
        composer.typeText("Clean up the old logs")
        try XCTUnwrap(hittable(app.buttons.matching(identifier: "composer.send"), timeout: 5), "no send").tap()
        XCTAssertTrue(app.buttons["Allow once"].firstMatch.waitForExistence(timeout: 90), "no approval in \(title)")
        pause(1)
        try XCTUnwrap(hittable(app.buttons.matching(identifier: "chat.back"), timeout: 10), "no Back in \(title)").tap()
        pause(1.5)
    }

    /// Scrolls Home's page by a slow drag from `y` (window space), 250 pt up: in the bottom half on the desk, clear of
    /// the who's-working panel's own scroll.
    private func dragPage(from y: CGFloat) {
        let window = app.windows.firstMatch, origin = window.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: window.frame.midX, dy: y))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: window.frame.midX, dy: y - 250)))
        pause(1.5)
    }

    private func toHome() throws {
        try XCTUnwrap(hittable(app.buttons.matching(identifier: "tab.dashboard"), timeout: 20), "no Home tab").tap()
        pause(3)
    }

    /// The screen the launch started on: Home, the Chats list, a chat, or unknown after 30 s. A compare needs the one the
    /// launch asked for (`-launchTab`); a launch that started anywhere else is a void run, not a finding.
    private func launchScreen() -> String {
        let end = Date().addingTimeInterval(30)
        repeat {
            if any("home.heading").exists { return "home" }
            if any("chats.sort").exists { return "chats" }
            if app.buttons["chat.back"].firstMatch.exists { return "chat" }
            pause(0.5)
        } while Date() < end
        return "unknown"
    }

    func testHomeAsADesk() throws {
        guard let url = env["HERMES_E2E_URL"], let token = env["HERMES_E2E_TOKEN"], !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set")
        }
        continueAfterFailure = true
        let deskCase = env["HERMES_E2E_DESK_CASE"] ?? "frames"
        let expect = env["HERMES_E2E_EXPECT"] ?? "split"
        let waiting = deskCase == "cards" ? max(1, min(2, Int(env["HERMES_E2E_WAITING"] ?? "2") ?? 2)) : 0
        // `-restore.openChat none`: the last open chat isn't reopened (its saved record reads as nothing for this launch,
        // the argument domain only), so every launch starts on the tab it asks for, in both copies.
        var args = ["-companionPromptShown", "YES", "-launchTab", waiting > 0 ? "chats" : "dashboard", "-restore.openChat", "none",
                    "-vory-desk-frames", "-colorSchemePreference", env["HERMES_E2E_SCHEME"] ?? "light"]
        if deskCase == "oracle" { args.append("-vory-ax-oracle") }
        if (env["HERMES_E2E_ARGS"] ?? "").contains("xxxlarge") { args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }
        if let bundle = env["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop"] + args
        } else {
            app = XCUIApplication(); app.launchArguments = args
        }
        app.launch()
        print("DESK launch screen \(launchScreen())")
        for title in ["Disk cleanup", "Weekly dependency audit"].prefix(waiting) { try leaveWaiting(title) }
        if waiting > 0 { try toHome() } else {
            XCTAssertTrue(any("home.heading").waitForExistence(timeout: 40), "Home isn't in front")
            pause(3)
        }
        print("DESK state \(deskCase) at \(String(format: "%.1f", Date().timeIntervalSince1970))")

        switch deskCase {
        case "cards":
            if expect == "split" { _ = checkDesk("cards") }
            let first = choices()
            for b in first { print("DESK cards choice '\(b.label)' frame \(b.frame)") }
            if expect == "split" {
                for b in first where b.isHittable { XCTAssertGreaterThanOrEqual(b.frame.height, 50 - 0.5, "'\(b.label)' isn't large on the desk") }
            }
            // Scrolled to the first card's choices: above our tab bar.
            if let deny = first.first(where: { $0.label == "Deny" }), !deny.isHittable { dragPage(from: bars().barTop - 30) }
            print("DESK state cards-scrolled at \(String(format: "%.1f", Date().timeIntervalSince1970))")
            let (_, barTop) = bars()
            if let allow = choices().first(where: { $0.label == "Allow once" }) {
                XCTAssertLessThanOrEqual(allow.frame.maxY, barTop + 0.5, "Allow once runs under our tab bar")
                let before = app.buttons.matching(NSPredicate(format: "label == 'Allow once'")).count
                allow.tap()
                pause(3)
                let after = app.buttons.matching(NSPredicate(format: "label == 'Allow once'")).count
                print("DESK cards answered: Allow once buttons \(before) -> \(after)")
                XCTAssertEqual(after, before - 1, "Allow once on Home didn't answer its card in place")
            } else { XCTFail("no Allow once on Home") }
        case "posture":
            // Scrolled down far enough that the heading is off the top in every pose.
            dragPage(from: (readout()?.fold?.maxY ?? 500) + 250)
            let r1 = expect == "split" ? checkDesk("posture-laptop-1", scrolled: true) : readout()
            signal("ready-1")
            XCTAssertTrue(waitFor("posed-1"), "no flat pose in time")
            pause(2)
            let r2 = readout()
            let heading = any("home.heading")
            print("DESK posture flat split \(r2?.split ?? false) loads \(r2?.loads ?? -1) heading \(heading.exists ? "\(heading.frame)" : "none") page \(r2?.page ?? .null)")
            XCTAssertEqual(r2?.split, false, "still a desk when flat")
            // The scroll kept its place: the heading, back in the scroll when flat, is still scrolled off its top.
            if let page = r2?.page, heading.exists { XCTAssertLessThan(heading.frame.minY, page.minY, "the scroll went back to its top going flat") }
            signal("ready-2")
            XCTAssertTrue(waitFor("posed-2"), "no laptop pose in time")
            pause(2)
            let r3 = checkDesk("posture-laptop-2", scrolled: true)
            print("DESK posture loads \(r1?.loads ?? -1) \(r2?.loads ?? -1) \(r3?.loads ?? -1)")
            XCTAssertEqual(r1?.loads, r2?.loads, "a load going flat")
            XCTAssertEqual(r1?.loads, r3?.loads, "a load coming back")
        case "oracle":
            let o = any("debug.voiceover")
            XCTAssertTrue(o.waitForExistence(timeout: 5), "no oracle")
            let stops = ((o.value as? String) ?? "").split(separator: "\n").map { String($0.split(separator: "|").first ?? "") }
            print("DESK oracle \(stops.count) stops: \(stops.joined(separator: " / "))")
        case "audit":
            var count = 0
            try app.performAccessibilityAudit { issue in
                let el = issue.element
                print("DESK audit issue '\(issue.compactDescription)' type \(el?.elementType.rawValue ?? 0) id '\(el?.identifier ?? "")' label '\(el?.label.prefix(60) ?? "")' frame \(el?.frame ?? .zero)")
                count += 1
                return true
            }
            print("DESK audit \(count) issues")
        default:
            if expect == "split" { _ = checkDesk("frames") } else if let r = readout() {
                print("DESK frames one list page \(r.page) fold \(r.fold.map { "\($0)" } ?? "none") split \(r.split)")
                XCTAssertFalse(r.split, "a desk without a fold across")
            }
            // Home's own frames, for the compare with the release head (which has no readout).
            for id in ["home.heading"] where any(id).exists { print("DESK frames element \(id) frame \(any(id).frame)") }
            let titles = ["Overview", "Bots", "Pick up where you left off", "Since you were here", "Who's working", "Nothing needs you"]
            for t in app.staticTexts.matching(NSPredicate(format: "label IN %@", titles)).allElementsBoundByIndex where t.exists {
                print("DESK frames text '\(t.label)' frame \(t.frame)")
            }
            for b in app.buttons.matching(NSPredicate(format: "label IN {'Edit Home', 'Settings'}")).allElementsBoundByIndex where b.exists {
                print("DESK frames button '\(b.label)' frame \(b.frame)")
            }
        }
    }
}
