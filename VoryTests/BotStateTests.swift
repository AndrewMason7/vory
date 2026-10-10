import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// What a chat's bot is doing, as a pose (`ChatSession.botState`), written down as it is before
/// the 1.5 bot motion (#304) so the port changes it on purpose, not by accident.
@MainActor @Suite struct BotStateTests {
    private func chat() throws -> ChatSession {
        let conn = GatewayConnection(name: "unit", gateway: try GatewayURL.normalize("https://127.0.0.1:1"), authMode: .sessionToken)
        let rt = GatewayRuntime(connection: conn, store: ConnectionStore())
        return ChatSession(runtime: rt, storedID: "s1", title: nil)
    }
    private func running(_ status: String?) throws -> ChatSession {
        let c = try chat()
        c.isRunning = true
        c.statusLine = status
        return c
    }

    @Test func idleWhenNothingRuns() throws {
        #expect(try chat().botState == .idle)
    }

    @Test func aWaitingCardIsTheAskBeforeAnythingElse() throws {
        let c = try running("Writing…")
        c.cards = [PendingCard(id: "a1", method: "approval", params: .object([:]))]
        #expect(c.botState == .awaitingApproval)
    }

    @Test func aFailedOpenIsTheError() throws {
        let c = try chat()
        c.resumeError = "gone"
        #expect(c.botState == .error)
        c.items = [TranscriptItem(id: "m", kind: .user(text: "hi", attachments: []))]
        #expect(c.botState == .idle, "an open chat with history keeps its thread; the error only stands in for an empty one")
    }

    @Test func theReattachBannerReadsAsReconnecting() throws {
        let c = try chat()
        c.banner = "Reconnected, but the chat could not be re-attached: slow"
        #expect(c.botState == .reconnecting)
    }

    @Test func theStatusLineChoosesThinkingToolsOrWorking() throws {
        #expect(try running(nil).botState == .thinking)
        #expect(try running("Thinking…").botState == .thinking)
        #expect(try running("Sending…").botState == .thinking)
        #expect(try running("Queued on the gateway").botState == .thinking)
        #expect(try running("Running Web Search…").botState == .usingTool)
        #expect(try running("Preparing tool…").botState == .usingTool)
        #expect(try running("Writing…").botState == .streaming, "writing is the bubbles (1.5)")
        #expect(try running("Any other line").botState == .working)
    }

    @Test func aSearchToolIsTheLensAndAnyOtherTheToolbox() throws {
        let c = try running("Running Web Search…")
        c.currentToolName = "web_search"
        #expect(c.botState == .searching)
        c.currentToolName = "terminal"
        #expect(c.botState == .usingTool)
        c.currentToolName = nil
        #expect(c.botState == .usingTool)
        for n in ["search_files", "grep", "glob", "browser", "web", "find"] { #expect(ChatSession.isSearchTool(n), "\(n) should be a search") }
        for n in ["terminal", "read_file", "write_file", "patch", "kanban"] { #expect(!ChatSession.isSearchTool(n), "\(n) is not a search") }
    }
}

/// A finished turn is recorded for the chat it ended in as well as for the bot (1.5): the face
/// that stands for that chat spins; the bot's other faces do not.
@MainActor @Suite struct BotFinishKeyingTests {
    @Test func aFinishIsKeyedByTheSessionAndTheBot() {
        let a = BotAmbient()
        a.turnFinished(profile: "work", session: "s-1")
        #expect(a.finishedSessions["s-1"] != nil)
        #expect(a.finished["work"] != nil)
        #expect(a.finishedSessions["s-2"] == nil, "another chat of the same bot has no finish")
        a.turnFinished(profile: "mascot")
        #expect(a.finished["mascot"] != nil && a.finishedSessions.count == 1)
    }
}

/// The pose a state asks for (`BotFace.motion`) and the widgets' still pose, as they are today.
/// Serialized: one case sets the shared motion style and the others read it.
@Suite(.serialized) struct BotMotionTodayTests {
    let spec = BotLookSpec(shape: "blob", eyes: "classic", hex: "#3B7BFF")

    @Test func idleAsksForNothing() {
        let m = BotFace.motion(time: 12.3, seed: 5, spec: spec, state: .idle, since: 3)
        #expect(m == BotFace.Motion())
    }

    @Test func thinkingSettlesIntoThePebbleWithASquint() {
        let m = BotFace.motion(time: 10, seed: 2, spec: spec, state: .thinking, since: 2)
        #expect(m.morphTarget == .pebble)
        #expect(m.morph == 1)
        #expect(m.eyeOpen == 0.42)
        #expect(m.blinkPeriod == 2.8)
    }

    @Test func aToolGrowsTheStemAndLooksDown() {
        let m = BotFace.motion(time: 10, seed: 2, spec: spec, state: .usingTool, since: 2)
        #expect(m.morphTarget == .stem)
        #expect(m.morph == 1)
        #expect(m.eyeX == 0.8 && m.eyeY == 0.6)
        #expect(m.freezeGlance)
    }

    @Test func theAskIsTheExclamationWithTheEyesGone() {
        let m = BotFace.motion(time: 10, seed: 2, spec: spec, state: .awaitingApproval, since: 2)
        #expect(m.morphTarget == .exclamation)
        #expect(m.morph == 1)
        #expect(m.eyeOpacity == 0)
        #expect(abs(m.roll) > 0.1)
    }

    @Test func errorDimsAndShutsTheEyes() {
        let m = BotFace.motion(time: 10, seed: 2, spec: spec, state: .error, since: 2)
        #expect(m.dim == 1)
        #expect(m.eyeOpen == 0.08)
        #expect(m.eyeY == 1)
    }

    @Test func reconnectingSwingsTheEyes() {
        let a = BotFace.motion(time: 0.55, seed: 2, spec: spec, state: .reconnecting, since: 2)
        let b = BotFace.motion(time: 1.65, seed: 2, spec: spec, state: .reconnecting, since: 2)
        #expect(a.eyeX > 1 && b.eyeX < -1)
        #expect(a.yaw == 0 && a.morph == 0)
    }

    @Test func streamingSquintsAndLightsTheRim() {
        let m = BotFace.motion(time: 0.55, seed: 2, spec: spec, state: .streaming, since: 2)
        #expect(m.eyeOpen == 0.55)
        #expect(m.sheen > 0.3)
    }

    @Test func theFinishTurnAndTheTapNeverReachTheCaller() {
        // As written today, `motion` applies the finish turn and the tap in a `defer`, which runs
        // after `return m` has already copied the pose: the caller gets no yaw, no blink. The
        // 1.5 port replaces both with the eye orbit (decision 9), so this stays as a record of
        // what 1.4 did, not as a target.
        let finish = BotFace.motion(time: 100.575, seed: 2, spec: spec, state: .working, finishedAt: 100)
        #expect(finish.yaw == 0 && finish.eyeOpen == 1)
        let tap = BotFace.motion(time: 100.275, seed: 2, spec: spec, state: .idle, tappedAt: 100)
        #expect(tap.yaw == 0)
    }

    @Test func theMotionStyleScalesTheBodyNotTheHold() {
        BotFace.motionScale = 0.5
        defer { BotFace.motionScale = 1 }
        let m = BotFace.motion(time: 10, seed: 2, spec: spec, state: .awaitingApproval, since: 2)
        #expect(m.morph == 1, "the held silhouette is not scaled")
        #expect(abs(m.roll) < 0.1, "the lean is halved")
    }

    @Test func theWidgetsHoldAStillPosePerPhase() {
        #expect(BotFace.widgetPose(phase: "thinking", attention: false).morphTarget == .pebble)
        #expect(BotFace.widgetPose(phase: "tool", attention: false).morphTarget == .stem)
        #expect(BotFace.widgetPose(phase: "streaming", attention: false).eyeOpen == 0.55)
        #expect(BotFace.widgetPose(phase: "error", attention: false).dim == 1)
        #expect(BotFace.widgetPose(phase: "done", attention: false) == BotFace.Motion())
        let ask = BotFace.widgetPose(phase: "streaming", attention: true)
        #expect(ask.morphTarget == .exclamation && ask.eyeOpacity == 0)
    }

    @Test func blinksCloseFullyAndNeverInUnison() {
        // Today's blink is applied after everything else: a blink reaches 92 % shut.
        var lowest = 1.0
        for i in 0..<500 {
            let l = BotFace.liveliness(time: Double(i) * 0.01, seed: 3)
            lowest = min(lowest, 1 - l.blink * 0.92)
        }
        #expect(lowest <= 0.12)
        // Two bots with different seeds do not blink at the same moment.
        let t = (0..<2000).map { Double($0) * 0.01 }
        let a = t.filter { BotFace.liveliness(time: $0, seed: 3).blink > 0.5 }
        let b = t.filter { BotFace.liveliness(time: $0, seed: 8).blink > 0.5 }
        #expect(!a.isEmpty && !b.isEmpty && Set(a).intersection(b).isEmpty)
    }
}
