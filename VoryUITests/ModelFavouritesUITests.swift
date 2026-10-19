import XCTest

/// #401: favourite models and a searchable list of all of them. A tester with about a thousand models across several
/// providers dug through each provider's list to switch. "All Models…" in a model menu opens every model, searchable,
/// with a star on each; starred ones sit on top of the list and of the model menus, can be reordered and unpinned, and
/// one the gateway stops offering is shown as unavailable.
///
/// Against the mock with `--extra-models 1000` (600 under OpenRouter, 400 under Together, named
/// "<vendor>/model-NNNN"). Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set; HERMES_E2E_BUNDLE=
/// com.vorantx.vory.demo drives the demo copy.
@MainActor
final class ModelFavouritesUITests: XCTestCase {
    private var app: XCUIApplication!
    private var gatewayURL = ""

    // Two of the mock's long list, one under each big provider, and one more for the unavailable case.
    private let a = (id: "openrouter::cobalt/model-0042", model: "cobalt/model-0042", search: "model-0042")
    private let b = (id: "together::cobalt/model-0712", model: "cobalt/model-0712", search: "model-0712")
    private let c = (id: "openrouter::borealis/model-0001", model: "borealis/model-0001", search: "model-0001")

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private func launch(url: String, token: String) {
        gatewayURL = url
        let args = ["-companionPromptShown", "YES", "-launchTab", "chats", "-colorSchemePreference", "light"]
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop"] + args
        } else {
            app = XCUIApplication()
            app.launchArguments = args
        }
        app.launch()
        // A model an earlier run dropped from the mock is offered again.
        mock("/mock/drop-model?clear=1")
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: s); att.name = name; att.lifetime = .keepAlways; add(att)
        guard let folder = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"], !folder.isEmpty else { return }
        let d = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: d.appendingPathComponent("\(name).png"))
    }

    /// The mock's own test switch (`/mock/drop-model`): the gateway stops (or starts again) offering a model.
    private func mock(_ path: String) {
        guard let u = URL(string: gatewayURL + path) else { return }
        let done = expectation(description: path)
        URLSession.shared.dataTask(with: u) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
    }

    /// A fresh chat, its composer up.
    private func openChat() {
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()
        XCTAssertTrue(app.textViews["composer.text"].firstMatch.waitForExistence(timeout: 30))
        pause(2)
    }

    private func openChipMenu() {
        let chip = any("composer.modelChip")
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "no model chip")
        chip.tap()
    }

    private func menuItem(_ id: String, label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", id, label)).firstMatch
    }

    /// "All Models…" from the composer's model chip; how long until the list's rows are there.
    @discardableResult
    private func openList() -> TimeInterval {
        openChipMenu()
        let all = menuItem("models.all", label: "All Models")
        XCTAssertTrue(all.waitForExistence(timeout: 10), "no All Models… in the model menu")
        let start = Date()
        all.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'models.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the model list did not open with rows")
        return Date().timeIntervalSince(start)
    }

    private func search(_ text: String) -> TimeInterval {
        let field = app.searchFields.firstMatch
        if !field.exists { app.swipeDown(velocity: .slow); pause(0.5) }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field")
        field.tap()
        if let v = field.value as? String, !v.isEmpty, v != field.placeholderValue {
            field.buttons["Clear text"].firstMatch.tap()
        }
        let start = Date()
        field.typeText(text)
        let hit = app.descendants(matching: .any).matching(NSPredicate(format: "identifier ENDSWITH %@", text)).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 10), "no result for \(text)")
        return Date().timeIntervalSince(start)
    }

    /// The row's star: its own button where the tree lists it, else the row's trailing edge (the row is one element
    /// for VoiceOver).
    private func tapStar(_ rowID: String, starID: String) {
        let star = any(starID)
        if star.exists, star.isHittable { star.tap(); return }
        let row = any(rowID)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no row \(rowID)")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    }

    /// Out of the search, if it is active: the bar's Done is hidden while it is.
    private func leaveSearch() {
        guard app.keyboards.count > 0 || !any("models.done").isHittable else { return }
        let cancel = app.buttons.matching(NSPredicate(format: "label ==[c] 'cancel' OR label ==[c] 'close'")).allElementsBoundByIndex
            .first { $0.isHittable && $0.frame.minY > app.frame.height * 0.4 }
        cancel?.tap()
        pause(0.8)
    }

    private func closeList() {
        leaveSearch()
        let done = any("models.done")
        guard done.waitForExistence(timeout: 5) else {
            let buttons = app.buttons.allElementsBoundByIndex.map { "'\($0.label)' #\($0.identifier) \($0.frame)" }
            XCTFail("no Done on the model list; buttons: \(buttons.joined(separator: " | "))")
            return
        }
        done.tap()
        pause(0.8)
    }

    private func favouriteRows() -> [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'models.favrow.'")).allElementsBoundByIndex
    }

    /// Unstars whatever an earlier run left (the demo copy keeps its favourites between launches).
    private func clearFavourites() {
        for _ in 0..<8 {
            guard let row = favouriteRows().first, row.exists else { return }
            let id = String(row.identifier.dropFirst("models.favrow.".count))
            tapStar(row.identifier, starID: "models.star.\(id)")
            pause(0.6)
        }
    }

    // MARK: Tests

    func testTheListOfAThousandModelsOpensAndSearchesQuickly() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openChat()
        var opens: [TimeInterval] = [], typing: [TimeInterval] = [], menus: [TimeInterval] = []
        for i in 0..<3 {
            // The model menu itself, for scale.
            let m0 = Date(); openChipMenu()
            XCTAssertTrue(menuItem("models.all", label: "All Models").waitForExistence(timeout: 10))
            menus.append(Date().timeIntervalSince(m0))
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap(); pause(0.8)

            opens.append(openList())
            if i == 0 { shot("models-list-open") }
            typing.append(search([a.search, b.search, c.search][i]))
            if i == 0 { shot("models-list-search") }
            closeList()
        }
        func ms(_ t: [TimeInterval]) -> String { t.map { String(Int($0 * 1000)) }.joined(separator: ", ") }
        print("MODELS-TIMING menu open (ms): \(ms(menus))")
        print("MODELS-TIMING list open to first row (ms): \(ms(opens))")
        print("MODELS-TIMING typing 10 characters to the result (ms): \(ms(typing))")
        // Ceilings only: most of these numbers is XCUITest's own waiting (the model menu, unchanged, takes as long). The
        // app's own times are in its perf log (DEBUG, "models: …": the list drawn after the pick, each keystroke drawn).
        XCTAssertLessThan(opens.max() ?? 99, 6, "the list was slow to open: \(opens)")
        XCTAssertLessThan(typing.max() ?? 99, 8, "the search was slow: \(typing)")
    }

    func testAStarredModelIsOnTopOfTheListAndInTheModelMenu() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openChat()
        openList()
        clearFavourites()
        for m in [a, b] {
            _ = search(m.search)
            tapStar("models.row.\(m.id)", starID: "models.star.\(m.id)")
            pause(0.6)
        }
        // Back to the whole list: the two on top, in the order they were starred.
        app.searchFields.firstMatch.buttons["Clear text"].firstMatch.tap(); pause(0.8)
        let rows = favouriteRows()
        XCTAssertEqual(rows.map(\.identifier), ["models.favrow.\(a.id)", "models.favrow.\(b.id)"])
        XCTAssertTrue(rows.first?.label.contains("favourite") == true, "a favourite's row does not say so: \(rows.first?.label ?? "")")
        shot("models-favourites-on-top")
        closeList()

        // In the composer's model menu, first, and picking one switches the chat.
        openChipMenu()
        let item = menuItem("models.fav.\(b.id)", label: b.model)
        XCTAssertTrue(item.waitForExistence(timeout: 10), "the favourite is not in the model menu")
        shot("models-menu-favourites")
        item.tap()
        let chip = any("composer.modelChip")
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", b.model), evaluatedWith: chip)], timeout: 15)

        // Kept when the list opens again. (Across launches: FavouriteModelsTests. The demo copy adds its gateway afresh,
        // under a new id, at every launch, and favourites belong to a gateway.)
        openList()
        XCTAssertEqual(favouriteRows().map(\.identifier), ["models.favrow.\(a.id)", "models.favrow.\(b.id)"])
        clearFavourites()
        XCTAssertTrue(favouriteRows().isEmpty, "unstarring left favourites")
    }

    func testFavouritesReorderAndUnpin() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openChat()
        openList()
        clearFavourites()
        for m in [a, b, c] {
            _ = search(m.search)
            tapStar("models.row.\(m.id)", starID: "models.star.\(m.id)")
            pause(0.5)
        }
        app.searchFields.firstMatch.buttons["Clear text"].firstMatch.tap(); pause(0.8)
        // Out of the search (it keeps the bar, and Edit, away).
        leaveSearch()
        XCTAssertEqual(favouriteRows().map(\.identifier), ["models.favrow.\(a.id)", "models.favrow.\(b.id)", "models.favrow.\(c.id)"])

        // Edit, then the last one dragged to the top by its handle.
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit for the favourites")
        edit.tap(); pause(0.8)
        let handles = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Reorder'")).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(handles.count, 3, "no reorder handles")
        if handles.count >= 3 {
            handles[2].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: handles[0].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
            pause(1)
        }
        shot("models-favourites-reordered")
        app.buttons["Done"].firstMatch.tap(); pause(0.6)   // out of Edit
        XCTAssertEqual(favouriteRows().map(\.identifier), ["models.favrow.\(c.id)", "models.favrow.\(a.id)", "models.favrow.\(b.id)"])

        // Unpinned by a swipe.
        let first = any("models.favrow.\(c.id)")
        first.swipeLeft(); pause(0.6)
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no Delete on a swipe")
        delete.tap(); pause(0.8)
        XCTAssertEqual(favouriteRows().map(\.identifier), ["models.favrow.\(a.id)", "models.favrow.\(b.id)"])
        // Still in the providers' lists, unstarred.
        _ = search(c.search)
        XCTAssertTrue(any("models.row.\(c.id)").exists)
        XCTAssertFalse(any("models.row.\(c.id)").label.contains("favourite"))
        app.searchFields.firstMatch.buttons["Clear text"].firstMatch.tap(); pause(0.5)
        clearFavourites()
    }

    func testAFavouriteTheGatewayStopsOfferingIsShownUnavailable() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openChat()
        openList()
        clearFavourites()
        _ = search(c.search)
        tapStar("models.row.\(c.id)", starID: "models.star.\(c.id)")
        pause(0.5)
        app.searchFields.firstMatch.buttons["Clear text"].firstMatch.tap(); pause(0.5)
        leaveSearch()

        // The gateway drops it; pulling the list down asks for the list again.
        mock("/mock/drop-model?model=\(c.model)")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        pause(2.5)
        XCTAssertTrue(any("models.sheet").exists || any("models.done").exists, "the pull closed the list instead of refreshing it")
        let row = any("models.favrow.\(c.id)")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the dropped favourite left the list")
        XCTAssertTrue(row.label.contains("unavailable"), "the row does not say it is unavailable: \(row.label)")
        shot("models-list-unavailable")
        // Not in its provider's list any more.
        _ = search(a.search)
        XCTAssertFalse(any("models.row.\(c.id)").exists)
        app.searchFields.firstMatch.buttons["Clear text"].firstMatch.tap(); pause(0.5)
        closeList()

        // In the menu: still there, and cannot be picked.
        openChipMenu()
        let item = menuItem("models.fav.\(c.id)", label: c.model)
        XCTAssertTrue(item.waitForExistence(timeout: 10), "the dropped favourite left the model menu")
        XCTAssertFalse(item.isEnabled, "the dropped favourite can still be picked")
        shot("models-menu-unavailable")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap(); pause(0.8)

        openList()
        clearFavourites()
        XCTAssertTrue(favouriteRows().isEmpty)
        closeList()
        mock("/mock/drop-model?clear=1")
    }

    /// The other ways in: the chat's … menu (its Model submenu), and the bot card's Model row, where the list opens
    /// over the card (the chat under it cannot present while the card is up) and the card is still there after.
    func testAllModelsOpensFromTheChatMenuAndOverTheBotCard() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        openChat()

        app.buttons["chat.more"].firstMatch.tap()
        let modelItem = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Model: '")).firstMatch
        XCTAssertTrue(modelItem.waitForExistence(timeout: 10), "no Model in the chat's menu")
        modelItem.tap()
        let all = menuItem("models.all", label: "All Models")
        XCTAssertTrue(all.waitForExistence(timeout: 10), "no All Models… in the chat menu's Model list")
        all.tap()
        XCTAssertTrue(any("models.done").waitForExistence(timeout: 10), "the list did not open from the chat's menu")
        closeList()

        let pill = any("chat.titlePill")
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()
        XCTAssertTrue(any("profile.header").waitForExistence(timeout: 10), "no bot card")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model'")).allElementsBoundByIndex.first { $0.frame.minY > 150 }
        var modelRow = row
        for _ in 0..<6 where !(modelRow?.isHittable ?? false) {
            app.swipeUp(velocity: .slow); pause(0.6)
            modelRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model'")).allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 150 }
        }
        guard let modelRow, modelRow.isHittable else { XCTFail("no Model row on the bot card"); return }
        modelRow.tap()
        XCTAssertTrue(all.waitForExistence(timeout: 10), "no All Models… in the card's Model menu")
        all.tap()
        XCTAssertTrue(any("models.done").waitForExistence(timeout: 10), "the list did not open over the bot card")
        shot("models-list-over-card")
        closeList()
        XCTAssertTrue(any("profile.header").exists, "the bot card went with the list")
    }

    // MARK: The audit on the new list and the menu's new items

    func testTheListAndTheMenuPassTheAudit() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        launch(url: url, token: token)
        openChat()
        openList()
        clearFavourites()
        _ = search(a.search)
        tapStar("models.row.\(a.id)", starID: "models.star.\(a.id)")
        pause(0.5)
        app.searchFields.firstMatch.buttons["Clear text"].firstMatch.tap(); pause(0.5)
        leaveSearch()
        var flagged: [String] = []
        func audit(_ screen: String) {
            do {
                try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .elementDetection]) { issue in
                    let el = issue.element
                    let line = "\(screen): '\(issue.compactDescription)' id '\(el?.identifier ?? "")' label '\(el?.label.prefix(60) ?? "")' frame \(el?.frame ?? .zero)"
                    print("MODELS-AUDIT \(line)")
                    // Only what this change added: the list's rows, stars, search and Done, and the menu's items.
                    let id = el?.identifier ?? ""
                    if id.hasPrefix("models.") || el?.label.hasPrefix("Search models") == true { flagged.append(line) }
                    return true
                }
            } catch { flagged.append("\(screen): the audit failed: \(error)") }
        }
        audit("Models list")
        closeList()
        openChipMenu()
        XCTAssertTrue(menuItem("models.fav.\(a.id)", label: a.model).waitForExistence(timeout: 10))
        audit("Model menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap(); pause(0.8)
        openList()
        clearFavourites()
        XCTAssertTrue(flagged.isEmpty, "the audit flags the new parts: \(flagged)")
    }
}
