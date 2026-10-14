#if os(iOS)
import Foundation
import Testing
@testable import Vory

/// #371: a cold launch after the system ended the app in the background opens the chat that was
/// open (within the hour, on the same gateway), and not after two launches in a row that ended
/// in front within a minute.
@Suite struct AppRestoreTests {
    private let gateway = UUID()
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private let address = "https://gateway.example.com"

    private func saved(minutesAgo: Double, on connection: UUID? = nil, at gatewayAddress: String? = nil) -> AppRestore.Saved {
        AppRestore.Saved(storedID: "20261013_101500_abc123", profile: "workshop", connectionID: connection ?? gateway,
                         gateway: gatewayAddress ?? address, leftAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func reopening(_ s: AppRestore.Saved?, connection: UUID?, gateway: String? = nil, shortLaunches: Int = 0) -> AppRestore.Saved? {
        AppRestore.reopening(s, now: now, connection: connection, gateway: gateway, shortLaunches: shortLaunches)
    }

    @Test func aChatLeftWithinTheHourOnTheSameGatewayIsOpenedAgain() {
        let s = saved(minutesAgo: 20)
        #expect(reopening(s, connection: gateway) == s)
        #expect(reopening(saved(minutesAgo: 59), connection: gateway) != nil)
        // The same address under a new connection (the demo copy re-adds its gateway each launch).
        #expect(reopening(s, connection: UUID(), gateway: address) == s)
    }

    @Test func notAfterAnHourNotAnotherGatewayNotNothing() {
        #expect(reopening(saved(minutesAgo: 61), connection: gateway) == nil)
        #expect(reopening(saved(minutesAgo: 5, on: UUID()), connection: gateway, gateway: "https://other.example.com") == nil)
        #expect(reopening(saved(minutesAgo: 5), connection: nil, gateway: address) == nil)
        #expect(reopening(nil, connection: gateway) == nil)
        // A clock set back: a time in the future is not trusted.
        #expect(reopening(saved(minutesAgo: -10), connection: gateway) == nil)
    }

    @Test func oneShortLaunchStillRestoresTwoDoNot() {
        #expect(reopening(saved(minutesAgo: 5), connection: gateway, shortLaunches: 1) != nil)
        #expect(reopening(saved(minutesAgo: 5), connection: gateway, shortLaunches: 2) == nil)
    }

    @Test func launchesThatEndInFrontWithinAMinuteAreCountedInARow() throws {
        let name = "AppRestoreTests-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        func short() -> Int { d.integer(forKey: AppRestore.shortLaunchesKey) }

        AppRestore.startLaunch(defaults: d)         // first launch ever
        #expect(short() == 0)
        AppRestore.startLaunch(defaults: d)         // the one before ended in front, still marked
        #expect(short() == 1)
        AppRestore.startLaunch(defaults: d)
        #expect(short() == 2)
        AppRestore.lasted(defaults: d)              // this one lasted (or left the screen)
        #expect(short() == 0)
        #expect(d.object(forKey: AppRestore.launchedAtKey) == nil)
        AppRestore.startLaunch(defaults: d)         // the one before lasted: the count starts over
        #expect(short() == 0)
        AppRestore.lasted(defaults: d)
        AppRestore.lasted(defaults: d)              // twice is harmless
        #expect(short() == 0)
    }

    /// Call #33: swiping the app away starts fresh. The system drops the scene's storage then, and
    /// the chat reopens only when the scene still holds it.
    @Test func theSceneMustStillHoldTheChat() {
        let s = saved(minutesAgo: 5)
        #expect(AppRestore.sceneAgrees(s, sceneChat: s.storedID))
        #expect(!AppRestore.sceneAgrees(s, sceneChat: ""), "a swiped-away app reopened its chat")
        #expect(!AppRestore.sceneAgrees(s, sceneChat: nil))
        #expect(!AppRestore.sceneAgrees(s, sceneChat: "20261013_090000_other1"))
    }

    @Test func whatIsSavedReadsBack() throws {
        let s = saved(minutesAgo: 3)
        let back = try JSONDecoder().decode(AppRestore.Saved.self, from: try JSONEncoder().encode(s))
        #expect(back == s)
    }
}
#endif
