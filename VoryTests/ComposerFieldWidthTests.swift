#if os(iOS)
import Testing
import UIKit
import SwiftUI
@testable import Vory

/// #433: the message field's size never comes from the width it last had. Asked for its ideal size it gave its
/// own bounds, so a bar laid out wider once kept that width, and the chat page with it.
@MainActor @Suite struct ComposerFieldWidthTests {
    private func field(width: CGFloat) -> UITextView {
        let v = UITextView(frame: CGRect(x: 0, y: 0, width: width, height: 40))
        v.font = .preferredFont(forTextStyle: .body)
        v.text = "Restart the export once the index is in"
        v.layoutIfNeeded()
        return v
    }

    @Test func askedForItsIdealSizeTheFieldGivesItsOwnSmallWidthNotTheWidthItHad() {
        let v = field(width: 1000)
        let size = ComposerTextView.fit(.unspecified, v, maxLines: 6)
        #expect(size?.width == ComposerTextView.idealWidth, "the field answered \(String(describing: size)) after being 1000 wide")
        // Its height is the text's at that width, within the line cap.
        let line = v.font?.lineHeight ?? 22
        #expect((size?.height ?? 0) >= line && (size?.height ?? 0) <= ceil(line * 6))
    }

    @Test func aProposedWidthIsTheWidthItTakes() {
        let v = field(width: 1000)
        #expect(ComposerTextView.fit(ProposedViewSize(width: 300, height: nil), v, maxLines: 6)?.width == 300)
        #expect(ComposerTextView.fit(ProposedViewSize(width: .infinity, height: nil), v, maxLines: 6)?.width == .infinity)
        #expect(ComposerTextView.fit(ProposedViewSize(width: 0, height: nil), v, maxLines: 6) == nil)
    }
}
#endif
