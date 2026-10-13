#if os(macOS)
import Foundation
import Testing
import Observation
@testable import Vory

/// #248: on the Mac the bots move only while something is working. The 1.4 "Animate bots" switch
/// is gone in 1.5; a stored "off" becomes the Still style once.
@MainActor
@Suite(.serialized) struct MacBotAnimationTests {
    private func defaults() -> UserDefaults {
        let name = "MacBotAnimationTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func animateBotsOffBecomesTheStillStyleOnce() {
        let d = defaults()
        d.set(false, forKey: MacBotMotion.oldAnimateKey)
        MacBotMotion.migrateAnimateSwitch(defaults: d)
        #expect(d.string(forKey: MacBotMotion.styleKey) == "still")
        #expect(d.object(forKey: MacBotMotion.oldAnimateKey) == nil)
        // Run again: nothing to migrate, a style chosen since stays.
        d.set("lively", forKey: MacBotMotion.styleKey)
        MacBotMotion.migrateAnimateSwitch(defaults: d)
        #expect(d.string(forKey: MacBotMotion.styleKey) == "lively")
    }

    @Test func animateBotsOnOrUnsetLeavesTheStyleAlone() {
        let d = defaults()
        MacBotMotion.migrateAnimateSwitch(defaults: d)
        #expect(d.string(forKey: MacBotMotion.styleKey) == nil)
        d.set(true, forKey: MacBotMotion.oldAnimateKey)
        d.set("calm", forKey: MacBotMotion.styleKey)
        MacBotMotion.migrateAnimateSwitch(defaults: d)
        #expect(d.string(forKey: MacBotMotion.styleKey) == "calm")
        #expect(d.object(forKey: MacBotMotion.oldAnimateKey) == nil)
    }

    @Test func theTurnBoardTellsTheBotsWhenSomethingIsWorking() {
        let board = TurnBoard.shared
        let ambient = BotAmbient.shared
        let id = "test-\(UUID().uuidString)"
        defer { board.remove(id) }
        board.remove(id)
        #expect(ambient.anyWorking == !board.turns.isEmpty)
        board.upsert(TurnBoard.Turn(id: id, title: "T", bot: "B", profile: "default", detail: "Thinking…", attention: false, startedAt: Date()))
        #expect(ambient.anyWorking)
        #expect(ambient.decorativeActive)
        // Waiting on an approval still counts: the bot is mid-turn.
        board.upsert(TurnBoard.Turn(id: id, title: "T", bot: "B", profile: "default", detail: "Needs you", attention: true, startedAt: Date()))
        #expect(ambient.anyWorking)
        board.remove(id)
        #expect(ambient.anyWorking == !board.turns.isEmpty)
    }

    /// The menu bar item reads the counts; a running turn's row rewritten (about once a second
    /// while a reply streams) must not tell it anything changed, or the whole app scene updates.
    @Test func aRewrittenRowLeavesTheMenuBarCountsAlone() {
        let board = TurnBoard.shared
        let id = "test-\(UUID().uuidString)"
        defer { board.remove(id) }
        let running = board.running, attention = board.attention
        board.upsert(TurnBoard.Turn(id: id, title: "T", bot: "B", profile: "default", detail: "Thinking…", attention: false, startedAt: Date()))
        #expect(board.running == running + 1 && board.attention == attention)
        final class Told: @unchecked Sendable { var value = false }
        let told = Told()
        withObservationTracking { _ = board.running; _ = board.attention } onChange: { told.value = true }
        board.upsert(TurnBoard.Turn(id: id, title: "T", bot: "B", profile: "default", detail: "Writing…", attention: false, startedAt: Date()))
        #expect(!told.value)
        // Needing you moves it from one count to the other, and that is news.
        board.upsert(TurnBoard.Turn(id: id, title: "T", bot: "B", profile: "default", detail: "Needs you", attention: true, startedAt: Date()))
        #expect(told.value)
        #expect(board.running == running && board.attention == attention + 1)
        board.remove(id)
        #expect(board.running == running && board.attention == attention)
    }
}
#endif
