import Foundation
import Observation
import Testing
@testable import Vory
@testable import VoryCore

/// #371: while the app is away, a chat's views are left out of its changes and told once on the
/// way back. A long turn in the background re-ran the thread's views with every event (a third
/// to half of a core) and drew its long reply in full at the end (30 MB kept while suspended).
/// The values stay current for everything that reads them; only observation waits. A hands-free
/// session, which follows the chat through observation with the app away, keeps it live.
@MainActor @Suite struct AwayQuietTests {
    final class Fired: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func fire() { lock.withLock { n += 1 } }
        var count: Int { lock.withLock { n } }
    }

    @MainActor final class Surface: TurnActivityReporting {
        private(set) var started = 0
        private(set) var ended: [String] = []
        func start(for chat: ChatSession) { started += 1 }
        func update(for chat: ChatSession, attention: Bool, detail: String?) {}
        func end(for chat: ChatSession, phase: String) { ended.append(phase) }
    }

    private func chat(surface: Surface? = nil) throws -> ChatSession {
        let conn = GatewayConnection(name: "unit", gateway: try GatewayURL.normalize("https://127.0.0.1:1"), authMode: .sessionToken)
        let rt = GatewayRuntime(connection: conn, store: ConnectionStore())
        if let surface { rt.activityReporterFactory = { surface } }
        let c = ChatSession(runtime: rt, storedID: nil, title: nil)
        rt.registry.add(c)
        return c
    }

    private func event(_ type: String, _ payload: [String: JSONValue] = [:]) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "s1", payload: .object(payload), seq: nil)
    }

    /// What a thread's views read: told on the first change to any of them.
    private func watch(_ c: ChatSession, _ fired: Fired) {
        withObservationTracking {
            _ = c.items
            _ = c.isRunning
            _ = c.statusLine
            _ = c.currentToolName
            _ = c.usage
            _ = c.cards
        } onChange: { fired.fire() }
    }

    /// A turn with a tool call and a reply, as the gateway sends it.
    private func turn(_ c: ChatSession) {
        c.handle(event: event("message.start"))
        c.handle(event: event("tool.start", ["tool_id": "t1", "name": "terminal", "context": "df -h"]))
        c.handle(event: event("tool.complete", ["tool_id": "t1", "name": "terminal", "summary": "41% used", "result_text": "/dev/sda1 41%"]))
        c.handle(event: event("message.delta", ["text": "All good."]))
        c.handle(event: event("message.complete", ["text": "All good.", "status": "complete"]))
    }

    @Test func awayTheViewsHearNothingUntilTheReturnAndTheValuesStayCurrent() throws {
        let c = try chat()
        c.runtime.isAway = true
        let fired = Fired()
        watch(c, fired)
        turn(c)
        #expect(fired.count == 0, "a view was told of a change while the app was away")
        // Current for whatever reads them directly (notifications, the cache, the Live Activity).
        #expect(c.items.contains { if case .tool = $0.kind { return true }; return false })
        #expect(c.items.contains { if case .assistant(let t, _, false) = $0.kind { return t == "All good." }; return false })
        #expect(c.isRunning == false)
        c.runtime.isAway = false
        #expect(fired.count == 1, "the views were not told on the way back")
    }

    @Test func inFrontEveryChangeIsToldAndAnEqualWriteIsNotAsTheMacroDoes() throws {
        let c = try chat()
        c.statusLine = "Running terminal…"
        let same = Fired()
        withObservationTracking { _ = c.statusLine } onChange: { same.fire() }
        c.statusLine = "Running terminal…"
        #expect(same.count == 0, "an equal write told the views (the macro skips it)")
        c.statusLine = "Running search…"
        #expect(same.count == 1)

        let rows = Fired()
        withObservationTracking { _ = c.items } onChange: { rows.fire() }
        c.handle(event: event("message.start"))
        #expect(rows.count == 1, "a row in front was not told")
    }

    @Test func aHandsFreeSessionKeepsTheChatLiveAndHearsWhatWasHeldBackAtOnce() throws {
        let c = try chat()
        c.runtime.isAway = true
        let held = Fired()
        watch(c, held)
        c.handle(event: event("message.start"))
        #expect(held.count == 0)
        // Voice starts with the app away (Siri): it is told now what changed.
        c.keepsObserversLive = true
        #expect(held.count == 1, "what was held back was not told when voice started")
        // And live from then on.
        let live = Fired()
        withObservationTracking { _ = c.isRunning; _ = c.cards.count } onChange: { live.fire() }
        c.handle(event: event("message.complete", ["text": "Done.", "status": "complete"]))
        #expect(live.count == 1, "a hands-free session did not hear the turn end while away")
        c.keepsObserversLive = false
        c.runtime.isAway = false
    }

    @Test func aTurnEndingAwayStillEndsItsLiveActivityAndLeavesTheRuntimeIdle() async throws {
        let surface = Surface()
        let c = try chat(surface: surface)
        c.runtime.isAway = true
        turn(c)
        #expect(surface.ended == ["done"], "the Live Activity's turn did not end while away")
        // AwayWatch lets the background time go when no chat runs: it reads the live value.
        #expect(!c.runtime.chats.contains { $0.isRunning })
        c.runtime.isAway = false
    }

    @Test func goingAwayAgainBeforeTheReturnSettlesStillTellsOnce() throws {
        let c = try chat()
        c.runtime.isAway = true
        let fired = Fired()
        watch(c, fired)
        c.handle(event: event("message.start"))
        c.runtime.isAway = false
        #expect(fired.count == 1)
        let again = Fired()
        watch(c, again)
        c.runtime.isAway = true
        c.handle(event: event("message.complete", ["text": "Done.", "status": "complete"]))
        #expect(again.count == 0)
        c.runtime.isAway = false
        #expect(again.count == 1)
    }
}
