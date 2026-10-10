import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// A bot's display name and title as Vory keeps them (#315): set, cleared, read before the
/// gateway's names, and never touching the folder name.
@MainActor
struct BotNamesTests {
    private func suite() -> String {
        let suite = "bot-names-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        return suite
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: suite())! }

    @Test func namesAreKeptPerBotAndClearedWhenBothAreEmpty() {
        let d = defaults()
        BotNames.set(displayName: "Scribe", title: "Notes and minutes", for: "work", d)
        #expect(BotNames.names(for: "work", d) == ProfileOwnNames(displayName: "Scribe", title: "Notes and minutes"))
        #expect(BotNames.names(for: "other", d) == nil)
        // One of the two cleared: the other stays.
        BotNames.set(displayName: "  ", title: "Notes and minutes", for: "work", d)
        #expect(BotNames.names(for: "work", d) == ProfileOwnNames(displayName: nil, title: "Notes and minutes"))
        // Both cleared: the entry goes.
        BotNames.set(displayName: "", title: "", for: "work", d)
        #expect(BotNames.names(for: "work", d) == nil)
        #expect(BotNames.stored(d).isEmpty)
    }

    @Test func theLabelReadsVoryFirstThenTheGatewayThenTheFolder() {
        let suite = suite()
        let d = UserDefaults(suiteName: suite)!
        let kept = ProfileInfo.ownNames
        defer { ProfileInfo.ownNames = kept }
        // The closure must be Sendable: it opens the suite by name rather than capturing `d`.
        ProfileInfo.ownNames = { BotNames.names(for: $0, UserDefaults(suiteName: suite)!) }

        let bare = ProfileInfo(name: "work")
        #expect(bare.label == "work" && bare.title == nil)
        let fromGateway = ProfileInfo(name: "work", displayName: "Work bot", botTitle: "Ops")
        #expect(fromGateway.label == "Work bot" && fromGateway.title == "Ops")
        BotNames.set(displayName: "Scribe", title: nil, for: "work", d)
        #expect(fromGateway.label == "Scribe" && fromGateway.title == "Ops")
        BotNames.set(displayName: nil, title: "Minutes", for: "work", d)
        #expect(fromGateway.label == "Work bot" && fromGateway.title == "Minutes")
        // Clearing goes back to the gateway's, then the folder name.
        BotNames.set(displayName: nil, title: nil, for: "work", d)
        #expect(fromGateway.label == "Work bot" && bare.label == "work")
        // The folder name is the id whatever the label says.
        #expect(fromGateway.id == "work")
    }
}
