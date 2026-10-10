import SwiftUI

/// Whether the window is wide enough for the reading-width layout: a column in the middle,
/// bubbles capped, grids with more columns. True on the Mac; on iOS it follows the horizontal
/// size class (regular on iPad, the open Duo and a large window; compact on a phone, a closed
/// Duo and a narrow window), never the idiom or the screen.
extension EnvironmentValues {
    @Entry var wideLayout: Bool = {
        #if os(macOS)
        true
        #else
        false
        #endif
    }()
}

extension View {
    /// A reading column of `width` in the middle of the page when the layout is wide; the full
    /// width otherwise. Replaces the `#if os(macOS)` column caps so iPad and the open Duo get
    /// the Mac's page shape.
    func readingColumn(_ width: CGFloat) -> some View { modifier(ReadingColumn(width: width)) }
}

private struct ReadingColumn: ViewModifier {
    @Environment(\.wideLayout) private var wide
    let width: CGFloat
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: wide ? width : .infinity)
            .frame(maxWidth: .infinity)
    }
}

/// Grid columns that divide cleanly: an even count on a wide layout, so a fold down the middle
/// of the window (the Duo's book posture) falls between columns and never through a card.
enum EvenColumns {
    /// How many columns of at least `minimum` points (plus `spacing` between them) fit in
    /// `width`, rounded down to an even number and never under `floor`.
    static func count(width: CGFloat, minimum: CGFloat, spacing: CGFloat, floor: Int = 2) -> Int {
        guard width > 0, minimum > 0 else { return floor }
        let fit = Int((width + spacing) / (minimum + spacing))
        return max(floor, fit - fit % 2)
    }

    static func items(_ count: Int, spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, count))
    }
}
