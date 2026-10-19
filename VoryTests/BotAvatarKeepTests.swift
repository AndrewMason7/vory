import Foundation
import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import Vory

/// #422: a bot's face is kept across the background (an NSCache empties itself as the app leaves, just before the
/// switcher snapshot draws the app), its other appearance is drawn once at idle, and a change of look draws it again.
/// Each test uses a profile of its own that no bot has, so no stored look is written.
@MainActor
@Suite(.serialized)
struct BotAvatarKeepTests {
    private func profile() -> String { "keep-test-\(UUID().uuidString.prefix(8))" }

    @Test func aFaceIsTheSamePictureAfterTheAppLeaves() {
        let p = profile()
        let first = BotAvatarImage.cached(profile: p, size: 21, scheme: .light)
        #if canImport(UIKit)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #endif
        #expect(BotAvatarImage.cached(profile: p, size: 21, scheme: .light) === first)
        #expect(BotAvatarImage.cached(profile: p, size: 21, scheme: .light, closed: true) !== first)
    }

    @Test func theOtherAppearanceIsDrawnAtIdle() async throws {
        let p = profile()
        _ = BotAvatarImage.cached(profile: p, size: 22, scheme: .light)
        #expect(BotAvatarImage.kept["\(p)|22.0|d|open"] == nil)
        try await Task.sleep(for: .milliseconds(1600))
        let dark = try #require(BotAvatarImage.kept["\(p)|22.0|d|open"])
        #expect(dark.look == BotAvatarImage.look(for: p))
        #expect(BotAvatarImage.cached(profile: p, size: 22, scheme: .dark) === dark.image)
    }

    @Test func aNewLookDrawsTheFaceAgain() {
        let p = profile()
        let first = BotAvatarImage.cached(profile: p, size: 23, scheme: .light)
        let before = BotAvatarImage.look(for: p)
        BotAvatarStore.removePhoto(for: p)   // no photo to remove: only the photo generation moves on
        #expect(BotAvatarImage.look(for: p) != before)
        let again = BotAvatarImage.cached(profile: p, size: 23, scheme: .light)
        #expect(again !== first)
        #expect(BotAvatarImage.cached(profile: p, size: 23, scheme: .light) === again)
    }
}
