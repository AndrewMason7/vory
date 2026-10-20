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
    /// The window can fold: it reports a division, active or not (an open Duo, flat or half
    /// open). Layouts that must not reflow at every hinge move key on this, not on a fold.
    var foldable = false
    /// Apple's margin for interactive content beside a region.
    static let margin: CGFloat = 8
    var isEmpty: Bool { divisions.isEmpty && occlusions.isEmpty }
    var all: [CGRect] { divisions + occlusions }
    /// A fold that runs across the window (a laptop pose): top and bottom halves.
    var horizontalFold: CGRect? { divisions.first { $0.width > $0.height } }
    /// A fold that runs up the window (a book pose): left and right halves.
    var verticalFold: CGRect? { divisions.first { $0.height >= $0.width } }

    /// How far a list growing up from `y` (window space) may reach before a fold across the
    /// window above it, the margin kept: nil with no such fold above `y`. No floor (Duo stage
    /// 2): a floor won over the fold and the + panel opened across it (the 10-12 round). A list
    /// that wants more room than this lifts the dock over the fold instead (`dockLift`).
    func room(under y: CGFloat) -> CGFloat? {
        guard let fold = horizontalFold, y > fold.midY else { return nil }
        return max(0, y - fold.maxY - Self.margin)
    }

    /// How far the chat's dock moves up off a fold across the window (a laptop pose), so that
    /// its bottom edge sits the margin above the fold; 0 where it stays. `dock` is where the
    /// dock stands unlifted (window space). It moves when it is on the fold itself (the
    /// keyboard pushed it there), and when it stands under the fold while an open list (+, "/",
    /// "@") would reach across it: `listTop`, the list's top edge at full size with the dock
    /// unlifted, nil with no list open. `held` keeps a lift made for the list until the list
    /// closes (the Checker's call: the dock rides above the fold while the list is open), so
    /// the list's own resizing after the lift cannot drop the dock back under it.
    func dockLift(dock: CGRect, listTop: CGFloat? = nil, held: Bool = false) -> CGFloat {
        guard let fold = horizontalFold, dock.height > 0 else { return 0 }
        let onFold = dock.minY < fold.maxY + Self.margin && dock.maxY > fold.minY - Self.margin
        let underFold = dock.minY >= fold.maxY + Self.margin
        let listCrosses = listTop.map { held || $0 < fold.maxY + Self.margin } ?? false
        guard onFold || (underFold && listCrosses) else { return 0 }
        return dock.maxY - fold.minY + Self.margin
    }

    /// The width of the list column in two columns when a fold runs up the window (a book
    /// pose): the column ends at the fold's middle, so the fold is the line between the list
    /// and the chat, as Apple advises, rather than running through the chat. `leading` is the
    /// split view's leading edge (window space). Nil with no such fold, or where that width is
    /// outside the column's `range`: the usual width stands.
    func listWidth(leading: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat? {
        guard let fold = verticalFold else { return nil }
        let width = (fold.midX - leading).rounded(.down)
        return range.contains(width) ? width : nil
    }
}

/// Home's six tiles (DashboardView): three to a row, two even rows, on a phone, an iPad and the
/// Mac; two to a row on a window that can fold (the open Duo), so a fold up the middle falls
/// between them and never through one (the Checker's call, Duo plan section 6). Keyed to the
/// window being foldable, not to the fold being there, so the tiles don't reflow at every
/// hinge move; a fold up the window counts too, in case a flat Duo reports no division.
enum HomeTiles {
    static func columns(regions: ReservedRegions) -> Int {
        #if os(macOS)
        3
        #else
        regions.foldable || regions.verticalFold != nil ? 2 : 3
        #endif
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
                    occlusions: proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map { $0.frame.offsetBy(dx: origin.x, dy: origin.y) },
                    foldable: !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty)
                content().environment(\.reservedRegions, regions)
            }
        }
    }
    #endif
}
