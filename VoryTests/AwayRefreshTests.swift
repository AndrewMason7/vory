import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// #371: away with a turn running, the refreshes a long turn sets off are held back. Each of the
/// gateway's sessions.changed (one per flush, every 2 s of a long turn) fetched the list, wrote
/// the widget snapshot to the Keychain, reloaded the widgets and reloaded the chat list with its
/// Siri and Spotlight catalogs, on a main thread the system wants quiet in the background. Now
/// the snapshot runs once when the last turn ends and the list once after the return.
///
/// The snapshots are counted through this runtime's own callback; the list refresh by the
/// runtime's owed state (the notice goes to the shared centre, where tests running alongside
/// post it too, so its count can only be a lower bound).
@MainActor @Suite struct AwayRefreshTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func add() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
    }

    private func runtime() throws -> GatewayRuntime {
        let conn = GatewayConnection(name: "unit", gateway: try GatewayURL.normalize("https://127.0.0.1:1"), authMode: .sessionToken)
        return GatewayRuntime(connection: conn, store: ConnectionStore())
    }

    /// The gateway sends it with no session id; here it carries one no chat has, because this
    /// test's chat was never opened and its runtime id is still empty, and the runtime hands an
    /// event to the chat whose runtime id matches before it looks at its type.
    private func sessionsChanged() -> GatewayEvent {
        GatewayEvent(type: "sessions.changed", sessionID: "global", payload: .object([:]), seq: nil)
    }

    private func settle(until done: () -> Bool, seconds: Double = 5) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func awayDuringATurnTheRefreshesWaitForTheTurnsEndAndTheReturn() async throws {
        let rt = try runtime()
        let snapshots = Counter()
        rt.onSnapshotPublished = { _ in snapshots.add() }
        let chat = ChatSession(runtime: rt, storedID: nil, title: nil)
        rt.registry.add(chat)
        rt.isAway = true
        chat.isRunning = true
        for _ in 0..<5 { rt.handle(batch: [sessionsChanged()]) }
        try await Task.sleep(for: .milliseconds(600))
        #expect(snapshots.value == 0, "a snapshot was published away with the turn running")
        #expect(rt.owedSnapshot && rt.owedSessionsRefresh)
        #expect(rt.owedListRefresh, "the lists were refreshed away with the turn running")

        // The turn ends while away: the widgets get its end state, once; the lists still wait.
        chat.isRunning = false
        await settle { snapshots.value >= 1 }
        try await Task.sleep(for: .milliseconds(300))
        #expect(snapshots.value == 1)
        #expect(!rt.owedSnapshot && !rt.owedSessionsRefresh)
        #expect(rt.owedListRefresh)

        // Back: the lists are read once, after the return's animation.
        rt.isAway = false
        try await Task.sleep(for: .milliseconds(300))
        #expect(rt.owedListRefresh, "the lists were refreshed inside the return's animation")
        await settle { !rt.owedListRefresh }
        #expect(!rt.owedListRefresh, "the lists were not refreshed after the return")
        #expect(snapshots.value == 1)
    }

    @Test func inFrontEveryRefreshRunsAsBefore() async throws {
        let rt = try runtime()
        let snapshots = Counter(), lists = Counter()
        rt.onSnapshotPublished = { _ in snapshots.add() }
        let observer = NotificationCenter.default.addObserver(forName: .hermesSessionsChanged, object: nil, queue: nil) { _ in lists.add() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let chat = ChatSession(runtime: rt, storedID: nil, title: nil)
        rt.registry.add(chat)
        chat.isRunning = true
        await settle { snapshots.value >= 1 }
        for _ in 0..<3 { rt.handle(batch: [sessionsChanged()]) }
        await settle { snapshots.value >= 4 }
        #expect(snapshots.value == 4)
        #expect(lists.value >= 3, "a sessions.changed in front did not refresh the lists")
        #expect(!rt.owedListRefresh && !rt.owedSnapshot)
    }

    @Test func goingAwayAgainBeforeTheReturnSettlesOwesTheRefreshStill() async throws {
        let rt = try runtime()
        rt.isAway = true
        rt.handle(batch: [sessionsChanged()])
        #expect(rt.owedListRefresh)
        rt.isAway = false
        rt.isAway = true          // a glance at the app and away again, inside the 0.7 s
        try await Task.sleep(for: .milliseconds(1000))
        #expect(rt.owedListRefresh, "a return cut short paid the owed refresh while away")
        rt.isAway = false
        await settle { !rt.owedListRefresh }
        #expect(!rt.owedListRefresh)
    }
}
