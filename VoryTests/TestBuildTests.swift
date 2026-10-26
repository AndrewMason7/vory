import StoreKit
import Testing
@testable import Vory

/// What only a test build offers (Settings › Troubleshooting's Replay the welcome tour, #487, and Screen layout, #516):
/// TestFlight's (the App Store's sandbox), Xcode's or a Debug build; never the App Store's build, nor when the App Store
/// can't say which this is. Every row reads the one flag.
@Suite struct TestBuildTests {
    @Test func onlyATestBuildIsOne() {
        #expect(TestBuild.allowed(environment: .sandbox, debug: false), "TestFlight")
        #expect(TestBuild.allowed(environment: .xcode, debug: false), "installed by Xcode")
        #expect(!TestBuild.allowed(environment: .production, debug: false), "the App Store")
        #expect(!TestBuild.allowed(environment: nil, debug: false), "the App Store couldn't say")
        #expect(TestBuild.allowed(environment: .production, debug: true), "a Debug build")
        #expect(TestBuild.allowed(environment: nil, debug: true), "a Debug build")
    }

    /// On the main actor: TroubleshootingView is a View, so its statics are the main actor's.
    @Test @MainActor func troubleshootingsTestBuildRowsAllReadTheOneFlag() {
        #expect(TroubleshootingView.testBuildRows(testBuild: false).isEmpty, "no row on the App Store's build")
        #expect(TroubleshootingView.testBuildRows(testBuild: true) == [.replayTour, .screenLayout], "both rows on a test build")
        for env: AppStore.Environment? in [.production, .sandbox, .xcode, nil] {
            let flag = TestBuild.allowed(environment: env, debug: false)
            #expect(TroubleshootingView.testBuildRows(testBuild: flag).contains(.screenLayout) == flag)
        }
    }
}
