import Foundation
import Testing
@testable import Vory

/// When Home loads (`DashboardView.shouldLoad`): hidden, only for a gateway it has not loaded from
/// yet (the launch load behind the tab in front, which also refreshes the Overview widget, and a
/// gateway switch); live, whenever its key moved.
@Suite struct HomeLoadGateTests {
    let a = UUID(), b = UUID()
    func key(_ c: UUID?, profile: String = "default", visits: Int = 0) -> String { "\(c?.uuidString ?? "")|\(profile)|30|false|\(visits)" }

    @Test func hiddenAtLaunchBeforeTheGatewayIsUpDoesNotLoad() {
        #expect(!DashboardView.shouldLoad(pageLive: false, connection: nil, loadedConnection: nil, key: key(nil), loadedKey: ""))
    }

    @Test func hiddenWhenTheGatewayComesUpLoads() {
        #expect(DashboardView.shouldLoad(pageLive: false, connection: a, loadedConnection: nil, key: key(a), loadedKey: ""))
    }

    @Test func hiddenAfterAGatewaySwitchLoads() {
        #expect(DashboardView.shouldLoad(pageLive: false, connection: b, loadedConnection: a, key: key(b), loadedKey: key(a)))
    }

    @Test func hiddenWhenTheBotChangesWaitsForTheReturn() {
        #expect(!DashboardView.shouldLoad(pageLive: false, connection: a, loadedConnection: a, key: key(a, profile: "work"), loadedKey: key(a)))
    }

    @Test func liveWhenTheBotChangedLoads() {
        #expect(DashboardView.shouldLoad(pageLive: true, connection: a, loadedConnection: a, key: key(a, profile: "work"), loadedKey: key(a)))
    }

    @Test func liveOnANewMacVisitLoads() {
        #expect(DashboardView.shouldLoad(pageLive: true, connection: a, loadedConnection: a, key: key(a, visits: 1), loadedKey: key(a)))
    }

    @Test func liveWithNothingChangedDoesNotLoadAgain() {
        #expect(!DashboardView.shouldLoad(pageLive: true, connection: a, loadedConnection: a, key: key(a), loadedKey: key(a)))
    }
}
