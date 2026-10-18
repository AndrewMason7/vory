import Testing
@testable import Vory

/// The tab bar on a wide window (iPad, the open Duo): a chat open beside the list does not
/// hide it; on a narrow window the chat is pushed over the list and the bar steps aside as before.
@MainActor @Suite struct WideLayoutTests {
    @Test func anOpenChatHidesTheBarOnlyOnANarrowWindow() {
        let m = AppModel()
        m.selectedTab = .chats
        m.chatsPathOpen = true
        m.wideLayout = false
        #expect(m.tabBarHidden)
        m.wideLayout = true
        #expect(!m.tabBarHidden)
    }

    @Test func aKeyboardOrAHidingPageStillHidesItWhenWide() {
        let m = AppModel()
        m.wideLayout = true
        m.keyboardUp = true
        #expect(m.tabBarHidden)
        m.keyboardUp = false
        m.selectedTab = .bots
        m.tabBarHiders[.bots] = 1
        #expect(m.tabBarHidden)
    }
}
