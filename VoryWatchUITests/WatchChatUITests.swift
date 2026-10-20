import XCTest

/// The chat screen on its feed (#387 range B), at every size and mode the harness runs. Unpaired, the Watch reads the
/// mock on its own socket. A chat from the list opens at its end; a turn started on the gateway after that first read
/// (the mock's /mock/start-turn) brings an approval card, answered with the names the iPhone uses (#36).
final class WatchChatUITests: WatchUITestCase {
    /// The export chat open, past its first read.
    private func openExportChat() throws {
        try launch()
        let row = app.staticTexts["Rewrite the nightly export job"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 40), "no chat list")
        sleep(1)
        row.tap()
        XCTAssertTrue(app.textFields["Message"].firstMatch.waitForExistence(timeout: 20), "no message bar in the chat")
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "export")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 20), "no rows in the chat")
        sleep(2)
    }

    /// A turn in the open chat, as if its prompt had been sent from elsewhere.
    private func startTurn(_ prompt: String) async throws {
        let base = ProcessInfo.processInfo.environment["HERMES_E2E_URL"] ?? ""
        var c = try XCTUnwrap(URLComponents(string: base + "/mock/start-turn"))
        c.queryItems = [URLQueryItem(name: "session", value: "nightly export"), URLQueryItem(name: "prompt", value: prompt)]
        let (_, response) = try await URLSession.shared.data(from: try XCTUnwrap(c.url))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "the mock did not start the turn")
    }

    func testAChatOpensAtItsEnd() throws {
        try openExportChat()
        mark("chat open")
        shot("chat")
    }

    func testAnApprovalArrivesWithTheNamesTheIPhoneUses() async throws {
        try openExportChat()
        try await startTurn("morph")
        let allow = app.buttons["Allow once"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 30), "no approval card arrived")
        XCTAssertTrue(app.buttons["Deny"].firstMatch.exists, "the card has no Deny")
        sleep(1)
        mark("card arrived")
        shot("chat-card")
        allow.tap()
        XCTAssertTrue(allow.waitForNonExistence(timeout: 20), "Allow once did not answer the card")
        sleep(2)
        shot("chat-card-answered")
    }
}
