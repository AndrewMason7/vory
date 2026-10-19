#if os(iOS)
import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// #387: the iPhone's turn surface passed on to the Watch. The relay is a pure decorator: every call reaches the Live
/// Activity (the inner reporter) unchanged and in order, and only a turn starting or ending and its cards changing tell
/// the Watch. WatchSync follows a chat for a Watch for ten minutes from its last request.
@MainActor
@Suite(.serialized)
struct WatchTurnRelayTests {
    enum Call: Equatable {
        case start(String), update(String, Bool, String?), end(String, String), voiceMode(String, String?), showCards(String)
    }

    final class Recorder: TurnActivityReporting {
        var calls: [Call] = []
        func start(for chat: ChatSession) { calls.append(.start(chat.storedID)) }
        func update(for chat: ChatSession, attention: Bool, detail: String?) { calls.append(.update(chat.storedID, attention, detail)) }
        func end(for chat: ChatSession, phase: String) { calls.append(.end(chat.storedID, phase)) }
        func voiceMode(for chat: ChatSession, line: String?) { calls.append(.voiceMode(chat.storedID, line)) }
        func showCards(for chat: ChatSession) { calls.append(.showCards(chat.storedID)) }
    }

    private func chat(_ id: String) throws -> ChatSession {
        let conn = GatewayConnection(name: "unit", gateway: try GatewayURL.normalize("https://127.0.0.1:1"), authMode: .sessionToken)
        return ChatSession(runtime: GatewayRuntime(connection: conn, store: ConnectionStore()), storedID: id, title: nil)
    }

    @Test func everyCallReachesTheInnerReporterInOrderWithTheSameValues() throws {
        let inner = Recorder()
        var told: [(String, WatchFeedRules.TurnCall)] = []
        let relay = WatchTurnRelay(inner: inner) { chat, call in told.append((chat.storedID, call)) }
        let a = try chat("a"), b = try chat("b")
        relay.start(for: a)
        relay.update(for: a, attention: false, detail: "Running terminal")
        relay.update(for: b, attention: true, detail: nil)
        relay.voiceMode(for: a, line: "Listening…")
        relay.showCards(for: b)
        relay.voiceMode(for: a, line: nil)
        relay.end(for: a, phase: "done")
        relay.end(for: b, phase: "error")
        #expect(inner.calls == [.start("a"), .update("a", false, "Running terminal"), .update("b", true, nil), .voiceMode("a", "Listening…"),
                                .showCards("b"), .voiceMode("a", nil), .end("a", "done"), .end("b", "error")])
        // The Watch hears of a turn starting or ending and of the cards changing, nothing else.
        #expect(told.map(\.0) == ["a", "b", "a", "b"])
        #expect(told.map(\.1) == [.start, .showCards, .end, .end])
    }

    @Test func theConvenienceUpdateReachesTheInnerReporterWithNoDetail() throws {
        let inner = Recorder()
        let relay = WatchTurnRelay(inner: inner) { _, _ in }
        relay.update(for: try chat("c"), attention: true)
        #expect(inner.calls == [.update("c", true, nil)])
    }

    @Test func aChatIsFollowedForTenMinutesFromTheWatchsLastRequestAndUntilItLeaves() {
        let sync = WatchSync.shared
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        let id = "follow-\(UUID().uuidString)"
        #expect(!sync.isFollowed(id, now: t0))
        sync.follow(id, now: t0)
        #expect(sync.isFollowed(id, now: t0.addingTimeInterval(599)))
        #expect(!sync.isFollowed(id, now: t0.addingTimeInterval(601)))
        sync.follow(id, now: t0.addingTimeInterval(590))
        #expect(sync.isFollowed(id, now: t0.addingTimeInterval(1_100)))
        sync.follow(id, on: false, now: t0.addingTimeInterval(600))
        #expect(!sync.isFollowed(id, now: t0.addingTimeInterval(601)))
    }
}
#endif
