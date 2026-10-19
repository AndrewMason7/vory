import XCTest

/// #449: a long chat, or a long Bot Chat, opened from the list, lands at its end without being thrown up the thread. The
/// thread used to be thrown to its top for a few frames as the history landed (a Bot Chat, about half its opens), or a few
/// screens up and back again (a long chat). Each open is cold: a fresh launch, the history fetched. Read from the app's
/// DEBUG probe (`-vory-coldopen-probe`, `ColdOpenProbe`): how the thread moved in the six seconds after the chat appeared.
///
/// Needs the mock with MOCK_CODING (a long coding chat as "Disk cleanup", and a long Bot Chat); skipped without it.
/// HERMES_E2E_CYCLES sets how many fresh launches (6 by default). The stalled case switches the mock's faults
/// (`/mock/fault`), so it needs the mock this suite was started with.
@MainActor
final class ColdOpenUITests: XCTestCase {
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    /// The probe's reading of the last open, from what was in sight: (title, items, moves of 80 pt or more, settle ms, the
    /// largest throw up in pt, when the thread was shown with its whole history, ms).
    private func reading(_ app: XCUIApplication) -> (title: String, items: Int, moves: Int, settle: Int, thrown: Int, shown: Int)? {
        let e = app.descendants(matching: .any).matching(identifier: "debug.coldopen").firstMatch
        guard e.waitForExistence(timeout: 5), let v = e.value as? String else { return nil }
        let f = v.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 6, let items = Int(f[1]), let moves = Int(f[2]), let settle = Int(f[3]), let thrown = Int(f[4]), let shown = Int(f[5]) else { return nil }
        return (f[0], items, moves, settle, thrown, shown)
    }

    func testAChatOpenedColdLandsWithoutBeingThrown() throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set")
        }
        continueAfterFailure = true
        let cycles = Int(e["HERMES_E2E_CYCLES"] ?? "") ?? 6
        let app = XCUIApplication(bundleIdentifier: e["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.vorantx.vory.demo")
        app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats",
                               "-vory-coldopen-probe"] + (e["HERMES_E2E_GEOMETRY"] == "1" ? ["-vory-geometry-log"] : [])
        // The clean opens' numbers (2026-10-19, 24 per kind on 27 and 28): a long chat at most 5 moves and about 0.6 s to settle,
        // a Bot Chat at most 4 and about 0.42 s. A throw was 6,000 pt (long chat) or the whole thread (Bot Chat, 20,000 pt).
        let most = ["long": 5, "botchat": 4]
        var settles: [String: [Int]] = [:]
        for c in 1...cycles {
            app.launch()
            let rows = ["long": app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Disk cleanup' AND NOT (identifier BEGINSWITH 'chat.')")).firstMatch,
                        "botchat": app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Bot Chat' AND NOT (identifier BEGINSWITH 'chat.')")).firstMatch]
            let back = app.buttons["chat.back"].firstMatch
            XCTAssertTrue(rows["long"]!.waitForExistence(timeout: 40), "no chat list")
            pause(2)
            for kind in ["long", "botchat"] {
                guard let row = rows[kind], row.waitForExistence(timeout: 5) else { XCTFail("no \(kind) row in cycle \(c)"); continue }
                row.tap()
                pause(6)
                guard let r = reading(app) else { XCTFail("no reading for \(kind) in cycle \(c)"); continue }
                print("COLD-OPEN \(kind) \(c): \(r.title), \(r.items) items, shown at \(r.shown) ms, \(r.moves) moves, settled at \(r.settle) ms, thrown \(r.thrown) pt")
                if r.items < 100 { throw XCTSkip("the chat is short (\(r.items) items): run the mock with MOCK_CODING") }
                // Out of sight while its history lands (#449), but not for long: shown within 1.2 s on the mock.
                XCTAssertTrue((0...1200).contains(r.shown), "\(kind) \(c): shown at \(r.shown) ms (-1: never in sight)")
                XCTAssertLessThanOrEqual(r.thrown, 100, "\(kind) \(c): thrown \(r.thrown) pt up the thread as it opened")
                XCTAssertLessThanOrEqual(r.moves, most[kind]!, "\(kind) \(c): \(r.moves) moves as it opened")
                XCTAssertLessThanOrEqual(r.settle, 1600, "\(kind) \(c): still moving at \(r.settle) ms")
                settles[kind, default: []].append(r.settle)
                if back.waitForExistence(timeout: 5) { back.tap() }
                pause(1.5)
            }
            app.terminate()
            pause(1)
        }
        for (kind, s) in settles where !s.isEmpty {
            let median = s.sorted()[s.count / 2]
            print("COLD-OPEN \(kind): median settle \(median) ms over \(s.count) opens")
            XCTAssertLessThanOrEqual(median, kind == "long" ? 800 : 550, "\(kind): median settle \(median) ms")
        }
    }

    /// The mock's faults (#423): `slow-resume&count=N` answers a chat's history N seconds late; `none` ends it.
    private func fault(_ mode: String, _ base: String) {
        let done = expectation(description: "fault \(mode)")
        URLSession.shared.dataTask(with: URL(string: "\(base)/mock/fault?mode=\(mode)")!) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
    }

    /// A history slow to come (`session.resume` answered 4 s late, REST and the socket up), in a chat whose stored rows are
    /// shorter than the screen (the Bot Chat: a few rows can be at no end, so only the cap shows them): its rows are shown
    /// after 1.5 s rather than nothing for as long as the history takes; when the history then lands, it lands out of sight
    /// and the thread comes back at its end, not thrown. (A chat whose stored rows fill the screen is shown at its end at once.)
    func testAStalledHistoryShowsTheStoredRowsThenLandsUnseen() throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set")
        }
        continueAfterFailure = true
        let app = XCUIApplication(bundleIdentifier: e["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.vorantx.vory.demo")
        app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats",
                               "-vory-coldopen-probe"] + (e["HERMES_E2E_GEOMETRY"] == "1" ? ["-vory-geometry-log"] : [])
        app.launch()
        defer { fault("none", url) }
        let botChat = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Bot Chat' AND NOT (identifier BEGINSWITH 'chat.')")).firstMatch
        XCTAssertTrue(botChat.waitForExistence(timeout: 40), "no chat list")
        pause(2)
        fault("slow-resume&count=4", url)
        botChat.tap()
        pause(2.2)
        guard let early = reading(app) else { XCTFail("no reading while the history is held up"); return }
        print("COLD-OPEN stalled, before the history: \(early.items) items, shown at \(early.shown) ms")
        if early.items >= 20 { throw XCTSkip("the chat opened with \(early.items) rows kept: not the stalled path") }
        XCTAssertTrue((1400...1800).contains(early.shown), "the stored rows were shown at \(early.shown) ms, not after 1.5 s")
        // The history lands when the slow answer comes, about 4 s after the open.
        var landed: (title: String, items: Int, moves: Int, settle: Int, thrown: Int, shown: Int)?
        for _ in 0..<25 {
            pause(2)
            if let r = reading(app), r.items >= 100 { landed = r; break }
        }
        guard landed != nil else { XCTFail("the history did not land within 50 s"); return }
        pause(3)
        guard let r = reading(app) else { XCTFail("no reading after the history"); return }
        print("COLD-OPEN stalled, after the history: \(r.items) items, shown at \(r.shown) ms, \(r.moves) moves, thrown \(r.thrown) pt")
        if r.items < 100 { throw XCTSkip("the chat is short (\(r.items) items): run the mock with MOCK_CODING") }
        XCTAssertGreaterThan(r.shown, early.shown, "the whole history was never in sight")
        XCTAssertLessThanOrEqual(r.thrown, 100, "thrown \(r.thrown) pt up the thread as the held-up history landed")
    }
}
