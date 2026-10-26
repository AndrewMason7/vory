import StoreKit

/// A test build: a Debug build, or one installed from TestFlight (the App Store's sandbox) or by Xcode; never the App
/// Store's. The one gate for what only a test build offers, all of it on one flag asked once at launch
/// (`AppModel.testBuild`): Settings › Troubleshooting's Replay the welcome tour (#487) and Screen layout (#516).
enum TestBuild {
    static func allowed(environment: AppStore.Environment?, debug: Bool) -> Bool {
        debug || environment == .sandbox || environment == .xcode
    }

    /// This build's answer, asked once at launch. False when the App Store can't say.
    static func allowedHere() async -> Bool {
        #if DEBUG
        return true
        #else
        guard let result = try? await AppTransaction.shared else { return false }
        switch result {
        case .verified(let t), .unverified(let t, _): return allowed(environment: t.environment, debug: false)
        }
        #endif
    }
}
