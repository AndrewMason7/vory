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

/// Which side edge the system would lay a vertical bar on in this window (the closed iPhone
/// Duo's strip, the open Duo in landscape), or nil where bars run along the bottom. Read from
/// the iOS 27.1 environment; nil on anything older.
struct VerticalBarEdge<Content: View>: View {
    @ViewBuilder var content: (HorizontalEdge?) -> Content

    var body: some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            Reader(content: content)
        } else {
            content(nil)
        }
        #else
        content(nil)
        #endif
    }

    #if os(iOS)
    @available(iOS 27.1, *)
    private struct Reader: View {
        @Environment(\.toolbarVerticalEdge) private var edge
        @ViewBuilder var content: (HorizontalEdge?) -> Content
        var body: some View { content(edge) }
    }
    #endif
}

/// How far a tab's pages start under the floating top bar's row (#340). The system keeps a band at the top for its
/// navigation bar, and the bar's row sits over that band; where the system's bars stand in a side strip instead (the
/// closed iPhone Duo, `toolbarVerticalEdge`), there is no band, and a root page's first row and its search field ran
/// under the row. Then the tab's navigation stack starts under the row's bottom (`rowBottom`, in the bar's space) plus
/// the bar's top padding and a gap (`TopBarRoomProbe`, as the stack's own additional safe area, so the system's search
/// drawer moves with the page); anywhere else, 0.
enum TopBarRoom {
    /// The bar's padding over its row (MorphTopBar's `.padding(.top, 4)`).
    static let barPadding: CGFloat = 4
    /// The gap between the row's bottom and the page.
    static let gap: CGFloat = 8
    static func inset(barsVertical: Bool, barOn: Bool, rowBottom: CGFloat) -> CGFloat {
        guard barsVertical, barOn, rowBottom > 0 else { return 0 }
        return (rowBottom + barPadding + gap).rounded()
    }
}


/// The fold on a partly open iPhone Duo, where it crosses this view's frame (its own
/// coordinates), with Apple's margins for interactive content included; nil when there is no
/// active fold here. Read through the iOS 27.1 geometry; nil on anything older.
struct FoldReader<Content: View>: View {
    @ViewBuilder var content: (_ fold: CGRect?) -> Content

    var body: some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            Reader(content: content)
        } else {
            content(nil)
        }
        #else
        content(nil)
        #endif
    }

    #if os(iOS)
    @available(iOS 27.1, *)
    private struct Reader: View {
        @ViewBuilder var content: (_ fold: CGRect?) -> Content
        var body: some View {
            GeometryReader { proxy in
                let fold = proxy.reservedRegions(kind: .division).first { $0.isActive }?.frame
                content(fold)
            }
        }
    }
    #endif
}

/// Where a floating piece should sit so it stays off `fold`: unchanged when the fold does not
/// cross it, otherwise shifted to whichever side of the fold has more room in `width`.
enum FoldAvoidance {
    static func offset(for frame: CGRect, fold: CGRect?, in width: CGFloat) -> CGFloat {
        guard let fold, fold.intersects(frame) else { return 0 }
        let leftRoom = fold.minX, rightRoom = width - fold.maxX
        if rightRoom >= leftRoom { return fold.maxX - frame.minX }
        return fold.minX - frame.maxX
    }
}

/// The window's reserved regions (iOS 27.1): the fold of a partly open iPhone Duo (`divisions`)
/// and the camera's housing or anything else that covers the display (`occlusions`), in window
/// space, active ones only. Custom floating pieces keep their interactive content outside these
/// frames plus a margin (`ReservedRegions.margin`); system pieces (sheets, menus, lists, the
/// split view) already do. Read once at the root (`RootView`) and handed down the environment;
/// empty on anything older and on the Mac.
struct ReservedRegions: Equatable {
    var divisions: [CGRect] = []
    var occlusions: [CGRect] = []
    /// Apple's margin for interactive content beside a region.
    static let margin: CGFloat = 8
    var isEmpty: Bool { divisions.isEmpty && occlusions.isEmpty }
    var all: [CGRect] { divisions + occlusions }
    /// A fold that runs across the window (a laptop pose): top and bottom halves.
    var horizontalFold: CGRect? { divisions.first { $0.width > $0.height } }
    /// A fold that runs up the window (a book pose): left and right halves.
    var verticalFold: CGRect? { divisions.first { $0.height >= $0.width } }

    /// Where a piece at `frame` (window space) that stands on the lower side of a horizontal
    /// fold may reach up to: the fold's bottom edge plus the margin, or nil with no such fold.
    func ceiling(for frame: CGRect) -> CGFloat? {
        guard let fold = horizontalFold, frame.midY > fold.midY else { return nil }
        return fold.maxY + Self.margin
    }
}

extension EnvironmentValues {
    @Entry var reservedRegions = ReservedRegions()
}

/// Reads the window's reserved regions at the root and publishes them (window space) through
/// the environment, with margins left for the pieces that read them.
struct ReservedRegionsReader<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            Reader(content: content)
        } else {
            content()
        }
        #else
        content()
        #endif
    }

    #if os(iOS)
    @available(iOS 27.1, *)
    private struct Reader: View {
        @ViewBuilder var content: () -> Content
        var body: some View {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                let regions = ReservedRegions(
                    divisions: proxy.reservedRegions(kind: .division).filter(\.isActive).map { $0.frame.offsetBy(dx: origin.x, dy: origin.y) },
                    occlusions: proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map { $0.frame.offsetBy(dx: origin.x, dy: origin.y) })
                content().environment(\.reservedRegions, regions)
            }
        }
    }
    #endif
}
