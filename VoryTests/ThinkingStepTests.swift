import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// #424: a step that only thought before it called a tool keeps its reasoning as a folded card in
/// its place, while the turn runs and after it (it went the moment its tool began), and the same
/// turn read back (the gateway's history, the cached copy) gives the same rows. Such a step is
/// never a reply: nothing that reads, speaks or copies replies takes it.
@MainActor @Suite struct ThinkingStepTests {
    static let prompt = "read the shards"
    static let answer = "Done: all 3 shards read, no errors since the last run."
    static func thought(_ i: Int) -> String {
        "Step \(i): the export's shard \(i) is next. I'll read its log before touching anything. "
    }

    private func chat() throws -> ChatSession {
        let conn = GatewayConnection(name: "unit", gateway: try GatewayURL.normalize("https://127.0.0.1:1"), authMode: .sessionToken)
        let rt = GatewayRuntime(connection: conn, store: ConnectionStore())
        return ChatSession(runtime: rt, storedID: nil, title: nil)
    }

    private func send(_ chat: ChatSession, _ type: String, _ payload: [String: JSONValue] = [:]) {
        chat.handle(event: GatewayEvent(type: type, sessionID: chat.runtimeID, payload: .object(payload)))
    }

    /// The mock's `steps 3` turn, event by event: each step's reasoning streamed word by word,
    /// its tool call, then the answer.
    private func liveTurn(_ c: ChatSession, steps n: Int = 3, answer: String? = answer) {
        send(c, "message.start")
        for i in 1...n {
            for word in Self.thought(i).split(separator: " ") { send(c, "reasoning.delta", ["text": .string(word + " ")]) }
            send(c, "tool.start", ["tool_id": .string("call_\(i)"), "name": "terminal", "context": .string("tail shard-\(i).log")])
            send(c, "tool.complete", ["tool_id": .string("call_\(i)"), "name": "terminal", "summary": "20 lines", "result_text": "shard ok"])
        }
        if let answer { send(c, "message.delta", ["text": .string(answer)]) }
        send(c, "message.complete", ["text": .string(answer ?? ""), "status": "complete"])
    }

    /// The same turn as `session.resume` lists it (text and reasoning, no tool calls) or, with
    /// `rest`, as the REST page stores it (each step marked as asking for a tool).
    private func history(steps n: Int = 3, rest: Bool = false, answer: Bool = true) -> [TranscriptMessage] {
        var rows = [TranscriptMessage(role: "user", text: Self.prompt, timestamp: 1, rowId: 1)]
        for i in 1...n {
            rows.append(TranscriptMessage(role: "assistant", text: "", timestamp: Double(i * 2), rowId: i * 2, reasoning: Self.thought(i),
                                          finishReason: rest ? "tool_calls" : nil, hasToolCalls: rest))
            rows.append(TranscriptMessage(role: "tool", text: rest ? "shard ok" : nil, timestamp: Double(i * 2 + 1), name: "terminal", context: "tail shard-\(i).log"))
        }
        if answer { rows.append(TranscriptMessage(role: "assistant", text: Self.answer, timestamp: 100, rowId: 100, finishReason: rest ? "stop" : nil)) }
        return rows
    }

    /// What a reader sees of a turn: cards, tools and replies, without ids, times or the prompt.
    private func shape(_ items: [TranscriptItem]) -> [String] {
        items.compactMap { item in
            switch item.kind {
            case .user: return nil
            case .assistant(let t, let r, let streaming):
                if item.isThinkingOnly { return "card: " + StreamAssembler.normalized(r ?? "") }
                return "reply: \(t) | \(r ?? "-")\(streaming ? " (streaming)" : "")"
            case .tool(let a): return "tool: " + a.name
            default: return "other"
            }
        }
    }

    private var expected: [String] {
        (1...3).flatMap { ["card: " + StreamAssembler.normalized(Self.thought($0)), "tool: terminal"] } + ["reply: \(Self.answer) | -"]
    }

    @Test func eachStepsReasoningStaysAsAFoldedCard() throws {
        let c = try chat()
        liveTurn(c)
        #expect(shape(c.items) == expected)
        // Each card is where its step was: before the tool it called.
        let cards = c.items.indices.filter { c.items[$0].isThinkingOnly }
        #expect(cards.count == 3)
        for i in cards { if case .tool = c.items[i + 1].kind {} else { Issue.record("card \(i) is not before its tool") } }
    }

    @Test func aCardKeepsItsRowWhenItsToolBegins() throws {
        // The streaming row becomes the card under the same id: an open card stays open and the
        // thread does not take a row out and put another in while the reader is on it.
        let c = try chat()
        send(c, "message.start")
        send(c, "reasoning.delta", ["text": .string(Self.thought(1))])
        let streamingID = try #require(c.items.last?.id)
        send(c, "tool.start", ["tool_id": "call_1", "name": "terminal"])
        let card = try #require(c.items.first { $0.isThinkingOnly })
        #expect(card.id == streamingID)
    }

    @Test func aStepWithNeitherWordsNorThinkingLeavesNoRow() throws {
        let c = try chat()
        send(c, "message.start")
        send(c, "thinking.delta", ["text": "(waiting for the model)"])
        send(c, "reasoning.delta", ["text": "  "])
        send(c, "tool.start", ["tool_id": "call_1", "name": "terminal"])
        #expect(shape(c.items) == ["tool: terminal"])
    }

    @Test func theTurnReadBackGivesTheSameRows() throws {
        let c = try chat()
        liveTurn(c)
        #expect(shape(TranscriptItem.fromHistory(history())) == expected)
        #expect(shape(TranscriptItem.fromHistory(history(rest: true))) == expected)
        // The cached copy, as a cold launch draws it before the gateway answers.
        let conn = UUID(), stored = "unit-424-\(UUID().uuidString)"
        defer { if let u = TranscriptCache.url(connection: conn, storedID: stored) { try? FileManager.default.removeItem(at: u) } }
        TranscriptCache.save(c.items, connection: conn, storedID: stored)
        TranscriptCache.flush()
        let cached = try #require(TranscriptCache.load(connection: conn, storedID: stored))
        #expect(shape(TranscriptItem.fromHistory(cached)) == expected)
    }

    @Test func midTurnTheFinishedStepsAreCardsAndTheStepUnderWayIsNot() {
        // A snapshot while the turn runs: the steps whose tools ran are cards; the last row,
        // thinking still under way, is the live reply's to show.
        var rows = history(answer: false)
        rows.append(TranscriptMessage(role: "assistant", text: "", timestamp: 50, rowId: 50, reasoning: "Step 4: still thinking"))
        let built = TranscriptItem.fromHistory(rows, running: true)
        #expect(built.filter { $0.isThinkingOnly }.count == 3)
        #expect(!shape(built).contains { $0.contains("Step 4") })
    }

    @Test func aSnapshotKeepsTheLiveCardsUnderTheirIDs() throws {
        let c = try chat()
        liveTurn(c)
        let live = c.items.filter { $0.isThinkingOnly }.map(\.id)
        let paired = ChatSession.keepingIDs(TranscriptItem.fromHistory(history()), from: c.items)
        #expect(paired.filter { $0.isThinkingOnly }.map { $0.id } == live)
    }

    @Test func stepsThatThinkTheSameWordsKeepTheirOwnIDs() throws {
        // A loop of steps that begin alike pair with the history's rows by their reasoning's start,
        // as every terminal call pairs by its name: in order, and never two rows with one id, live,
        // read back from the gateway, through a snapshot, or from the cache.
        let same = "Let me check the logs again before I touch anything. "
        let c = try chat()
        send(c, "message.start")
        for i in 1...3 {
            send(c, "reasoning.delta", ["text": .string(same)])
            send(c, "tool.start", ["tool_id": .string("call_\(i)"), "name": "terminal"])
            send(c, "tool.complete", ["tool_id": .string("call_\(i)"), "name": "terminal", "summary": "ok"])
        }
        send(c, "message.delta", ["text": .string(Self.answer)])
        send(c, "message.complete", ["text": .string(Self.answer), "status": "complete"])
        let live = c.items.filter { $0.isThinkingOnly }.map { $0.id }
        #expect(live.count == 3)
        #expect(Set(live).count == 3)

        var rows = [TranscriptMessage(role: "user", text: Self.prompt, timestamp: 1, rowId: 1)]
        for i in 1...3 {
            rows.append(TranscriptMessage(role: "assistant", text: "", timestamp: Double(i * 2), rowId: i * 2, reasoning: same))
            rows.append(TranscriptMessage(role: "tool", timestamp: Double(i * 2 + 1), name: "terminal"))
        }
        rows.append(TranscriptMessage(role: "assistant", text: Self.answer, timestamp: 100, rowId: 100))
        let built = TranscriptItem.fromHistory(rows)
        #expect(built.filter { $0.isThinkingOnly }.count == 3)
        #expect(Set(built.map { $0.id }).count == built.count)
        // Through a snapshot each live card keeps its own id, in order.
        let paired = ChatSession.keepingIDs(built, from: c.items)
        #expect(Set(paired.map { $0.id }).count == paired.count)
        #expect(paired.filter { $0.isThinkingOnly }.map { $0.id } == live)
        // And a second snapshot on top of the first changes nothing.
        let again = ChatSession.keepingIDs(TranscriptItem.fromHistory(rows), from: paired)
        #expect(again.map { $0.id } == paired.map { $0.id })

        let conn = UUID(), stored = "unit-424-\(UUID().uuidString)"
        defer { if let u = TranscriptCache.url(connection: conn, storedID: stored) { try? FileManager.default.removeItem(at: u) } }
        TranscriptCache.save(paired, connection: conn, storedID: stored)
        TranscriptCache.flush()
        let cached = TranscriptItem.fromHistory(try #require(TranscriptCache.load(connection: conn, storedID: stored)))
        #expect(cached.filter { $0.isThinkingOnly }.count == 3)
        #expect(Set(cached.map { $0.id }).count == cached.count)
        // The cached copy shown, then the gateway's history over it: the cards pair up again.
        let reloaded = ChatSession.keepingIDs(built, from: cached)
        #expect(Set(reloaded.map { $0.id }).count == reloaded.count)
        #expect(reloaded.filter { $0.isThinkingOnly }.map { $0.id } == cached.filter { $0.isThinkingOnly }.map { $0.id })
    }

    @Test func aStepThatOnlyThoughtIsNeverAReply() throws {
        let c = try chat()
        liveTurn(c)
        #expect(VoiceCoordinator.lastReply(in: c.items) == Self.answer)
        let built = TranscriptItem.fromHistory(history())
        #expect(TranscriptItem.reply(in: built, to: Self.prompt, sentAt: Date(timeIntervalSince1970: 0)) == Self.answer)
        // A turn stopped after its tools, with no answer: there is no reply to read or speak.
        let stopped = try chat()
        liveTurn(stopped, answer: nil)
        #expect(stopped.items.filter { $0.isThinkingOnly }.count == 3)
        #expect(VoiceCoordinator.lastReply(in: stopped.items) == nil)
        // The turn's numbers go on its reply; with none, not on a card.
        #expect(stopped.items.allSatisfy { $0.stats == nil })
        // Its row is tagged as reasoning, not as a reply.
        let card = try #require(stopped.items.first { $0.isThinkingOnly })
        #expect(TranscriptRowModel(item: card).kindTag == "reasoning")
    }

    @Test func theBotSitsBesideTheReplyNotACard() throws {
        let c = try chat()
        liveTurn(c)
        let rows = TranscriptRowModel.build(c.items)
        #expect(rows.filter { $0.item.isThinkingOnly }.allSatisfy { !$0.lastOfRun })
        #expect(rows.last?.lastOfRun == true)
        // Words before the steps, and no answer yet: the bot stays beside those words.
        let early = try chat()
        send(early, "message.start")
        send(early, "message.delta", ["text": "Reading the shards now."])
        send(early, "tool.start", ["tool_id": "call_0", "name": "terminal"])
        send(early, "reasoning.delta", ["text": .string(Self.thought(1))])
        send(early, "tool.start", ["tool_id": "call_1", "name": "terminal"])
        let built = TranscriptRowModel.build(early.items)
        #expect(built.first { if case .assistant(let t, _, _) = $0.item.kind { return !t.isEmpty }; return false }?.lastOfRun == true)
    }

    @Test func aCachedCardIsNeverTakenForTheAnswer() throws {
        // The card is the cache's last row (the turn was stopped there). Read back, an empty
        // assistant row with reasoning at the end of a finished chat is a promoted answer, unless
        // it says it asked for a tool, as the cache marks it.
        let c = try chat()
        send(c, "message.start")
        send(c, "reasoning.delta", ["text": .string(Self.thought(1))])
        send(c, "tool.start", ["tool_id": "call_1", "name": "terminal"])
        let conn = UUID(), stored = "unit-424-\(UUID().uuidString)"
        defer { if let u = TranscriptCache.url(connection: conn, storedID: stored) { try? FileManager.default.removeItem(at: u) } }
        TranscriptCache.save(c.items.filter { $0.isThinkingOnly }, connection: conn, storedID: stored)
        TranscriptCache.flush()
        let cached = try #require(TranscriptCache.load(connection: conn, storedID: stored))
        #expect(TranscriptItem.fromHistory(cached).allSatisfy { $0.isThinkingOnly })
        // Previews and summaries read messages: the card has no words for them.
        #expect(TranscriptItem.withPromotedAnswers(cached).allSatisfy { ($0.text ?? "").isEmpty })
    }
}
