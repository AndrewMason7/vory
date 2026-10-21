import StoreKit
import Testing
@testable import Vory

/// "Replay the welcome tour" (#487) is offered on a test build only: TestFlight's (the App Store's sandbox), Xcode's or
/// a Debug build; never on the App Store's build, nor when the App Store can't say which this is.
@Suite struct TourReplayTests {
    @Test func onlyATestBuildOffersTheReplay() {
        #expect(TourReplay.allowed(environment: .sandbox, debug: false), "TestFlight")
        #expect(TourReplay.allowed(environment: .xcode, debug: false), "installed by Xcode")
        #expect(!TourReplay.allowed(environment: .production, debug: false), "the App Store")
        #expect(!TourReplay.allowed(environment: nil, debug: false), "the App Store couldn't say")
        #expect(TourReplay.allowed(environment: .production, debug: true), "a Debug build")
        #expect(TourReplay.allowed(environment: nil, debug: true), "a Debug build")
    }
}
