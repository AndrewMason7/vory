import XCTest

/// Matt on 1.5 (18): "don't allow taps behind the nav bar on iPhone as when the group chats appear
/// behind nav bar I can tap it when touching the nav bar". Points on the tab bar that miss its
/// buttons are tapped one at a time, with the page behind at rest: on Chats (the list runs under
/// the bar), on Bots (a group chat brought under the bar) and on Home. Before the fix, a touch
/// 2 pt over the bar's top edge, or in the notch at the top of a gap, opened the row behind it;
/// mid-height in a gap the nearest control took it. None may reach the page behind. Beside the
/// bar, 8 pt in from the screen's edge, the row must still answer: the bar takes its shapes,
/// not a strip.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set. HERMES_E2E_BUNDLE=com.vorantx.vory.demo
/// drives the demo copy. Wants the mock with --extra-sessions 60 --extra-bots 12.
@MainActor
final class TabBarGapsUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    /// More launch arguments for the next launch.
    private var launchArgs: [String] = []

    private func launch(url: String, token: String, tab: String) {
        let args = ["-companionPromptShown", "YES", "-launchTab", tab, "-colorSchemePreference", "light",
                    "-tabLayout", "dashboard,chats,bots,settings", "-tabLayout.homeFirstApplied", "YES"] + launchArgs
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
    private func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func at(_ p: CGPoint) -> XCUICoordinate { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y)) }

    /// One call to the mock's own controls.
    private final class Answer: @unchecked Sendable { var json: [String: Any]? }
    private func mock(_ gateway: String, _ path: String, _ body: [String: Any]) {
        guard let url = URL(string: gateway + path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 12)
    }

    /// The bar's shapes, from the mic circle (its frame is its circle on the simulator and the
    /// phone; the compose button's is only its glyph on the phone, and the tab slots' are narrower
    /// than the capsule): the compose circle the same size one 6 pt gap after it, the side margins
    /// equal, the capsule ending one gap before the mic.
    private func barShapes() -> (capsule: CGRect, mic: CGRect, compose: CGRect) {
        let mic = any("chats.voice").frame
        let compose = CGRect(x: mic.maxX + 6, y: mic.minY, width: mic.width, height: mic.height)
        let left = app.frame.width - compose.maxX
        return (CGRect(x: left, y: mic.minY, width: mic.minX - 6 - left, height: mic.height), mic, compose)
    }

    /// The points on the bar that miss every button: the middle of the gap between the capsule and
    /// the mic and of the gap between the circles, the notch at the top of the first gap, 2 pt
    /// over the capsule's and the mic's top edges, and 2 pt past the capsule's left end. All of
    /// them lie on the bar's drawn shapes or within its 4 pt touch margin.
    private func gapPoints() -> [(String, CGPoint)] {
        let (cap, mic, new) = barShapes()
        return [("capsule-mic", CGPoint(x: mic.minX - 3, y: mic.midY)),
                ("mic-compose", CGPoint(x: (mic.maxX + new.minX) / 2, y: new.midY)),
                ("notch", CGPoint(x: mic.minX - 3, y: mic.minY + 4)),
                ("over-capsule", CGPoint(x: cap.midX, y: cap.minY - 2)),
                ("over-mic", CGPoint(x: mic.midX, y: mic.minY - 2)),
                ("left-end", CGPoint(x: cap.minX - 2, y: cap.midY))]
    }

    /// What a tap did: "row" (the page behind answered: a chat, a pushed page or a group chat
    /// opened), "control" (a bar control answered: a new chat from compose or the mic, another
    /// tab, a sheet), or "nothing".
    private func outcome(_ tab: String) -> String {
        if any("chat.dock").exists {
            let pill = any("chat.titlePill")
            return pill.exists && pill.label.contains("New chat") ? "control:new-chat" : "row:chat"
        }
        if any("page.back").exists { return "row:page" }
        if any("group.back").exists { return "row:group" }
        let slot = any("tab.\(tab)")
        if !slot.exists || !slot.isHittable { return "row:covered" }
        if !slot.isSelected { return "control:tab" }
        if app.buttons["Cancel"].exists { return "control:sheet" }
        return "nothing"
    }

    /// Taps each point on its own, from the page at rest (`setUp` launches and places it; it runs
    /// again after any tap that changed something). Returns each point's outcome.
    private func probe(_ tab: String, _ points: () -> [(String, CGPoint)], rows: () -> XCUIElementQuery, setUp: () -> Void) -> [String: String] {
        var result: [String: String] = [:]
        setUp()
        let (cap, mic, new) = barShapes()
        print("GAP-SHAPES \(tab) capsule \(cap) mic \(mic) compose \(new) window \(app.frame.size)")
        for (name, p) in points() {
            let behind = rows().allElementsBoundByIndex.contains { $0.exists && $0.frame.contains(p) }
            at(p).tap(); pause(1.5)
            let o = outcome(tab)
            result[name] = o
            print("GAP-TAP \(tab) \(name) at (\(Int(p.x)), \(Int(p.y))) row-behind=\(behind) -> \(o)")
            if o != "nothing" { shot("\(tab)-\(name)-\(o)"); setUp() }
        }
        return result
    }

    func testTabBarGapsSwallowTaps() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        // Group chats on Bots, enough of them to put one under the bar.
        for i in 1...6 { mock(url, "/api/_mock/rooms", ["name": "Gap room \(i)", "handles": ["default", "work"]]) }
        let notBar = NSPredicate(format: "NOT (identifier BEGINSWITH 'tab.') AND NOT (identifier BEGINSWITH 'chats.')")

        // Chats: the list runs under the bar at rest. Beside the bar, 8 pt in from the screen's
        // edge (inside the 21 pt side margin, outside the touch margin), the row must still answer:
        // the bar takes its shapes, not a strip.
        var chats: [String: String] = [:]
        chats = probe("chats", { self.gapPoints() + [("beside", CGPoint(x: 8, y: self.barShapes().capsule.midY))] }, rows: { app.buttons.matching(notBar) }) {
            if app != nil, app.state == .runningForeground { app.terminate() }
            launch(url: url, token: token, tab: "chats")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch.waitForExistence(timeout: 40), "no chat rows")
            pause(2)
        }

        // Bots: a group chat card brought under the bar and held there.
        let bots = probe("bots", { self.gapPoints() }, rows: { app.buttons.matching(NSPredicate(format: "label CONTAINS 'Gap room'")) }) {
            if app != nil, app.state == .runningForeground { app.terminate() }
            launch(url: url, token: token, tab: "bots")
            XCTAssertTrue(any("bots.newBot").waitForExistence(timeout: 15), "no Bots page")
            pause(2)
            let room = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Gap room 3'")).firstMatch
            for _ in 0..<8 where !(room.exists && room.frame.minY > 0 && room.frame.maxY < app.frame.maxY) { app.swipeUp(velocity: .slow); pause(0.8) }
            XCTAssertTrue(room.exists, "no group chat on Bots")
            let delta = barShapes().capsule.midY - room.frame.midY
            let start = CGPoint(x: app.frame.midX, y: delta > 0 ? room.frame.midY : app.frame.midY)
            at(start).press(forDuration: 0.1, thenDragTo: at(CGPoint(x: start.x, y: start.y + delta)), withVelocity: .slow, thenHoldForDuration: 0.6)
            pause(1.5)
        }

        // Home: whatever its cards are.
        let home = probe("dashboard", { self.gapPoints() }, rows: { app.buttons.matching(notBar) }) {
            if app != nil, app.state == .runningForeground { app.terminate() }
            launch(url: url, token: token, tab: "dashboard")
            XCTAssertTrue(any("tab.dashboard").waitForExistence(timeout: 15), "no Home tab")
            pause(3)
        }

        for (tab, r) in [("Chats", chats), ("Bots", bots), ("Home", home)] {
            for (name, o) in r where name != "beside" {
                XCTAssertFalse(o.hasPrefix("row"), "a tap on the bar's \(name) on \(tab) reached the page behind it (\(o))")
            }
        }
        XCTAssertTrue(chats["beside"]?.hasPrefix("row") == true, "a tap beside the bar no longer reaches the list (\(chats["beside"] ?? "none")): the bar took a strip")
    }

    // MARK: Pressing the bar's own buttons

    /// The screen as pixels, rows from the top, four bytes a pixel.
    private func pixels(_ s: XCUIScreenshot) -> (data: [UInt8], w: Int, h: Int)? {
        guard let cg = s.image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? (data, w, h) : nil
    }

    /// The share of `band`'s pixels (points) that differ visibly between two screenshots.
    private func changed(_ a: XCUIScreenshot, _ b: XCUIScreenshot, in band: CGRect) -> Double {
        guard let pa = pixels(a), let pb = pixels(b), pa.w == pb.w, pa.h == pb.h else { return 1 }
        let k = CGFloat(pa.w) / app.frame.width
        let r = CGRect(x: band.minX * k, y: band.minY * k, width: band.width * k, height: band.height * k).integral
            .intersection(CGRect(x: 0, y: 0, width: pa.w, height: pa.h))
        guard !r.isEmpty else { return 0 }
        var n = 0, total = 0
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) {
                let i = (y * pa.w + x) * 4
                let d = abs(Int(pa.data[i]) - Int(pb.data[i])) + abs(Int(pa.data[i + 1]) - Int(pb.data[i + 1])) + abs(Int(pa.data[i + 2]) - Int(pb.data[i + 2]))
                if d > 30 { n += 1 }
                total += 1
            }
        }
        return Double(n) / Double(total)
    }

    /// The group chats' rows on Bots, one element each (a row is under 120 pt tall), top to bottom.
    private func roomRows() -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gap room'")).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 30 && $0.frame.height < 120 }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// Bots with a group chat brought under the bar, its top `above` points showing over the
    /// bar's top edge and the rest under its buttons (as in Matt's recording), held there.
    /// Returns the row's label: its frame is read again after each press.
    private func roomUnderTheBar(url: String, token: String, above: CGFloat) -> String? {
        if app != nil, app.state == .runningForeground { app.terminate() }
        launch(url: url, token: token, tab: "bots")
        XCTAssertTrue(any("bots.newBot").waitForExistence(timeout: 15), "no Bots page")
        pause(2)
        let target = barShapes().capsule.minY - above
        // With many bots the group chats start below the screen, out of the tree until near.
        for _ in 0..<10 where roomRows().filter({ $0.frame.minY >= target - 2 }).isEmpty { app.swipeUp(velocity: .slow); pause(0.8) }
        // The row nearest the spot, moved there by a slow drag; picked again each time (the
        // list settles after its first layout) and corrected until one sits there (a drag loses
        // a little to the scroll's slop).
        var label = ""
        for _ in 0..<9 {
            // From below the spot: the page scrolls up as far as it needs, and its top may be in
            // the way the other way.
            guard let row = roomRows().filter({ $0.frame.minY >= target - 2 }).min(by: { $0.frame.minY < $1.frame.minY }) else {
                XCTFail("no group chat rows on Bots"); return nil
            }
            label = row.label
            let delta = target - row.frame.minY
            print("TAB-PRESS placing '\(label.prefix(12))' at \(row.frame) by \(delta)")
            if abs(delta) < 3 { break }
            // A drag under the scroll's slop does not move it: a small one goes 40 pt past the
            // spot, and the next row below is taken from there.
            // Each drag lands about 10 pt short (the slop it spends before the scroll moves).
            let step = max(-480, abs(delta) < 25 ? delta - 40 : delta - 10)
            let start = CGPoint(x: app.frame.midX, y: step > 0 ? 260 : 660)
            at(start).press(forDuration: 0.1, thenDragTo: at(CGPoint(x: start.x, y: start.y + step)), withVelocity: .slow, thenHoldForDuration: 0.6)
            pause(1.2)
        }
        return label
    }

    /// Each of `items` pressed in turn while `band` (the part of a card or chip behind the bar
    /// that still shows) is watched; `place` sets the scene up and returns the band, again after
    /// a press that changed the page. Screens are taken during the press (a press blocks the
    /// test, so they are scheduled before it); the largest change per item counts. An item that
    /// `point` places is pressed there, not in its element's middle.
    private func pressWatching(_ items: [(id: String, hold: Double, slide: Bool)], point: (String) -> CGPoint? = { _ in nil }, place: () -> CGRect?) -> [String: Double] {
        var worst: [String: Double] = [:]
        var band: CGRect?
        for item in items {
            if band == nil { band = place() }
            guard let watched = band else { return worst }
            let rest = XCUIScreen.main.screenshot()
            let c: CGPoint
            if let p = point(item.id) {
                c = p
            } else {
                let button = item.id.hasPrefix("label:") ? app.buttons[String(item.id.dropFirst(6))].firstMatch : any(item.id)
                XCTAssertTrue(button.exists, "no \(item.id)")
                c = CGPoint(x: button.frame.midX, y: button.frame.midY)
            }
            nonisolated(unsafe) var shots: [XCUIScreenshot] = []
            for t in stride(from: 0.15, through: 0.15 + item.hold + 0.3, by: 0.1) {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { shots.append(XCUIScreen.main.screenshot()) } }
            }
            // Slid off before lifting: the button does not fire (the circles; a tab's capsule
            // would take the slide as its lens drag).
            if item.slide {
                at(c).press(forDuration: item.hold, thenDragTo: at(CGPoint(x: c.x, y: c.y - 160)), withVelocity: .fast, thenHoldForDuration: 0)
            } else {
                at(c).press(forDuration: item.hold)
            }
            pause(0.6)
            let d = shots.map { changed(rest, $0, in: watched) }.max() ?? 0
            worst[item.id] = d
            print("TAB-PRESS \(item.id) at (\(Int(c.x)), \(Int(c.y))) held \(item.hold) s: \(shots.count) screens, band \(watched), most changed \(String(format: "%.3f", d))")
            let restShot = XCTAttachment(screenshot: rest); restShot.name = "rest-\(item.id)"; restShot.lifetime = .keepAlways; add(restShot)
            if let i = shots.indices.max(by: { changed(rest, shots[$0], in: watched) < changed(rest, shots[$1], in: watched) }) {
                let a = XCTAttachment(screenshot: shots[i]); a.name = "press-\(item.id)"; a.lifetime = .keepAlways; add(a)
            }
            if !item.slide { band = nil }
        }
        return worst
    }

    /// The bar's buttons: the tabs pressed and held (a press switches or scrolls the page, so the
    /// scene is set again after it), the mic and compose held less than their own press and hold
    /// (0.4 s) and slid off, so nothing opens.
    private let barButtons: [(id: String, hold: Double, slide: Bool)] = [("tab.bots", 0.5, false), ("chats.voice", 0.3, true), ("chats.new", 0.3, true), ("tab.chats", 0.5, false), ("tab.dashboard", 0.5, false), ("tab.settings", 0.5, false)]

    /// What a press may change in a watched band without the thing behind showing pressed: the
    /// faces' blinks read under 1%, a card's press grow about 5%.
    private let pressedChange = 0.02

    /// A prompt left over the app from an earlier run (the microphone) is declined.
    private func declineLeftoverPrompt() {
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Don’t Allow", "Don't Allow", "OK"] where board.buttons[name].firstMatch.exists { board.buttons[name].firstMatch.tap(); pause(0.5) }
    }

    /// Matt on 1.5 (20): "tapping the nav bar bot item I can see the group chat behind it show a
    /// click": in his recording the group chat's card under the bar grows a little (its glass
    /// press) while the Bots tab item is held. With a card under the bar (its title showing over
    /// the bar, the rest under the buttons), the bar's buttons are pressed: the card's part above
    /// the bar, edges included, looks as it did at rest (judgement call #22). Simulator only:
    /// the phone's screens wait for a press to end.
    func testPressingTheBarLeavesTheRowBehindAlone() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        // Enough group chats that one can be scrolled to the bar from either side.
        for i in 1...12 { mock(url, "/api/_mock/rooms", ["name": "Gap room \(i)", "handles": ["default", "work"]]) }
        declineLeftoverPrompt()
        let worst = pressWatching(barButtons) {
            guard let label = roomUnderTheBar(url: url, token: token, above: 24) else { return nil }
            let room = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.first { $0.frame.height < 120 }
            let cap = barShapes().capsule
            guard let room, room.frame.maxY > cap.midY + 4, room.frame.minY < cap.minY - 16 else {
                XCTFail("the row is not under the bar with its top showing: \(String(describing: room?.frame)) bar \(cap)"); return nil
            }
            // The card's part above the bar, with a margin round its edges for a card that grows.
            return CGRect(x: room.frame.minX - 8, y: room.frame.minY - 8, width: room.frame.width + 16, height: cap.minY - 4 - (room.frame.minY - 8))
        }
        for (id, d) in worst.sorted(by: { $0.key < $1.key }) {
            XCTAssertLessThan(d, pressedChange, "pressing \(id) showed the group chat behind the bar pressed (\(String(format: "%.1f", d * 100))% of its visible part changed)")
        }
    }

    /// The same for a bot's card on Bots: its name pill under the bar, its face and the pill's top
    /// showing over it. Wants the mock with --extra-bots 12, so a card can be scrolled to the bar.
    func testPressingTheBarLeavesTheBotCardAlone() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        declineLeftoverPrompt()
        let worst = pressWatching(barButtons) {
            if app != nil, app.state == .runningForeground { app.terminate() }
            launch(url: url, token: token, tab: "bots")
            XCTAssertTrue(any("bots.actions.default").waitForExistence(timeout: 15), "no Bots page")
            pause(2)
            let cap = barShapes().capsule
            // A card is about 120 pt: its top 80 pt over the bar puts its pill under the buttons.
            let target = cap.minY - 80
            let menus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bots.actions.'"))
            var menu: XCUIElement?
            for _ in 0..<9 {
                // A card's top is its … less its 4 pt lift; the nearest one below the spot.
                guard let m = menus.allElementsBoundByIndex.filter({ $0.exists && $0.frame.minY + 4 >= target - 2 }).min(by: { $0.frame.minY < $1.frame.minY }) else { break }
                menu = m
                let delta = target - (m.frame.minY + 4)
                if abs(delta) < 3 { break }
                let step = max(-480, abs(delta) < 25 ? delta - 40 : delta - 10)
                let start = CGPoint(x: app.frame.midX, y: step > 0 ? 260 : 660)
                at(start).press(forDuration: 0.1, thenDragTo: at(CGPoint(x: start.x, y: start.y + step)), withVelocity: .slow, thenHoldForDuration: 0.6)
                pause(1.2)
            }
            guard let menu, menu.frame.minY + 4 < cap.minY - 40 else { XCTFail("no bot card brought to the bar"); return nil }
            let top = menu.frame.minY + 4
            print("TAB-PRESS bot card at \(top) bar \(cap)")
            // The card's name pill, the glass that grew (its face above is not glass): its part over
            // the bar, the card's grid column wide (the …'s right edge is 8 pt past the card).
            let pillTop = top + 60
            return CGRect(x: menu.frame.maxX - 8 - 178 - 8, y: pillTop - 4, width: 178 + 16, height: cap.minY - 4 - (pillTop - 4))
        }
        for (id, d) in worst.sorted(by: { $0.key < $1.key }) {
            XCTAssertLessThan(d, pressedChange, "pressing \(id) showed the bot card behind the bar pressed (\(String(format: "%.1f", d * 100))% of its visible part changed)")
        }
    }

    /// A chat: another bot's message (its chip) scrolled under the composer, its top showing over
    /// it; the composer's mic and + pressed and slid off, and the composer pressed over the chip
    /// (a glass reacts only to a press inside it): the chip looks as it did at rest.
    func testPressingTheComposerLeavesTheChipAlone() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        declineLeftoverPrompt()
        launch(url: url, token: token, tab: "chats")
        // A long chat, so its last rows can be scrolled down under the composer.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 40), "no chat rows")
        pause(1.5)
        row.tap()
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "no composer")
        pause(2)
        // A row from another bot: its chip, the thread's last row.
        composer.tap(); composer.typeText("Message from work: the export is paused until you say go."); pause(0.5)
        any("composer.send").tap(); pause(2)
        // The mock's reply asks to run a command; Deny ends the turn, and the composer, with its
        // mic again, takes the approval card's place.
        let deny = app.buttons["Deny"].firstMatch
        if deny.waitForExistence(timeout: 20) { deny.tap() }
        XCTAssertTrue(app.buttons["Dictate"].firstMatch.waitForExistence(timeout: 30), "the reply did not end: no mic in the composer")
        pause(1)
        // The keyboard down by a drag on the thread (XCTest lists a keyboard after it has gone, so
        // the composer's place tells).
        let dock = app.otherElements["chat.dock"].firstMatch
        for _ in 0..<3 where dock.frame.minY < app.frame.height * 0.75 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)), withVelocity: .fast, thenHoldForDuration: 0)
            pause(1.2)
        }
        pause(2)
        var chipFrame = CGRect.null
        let worst = pressWatching([("label:Dictate", 0.3, true), ("composer.attach", 0.3, true), ("composer-over-chip", 0.3, true)],
                                  point: { $0 == "composer-over-chip" ? CGPoint(x: chipFrame.midX, y: dock.frame.minY + 6) : nil }) {
            let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Message from work'")).allElementsBoundByIndex.last ?? app.buttons["none"]
            guard chip.exists else { XCTFail("no chip in the chat"); return nil }
            let target = dock.frame.minY - 12
            for _ in 0..<6 {
                let delta = target - chip.frame.minY
                if abs(delta) < 3 { break }
                let step = abs(delta) < 25 ? delta + (delta > 0 ? 40 : -40) : delta + (delta > 0 ? 10 : -10)
                let start = CGPoint(x: app.frame.midX, y: step > 0 ? 260 : 560)
                at(start).press(forDuration: 0.1, thenDragTo: at(CGPoint(x: start.x, y: start.y + max(-400, min(400, step)))), withVelocity: .slow, thenHoldForDuration: 0.6)
                pause(1.2)
            }
            print("TAB-PRESS chip \(chip.frame) dock \(dock.frame)")
            guard chip.frame.minY < dock.frame.minY - 4, chip.frame.maxY > dock.frame.minY + 4 else { XCTFail("the chip is not under the composer: \(chip.frame) dock \(dock.frame)"); return nil }
            chipFrame = chip.frame
            return CGRect(x: chip.frame.minX - 8, y: chip.frame.minY - 8, width: chip.frame.width + 16, height: dock.frame.minY - 4 - (chip.frame.minY - 8))
        }
        for (id, d) in worst.sorted(by: { $0.key < $1.key }) {
            XCTAssertLessThan(d, pressedChange, "pressing \(id) showed the chip behind the composer pressed (\(String(format: "%.1f", d * 100))% of its visible part changed)")
        }
    }

    /// Home's Range: its lens (the chosen option's glass) brought down to the bar, its middle on
    /// the bar's top edge, with Overview moved to the end of Home so the page can carry it there.
    /// The bar is pressed over the lens, on its top edge (the bar's touch margin) and 6 pt inside
    /// it, then its mic and compose: the lens's half over the bar looks as it did at rest. A
    /// regression guard: the lens keeps its interactive glass, and the bar has not set it off.
    func testPressingTheBarLeavesTheRangeAlone() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        declineLeftoverPrompt()
        var lensFrame = CGRect.null
        var cap = CGRect.null
        let worst = pressWatching([("bar-edge-over-lens", 0.3, true), ("bar-over-lens", 0.3, true), ("chats.voice", 0.3, true), ("chats.new", 0.3, true)],
                                  point: { id in
                                      switch id {
                                      case "bar-edge-over-lens": CGPoint(x: lensFrame.midX, y: cap.minY - 2)
                                      case "bar-over-lens": CGPoint(x: lensFrame.midX, y: cap.minY + 6)
                                      default: nil
                                      }
                                  }) {
            if app != nil, app.state == .runningForeground { app.terminate() }
            let layout = #"{"items":[{"card":"bots","size":"full"},{"card":"pickUp","size":"full"},{"card":"since","size":"full"},{"card":"overview","size":"full"}]}"#
            // Quoted, so the argument is read as a string, not as a property list. The range is
            // left at its default, 30 days.
            launchArgs = ["-home.layout", "\"" + layout.replacingOccurrences(of: "\"", with: "\\\"") + "\""]
            launch(url: url, token: token, tab: "dashboard")
            launchArgs = []
            // The options: "Range" each before they were named, "7 days" and so on after.
            let options = app.buttons.matching(NSPredicate(format: "label IN {'Range', '7 days', '30 days', '90 days'}"))
            XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 20), "no Range on Home")
            pause(2)
            cap = barShapes().capsule
            // The lens sits behind the chosen option (30 days, the middle one).
            func lens() -> CGRect? {
                let all = options.allElementsBoundByIndex.filter { $0.exists }.sorted { $0.frame.minX < $1.frame.minX }
                return (all.first { $0.isSelected } ?? (all.count == 3 ? all[1] : nil))?.frame
            }
            for _ in 0..<8 {
                guard let l = lens() else { break }
                let delta = cap.minY - l.midY
                if abs(delta) < 3 { break }
                let step = abs(delta) < 25 ? delta + (delta > 0 ? 40 : -40) : delta + (delta > 0 ? 10 : -10)
                let start = CGPoint(x: app.frame.midX * 0.6, y: step > 0 ? 260 : 660)
                at(start).press(forDuration: 0.1, thenDragTo: at(CGPoint(x: start.x, y: start.y + max(-400, min(400, step)))), withVelocity: .slow, thenHoldForDuration: 0.6)
                pause(1.2)
            }
            guard let l = lens(), abs(l.midY - cap.minY) < 4 else { XCTFail("the Range lens is not on the bar's edge: \(String(describing: lens())) bar \(cap)"); return nil }
            lensFrame = l
            let group = options.allElementsBoundByIndex.filter { $0.exists }.reduce(CGRect.null) { $0.union($1.frame) }
            print("TAB-PRESS lens \(l) options \(group) bar \(cap)")
            // The control's part over the bar, with a margin for a lens that grows; it stops 3 pt
            // short of the bar, whose own press look may reach past its edge.
            return CGRect(x: group.minX - 8, y: l.minY - 8, width: group.width + 16, height: cap.minY - 3 - (l.minY - 8))
        }
        for (id, d) in worst.sorted(by: { $0.key < $1.key }) {
            XCTAssertLessThan(d, pressedChange, "pressing \(id) showed Home's Range behind the bar pressed (\(String(format: "%.1f", d * 100))% of its visible part changed)")
        }
    }

    /// The elements lying on the bar, in tree order (the order a VoiceOver swipe takes), from one
    /// snapshot of the app.
    private func barTree(_ bar: CGRect) throws -> [String] {
        var out: [String] = []
        func walk(_ s: XCUIElementSnapshot) {
            if s.frame.width > 0, bar.contains(s.frame) {
                out.append("type \(s.elementType.rawValue) id '\(s.identifier)' label '\(s.label)' frame \(s.frame)")
            }
            for c in s.children { walk(c) }
        }
        walk(try app.snapshot())
        return out
    }

    /// The bar's touch margin is not something VoiceOver meets: an accessibility audit flags
    /// nothing lying on the bar, on Chats, Bots, Home and Settings. The hit-only capsule behind
    /// the bar's shapes read as an element with no description the size of the bar (1.5 (20)).
    func testTabBarAuditClean() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token, tab: "chats")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup'")).firstMatch.waitForExistence(timeout: 40), "no chat rows")
        pause(2)
        for tab in ["chats", "bots", "dashboard", "settings"] {
            if tab != "chats" { any("tab.\(tab)").tap(); pause(2) }
            // The bar's shapes and their touch margin, a little over. Down the Duo's strip: its
            // buttons' frames, the capsule's inset around them and the margin.
            let parts = ["tab.dashboard", "tab.chats", "tab.bots", "tab.settings", "chats.voice", "chats.new"].map { any($0) }.filter { $0.exists }
            let vertical = abs(any("tab.chats").frame.midX - any("tab.settings").frame.midX) < 2
            let bar: CGRect
            if vertical {
                bar = parts.dropFirst().reduce(parts[0].frame) { $0.union($1.frame) }.insetBy(dx: -16, dy: -16)
            } else {
                let (cap, mic, new) = barShapes()
                bar = cap.union(mic).union(new).insetBy(dx: -8, dy: -8)
            }
            print("TAB-BAR \(tab) \(bar) window \(app.frame.size)")
            for line in try barTree(bar) { print("TAB-TREE \(tab) \(line)") }
            var flagged: [String] = []
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .elementDetection]) { issue in
                guard let el = issue.element else { print("TAB-AUDIT \(tab) '\(issue.compactDescription)' no element"); return true }
                let line = "'\(issue.compactDescription)' type \(el.elementType.rawValue) id '\(el.identifier)' label '\(el.label)' frame \(el.frame)"
                print("TAB-AUDIT \(tab) \(line)")
                // On the bar: lying within it. A row running under the bar is wider than it.
                if bar.contains(el.frame) { flagged.append(line) }
                return true
            }
            XCTAssertTrue(flagged.isEmpty, "\(tab): the audit flags the bar: \(flagged)")
        }
    }
}
