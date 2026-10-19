import Foundation
import Testing
@testable import VoryCore

/// #387: the Watch chat's rules. Which rows the Watch shows, when it reads a chat (never at rest), which arrivals it
/// announces (nothing on a first read, a wrist-raise read of rows already seen, or a switch of path), how long the iPhone
/// follows a chat for it, which turn calls the iPhone passes on, and the cards on the phone path.
@Suite struct WatchFeedRulesTests {
    private func user(_ id: String, _ t: String = "hi") -> TranscriptItem { TranscriptItem(id: id, kind: .user(text: t, attachments: [])) }
    private func reply(_ id: String, _ t: String = "done", streaming: Bool = false) -> TranscriptItem {
        TranscriptItem(id: id, kind: .assistant(text: t, reasoning: nil, streaming: streaming))
    }
    private func tool(_ id: String, _ name: String, _ status: ToolActivity.Status = .done) -> TranscriptItem {
        TranscriptItem(id: id, kind: .tool(ToolActivity(id: id, name: name, status: status)))
    }

    // MARK: Rows

    @Test func aReplyStillBeingWrittenAndAThinkingOnlyStepAreNotShown() {
        let thinking = TranscriptItem(id: "t", kind: .assistant(text: "", reasoning: "weighing it", streaming: false))
        let rows = [user("u"), thinking, tool("a", "terminal"), reply("r1"), reply("r2", streaming: true)]
        #expect(WatchFeedRules.settled(rows).map(\.id) == ["u", "a", "r1"])
    }

    @Test func thisTurnsStepsAreTheToolsAfterTheLastMessageOfYours() {
        let rows = [user("u1"), tool("a", "read_file"), reply("r1"), user("u2"), tool("b", "terminal"), tool("c", "web_search", .running)]
        #expect(WatchFeedRules.turnTools(rows).map(\.name) == ["terminal", "web_search"])
        #expect(WatchFeedRules.turnTools([tool("x", "terminal")]).map(\.name) == ["terminal"])
    }

    // MARK: When the Watch reads a chat

    @Test func onlyThePhonePathPollsAndOnlyWhileATurnRuns() {
        #expect(WatchFeedRules.pollInterval(route: .throughPhone, working: true) == 2)
        #expect(WatchFeedRules.pollInterval(route: .throughPhone, working: false) == nil)
        #expect(WatchFeedRules.pollInterval(route: .live, working: true) == nil)
        #expect(WatchFeedRules.pollInterval(route: .live, working: false) == nil)
        #expect(WatchFeedRules.pollInterval(route: .offline, working: true) == nil)
    }

    @Test func comingForwardAndThePhoneComingBackReadAChatOnThePhonePath() {
        #expect(WatchFeedRules.refreshes(.sceneActive, route: .throughPhone))
        #expect(WatchFeedRules.refreshes(.phoneReachable, route: .throughPhone))
        #expect(WatchFeedRules.refreshes(.chatChanged, route: .throughPhone))
        #expect(WatchFeedRules.refreshes(.sceneActive, route: .offline))
        #expect(WatchFeedRules.refreshes(.phoneReachable, route: .offline))
    }

    @Test func theLivePathIgnoresWhatOnlyThePhonePathNeeds() {
        #expect(WatchFeedRules.refreshes(.sceneActive, route: .live))
        #expect(WatchFeedRules.refreshes(.liveChanged, route: .live))
        #expect(!WatchFeedRules.refreshes(.chatChanged, route: .live))
        #expect(!WatchFeedRules.refreshes(.poll, route: .live))
        #expect(!WatchFeedRules.refreshes(.phoneReachable, route: .live))
        #expect(!WatchFeedRules.refreshes(.poll, route: .offline))
    }

    // MARK: Arrivals

    @Test func aFirstReadAnnouncesNothing() {
        var gate = WatchFeedEventGate()
        #expect(gate.arrivals(items: [user("u"), reply("r")], cardIDs: ["c1"]).isEmpty)
    }

    @Test func aNewReplyIsAnnouncedOnceAndAReadOfRowsAlreadySeenIsQuiet() {
        var gate = WatchFeedEventGate()
        _ = gate.arrivals(items: [user("u")], cardIDs: [])
        #expect(gate.arrivals(items: [user("u"), reply("r")], cardIDs: []) == [.replyArrived(itemID: "r")])
        // A wrist raise reads the chat again: the same rows say nothing.
        #expect(gate.arrivals(items: [user("u"), reply("r")], cardIDs: []).isEmpty)
    }

    @Test func aReplyIsAnnouncedWhenItIsDoneNotWhileItIsWritten() {
        var gate = WatchFeedEventGate()
        _ = gate.arrivals(items: WatchFeedRules.settled([user("u")]), cardIDs: [])
        #expect(gate.arrivals(items: WatchFeedRules.settled([user("u"), reply("r", streaming: true)]), cardIDs: []).isEmpty)
        #expect(gate.arrivals(items: WatchFeedRules.settled([user("u"), reply("r")]), cardIDs: []) == [.replyArrived(itemID: "r")])
    }

    @Test func aSwitchOfPathOnlyLearnsWhatIsThere() {
        var gate = WatchFeedEventGate()
        _ = gate.arrivals(items: [user("live-u"), reply("live-r")], cardIDs: [])
        // The phone path's rows carry other ids for the same messages.
        gate.reseed()
        #expect(gate.arrivals(items: [user("hist-u"), reply("hist-r")], cardIDs: ["c1"]).isEmpty)
        #expect(gate.arrivals(items: [user("hist-u"), reply("hist-r"), reply("hist-r2")], cardIDs: ["c1"]) == [.replyArrived(itemID: "hist-r2")])
    }

    @Test func aCardAndAFailedTurnAreAnnounced() {
        var gate = WatchFeedEventGate()
        _ = gate.arrivals(items: [user("u")], cardIDs: [])
        #expect(gate.arrivals(items: [user("u")], cardIDs: ["c1"]) == [.cardArrived(cardID: "c1")])
        let failed = TranscriptItem(id: "e", kind: .error(text: "Your request was not processed"))
        #expect(gate.arrivals(items: [user("u"), failed], cardIDs: ["c1"]) == [.turnFailed(itemID: "e")])
        let interrupted = reply("i", "Operation interrupted.")
        #expect(gate.arrivals(items: [user("u"), failed, interrupted], cardIDs: ["c1"]) == [.turnFailed(itemID: "i")])
    }

    @Test func oneReadWithSeveralArrivalsAnnouncesTheCardFirstThenAFailureThenTheNewestReply() {
        #expect(WatchFeedEventGate.strongest([.replyArrived(itemID: "a"), .cardArrived(cardID: "c"), .turnFailed(itemID: "e")]) == .cardArrived(cardID: "c"))
        #expect(WatchFeedEventGate.strongest([.replyArrived(itemID: "a"), .turnFailed(itemID: "e")]) == .turnFailed(itemID: "e"))
        #expect(WatchFeedEventGate.strongest([.replyArrived(itemID: "a"), .replyArrived(itemID: "b")]) == .replyArrived(itemID: "b"))
        #expect(WatchFeedEventGate.strongest([]) == nil)
    }

    // MARK: The iPhone's follow

    @Test func theFollowLastsTenMinutesFromTheLastRequestAndEndsWhenTheWatchLeaves() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var follow = WatchFollow()
        #expect(!follow.isActive(now: t0))
        follow.renew(now: t0)
        #expect(follow.isActive(now: t0.addingTimeInterval(599)))
        #expect(!follow.isActive(now: t0.addingTimeInterval(600)))
        // Each request renews it.
        follow.renew(now: t0.addingTimeInterval(500))
        #expect(follow.isActive(now: t0.addingTimeInterval(1_000)))
        follow.end()
        #expect(!follow.isActive(now: t0.addingTimeInterval(501)))
    }

    @Test func theIPhonePassesOnATurnStartingOrEndingAndItsCardsNotEveryUpdate() {
        #expect(WatchFeedRules.tellsWatch(.start))
        #expect(WatchFeedRules.tellsWatch(.end))
        #expect(WatchFeedRules.tellsWatch(.showCards))
        #expect(!WatchFeedRules.tellsWatch(.update))
        #expect(!WatchFeedRules.tellsWatch(.voiceMode))
    }

    // MARK: Problems and cards

    @Test func aFailureReadsAsItsKind() {
        #expect(WatchFeedProblem.from("Your request was not processed.").kind == .notProcessed)
        #expect(WatchFeedProblem.from("Your iPhone is not reachable.", phoneAway: true).kind == .phoneAway)
        #expect(WatchFeedProblem.from("could not open the chat").kind == .sendFailed)
    }

    @Test func anApprovalCrossesToTheWatchWhole() throws {
        let params: JSONValue = ["request_id": "req-1", "session_id": "s1", "command": "rm -rf build", "description": "Delete the build folder",
                                 "choices": ["once", "deny"], "pattern_key": "rm -rf", "tool_name": "terminal"]
        let card = PendingCard(id: "card-1", method: "approval", params: params)
        let message = WatchFeedRules.cardMessage(card)
        #expect(message["text"] as? String == "Delete the build folder")
        #expect(message["request"] as? String == "req-1")
        #expect(message["choices"] as? [String] == ["once", "deny"])
        #expect(message["scope"] as? String == "commands matching “rm -rf”")
        let back = try #require(WatchFeedRules.cards(from: [message]).first)
        #expect(back.id == "card-1")
        #expect(back.approval == card.approval)
        #expect(back.isNamed(by: "req-1"))
    }

    @Test func anOlderPhonesCardIsRebuiltFromItsWords() throws {
        let approval = try #require(WatchFeedRules.cards(from: [["id": "c", "method": "approval", "text": "Run tests", "request": "r9", "choices": ["once", "deny"]]]).first)
        #expect(approval.approval?.requestId == "r9")
        #expect(approval.approval?.description == "Run tests")
        #expect(approval.approval?.offeredChoices == ["once", "deny"])
        let question = try #require(WatchFeedRules.cards(from: [["id": "q", "method": "clarify", "text": "Which branch?"]]).first)
        #expect(question.clarify?.question == "Which branch?")
        #expect(WatchFeedRules.cards(from: [["method": "approval"]]).isEmpty)
    }
}
