import Testing
@testable import Vory

/// #378: a chat from Home's Pick up opens on Chats with its title and comes back to Home when it
/// closes; Siri's, Spotlight's and the restore's opens are as before.
@MainActor @Suite struct PickUpRouteTests {
    @Test func pickUpOpensOnChatsWithItsTitleAndHome() {
        let m = AppModel()
        m.selectedTab = .dashboard
        m.openStoredChat(id: "20260930_221000_work01", profile: "work", title: "Bot Chat", returningTo: .dashboard)
        #expect(m.selectedTab == .chats)
        #expect(m.pendingRoute?.storedSessionID == "20260930_221000_work01")
        #expect(m.pendingRoute?.profile == "work")
        #expect(m.pendingRoute?.title == "Bot Chat")
        #expect(m.pendingRoute?.returnTab == .dashboard)
    }

    @Test func otherOpensCarryNoTitleAndNoReturn() {
        let m = AppModel()
        m.openStoredChat(id: "20260921_154212_a1b2c3", profile: "")
        #expect(m.selectedTab == .chats)
        #expect(m.pendingRoute?.profile == nil)
        #expect(m.pendingRoute?.title == nil)
        #expect(m.pendingRoute?.returnTab == nil)
    }
}
