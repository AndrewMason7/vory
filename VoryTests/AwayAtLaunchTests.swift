#if os(iOS)
import Foundation
import Observation
import Testing
import UIKit
@testable import Vory
@testable import VoryCore

/// #371: a runtime started in the background (no scene to say so) starts away, and is in front
/// again as soon as the app becomes active, whatever the scene's phase reported: away holds the
/// chats' views still, and it must never stick.
@MainActor @Suite struct AwayAtLaunchTests {
    final class Fired: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func fire() { lock.withLock { n += 1 } }
        var count: Int { lock.withLock { n } }
    }

    @Test func aLaunchInTheBackgroundStartsAwayAndOneInFrontDoesNot() {
        #expect(AwayAtLaunch.startsAway(.background))
        #expect(!AwayAtLaunch.startsAway(.inactive))
        #expect(!AwayAtLaunch.startsAway(.active))
    }

    @Test func aBackgroundLaunchThenTheAppOpenedTheRowsUpdate() throws {
        let conn = GatewayConnection(name: "unit", gateway: try GatewayURL.normalize("https://127.0.0.1:1"), authMode: .sessionToken)
        let rt = GatewayRuntime(connection: conn, store: ConnectionStore())
        let chat = ChatSession(runtime: rt, storedID: nil, title: nil)
        rt.registry.add(chat)
        let center = NotificationCenter()
        let observer = AwayAtLaunch.clearOnActive(center: center) { rt }
        defer { center.removeObserver(observer) }

        // Launched in the background: a turn's rows arrive with the views held still.
        rt.isAway = AwayAtLaunch.startsAway(.background)
        let fired = Fired()
        withObservationTracking { _ = chat.items } onChange: { fired.fire() }
        chat.handle(event: GatewayEvent(type: "message.start", sessionID: "s1", payload: .object([:]), seq: nil))
        #expect(fired.count == 0)

        // The app opened (no scene phase change reported): in front, and the rows are told.
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(rt.isAway == false)
        #expect(fired.count == 1, "the rows did not update once the app was active")

        // In front from then on: a change is told at once.
        let live = Fired()
        withObservationTracking { _ = chat.items } onChange: { live.fire() }
        chat.handle(event: GatewayEvent(type: "message.complete", sessionID: "s1", payload: .object(["text": .string("Done."), "status": .string("complete")]), seq: nil))
        #expect(live.count == 1)
    }
}
#endif
