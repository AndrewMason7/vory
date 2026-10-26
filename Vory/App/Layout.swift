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
    /// The row's room (stage 1's: the row's bottom, in the bar's space, plus the bar's padding and a gap) where nothing
    /// of the system's keeps the page under the row: where its bars stand vertical in a side strip (the closed iPhone
    /// Duo, stage 1), or where its status stands in a top corner of the window (`ReservedRegions.statusInCorner`: the
    /// open Duo upright, flat or half open like a laptop, whose search field stood under the row; the stage 2 probe).
    /// A phone and an iPad have neither: nothing, unchanged. Worked out from the window's shape alone, never read back
    /// from the page: a room keyed on what the page measured flapped, stuck, or missed (the stage 2 A/B).
    /// ASSUMPTION (the one line to change if a device ever breaks it): a status standing in a top corner means the system
    /// keeps no band of its own under the row.
    static func inset(barsVertical: Bool, statusInCorner: Bool, barOn: Bool, rowBottom: CGFloat) -> CGFloat {
        guard barOn, rowBottom > 0 else { return 0 }
        if barsVertical { return (rowBottom + barPadding + gap).rounded() }
        return statusInCorner ? cornerRoom : 0
    }
    /// Whether a page's search keeps the navigation bar while it's presented (`.searchPresentationToolbarBehavior
    /// (.avoidHidingContent)`): under a status in a top corner only (#516). There the corner room holds the field under the
    /// row through the bar's own title band; with the band hidden by an active search the field and its Cancel rode up
    /// under the row's capsules, and a room changed to follow the search arrived after UIKit had moved the field (the page
    /// jumped as the search started and ended). Keeping the bar, the field stays where it is and nothing changes late.
    /// Everywhere else (phones, iPads, the closed Duo) the system's own behaviour, unchanged.
    static func keepsBarWhileSearching(statusInCorner: Bool) -> Bool { statusInCorner }
    /// The room under a status in a top corner. ASSUMPTION (iOS 27.1 to 27.2, the open Duo upright and as a laptop): UIKit
    /// brings the navigation bar's own title band (58 pt) back under the safe area once any additional inset is set, so
    /// the smallest inset puts the search drawer just under the row: 1 pt leaves it at 141 against the row's 130, where
    /// 56 (the full room) left it at 196, a 66 pt empty band; with no inset the field stood under the row.
    /// TopBarRoomUITests holds the drawer within 16 pt of the row, so an iOS that changes this trips a test.
    static let cornerRoom: CGFloat = 1
    /// The room the probe last applied, for the readouts (the DEBUG geometry probe, and Screen layout on a test build),
    /// which redraw when it changes.
    @MainActor static var lastRoom: CGFloat {
        get { AppliedRoom.shared.room }
        set { AppliedRoom.shared.room = newValue }
    }
}

/// The room the top bar's probe last applied (`TopBarRoom.lastRoom`); -1 before it has applied one. Observed so a readout
/// redraws when it changes rather than showing an old room after a pose change.
@MainActor @Observable final class AppliedRoom {
    static let shared = AppliedRoom()
    var room: CGFloat = -1
    /// Each tab root's room as its own probe last applied it. Every root applies one, the hidden ones too, so the last
    /// applied (`room`) can be a hidden tab's: Screen layout shows the front tab's, and names any root that differs.
    var rooms: [AppModel.AppTab: CGFloat] = [:]
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
    /// The division running up the window, active or not (window space): the open Duo on its
    /// side, flat or half open like a book. Layouts that must not reflow at every hinge move key
    /// on this, not on the fold being there (`upFold(_:in:)`).
    var upFold: CGRect? = nil
    /// The window can fold up its middle.
    var foldable: Bool { upFold != nil }
    /// Every region the window reports, active or not, as it reports it (window space): what Settings › Troubleshooting ›
    /// Screen layout shows (#516). The layouts read the active ones above, never these.
    var reported: [Reported] = []
    struct Reported: Equatable {
        enum Kind: Equatable { case fold, occlusion }
        var kind: Kind
        var frame: CGRect
        var active: Bool
    }

    /// The first of `divisions` (active or not, the window's own space) that runs up a window of
    /// `size` and crosses it: a fold across the window (the laptop pose, the open Duo upright)
    /// runs between rows and does not count, nor does one outside the window (the closed Duo
    /// reports none, the probe found).
    static func upFold(_ divisions: [CGRect], in size: CGSize) -> CGRect? {
        let window = CGRect(origin: .zero, size: size)
        return divisions.first { $0.height >= $0.width && $0.intersects(window) }
    }
    /// Room we keep beyond a region's frame for interactive content. 0: the Duo reports each region with Apple's
    /// margin already in its frame (the probe, 2026-10-20: the fold a 40 pt band, 20 pt either side of the hinge
    /// line, `margins` 20/20), so the 8 pt this was counted it twice.
    static let margin: CGFloat = 0
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
    /// closes (the decision: the dock rides above the fold while the list is open), so
    /// the list's own resizing after the lift cannot drop the dock back under it.
    func dockLift(dock: CGRect, listTop: CGFloat? = nil, held: Bool = false) -> CGFloat {
        guard let fold = horizontalFold, dock.height > 0 else { return 0 }
        let onFold = dock.minY < fold.maxY + Self.margin && dock.maxY > fold.minY - Self.margin
        let underFold = dock.minY >= fold.maxY + Self.margin
        let listCrosses = listTop.map { held || $0 < fold.maxY + Self.margin } ?? false
        guard onFold || (underFold && listCrosses) else { return 0 }
        return dock.maxY - fold.minY + Self.margin
    }

    /// An active occlusion in the top trailing corner of a window `width` wide: at its top edge, against its right edge
    /// (in the window's own space, whatever the writing direction), less than half its width and wider than tall (a piece
    /// of a status, not a strip down the side). The open iPhone Duo's status corner (535, 0, 134 x 82 of 669; the probe).
    /// Not: a phone's or an iPad's status, one band the window's full width (iOS 27.2); an iPad turned to landscape, whose
    /// status 27.2 reports as a strip 32 wide and the window's full height against a side; a camera under the top edge;
    /// an iPad window's own controls, in its top leading corner, should a system report them as an occlusion.
    func statusInCorner(width: CGFloat) -> Bool {
        if case .corner = statusArea(width: width) { true } else { false }
    }

    /// The status area as the layout reads it (`statusInCorner`'s rule): the corner it stands in, or why none was found.
    /// One reading for the layout and for Settings › Troubleshooting › Screen layout, which shows what the layout decided
    /// (#516: the open Duo upright gave its row no room on a real device, while the simulator did).
    enum StatusArea: Equatable {
        case corner(CGRect)
        case notFound(String)
    }
    func statusArea(width: CGFloat) -> StatusArea {
        let top = occlusions.filter { $0.minY <= 0.5 }
        if let c = top.first(where: { $0.maxX >= width - 0.5 && $0.width < width / 2 && $0.width > $0.height }) { return .corner(c) }
        guard let f = top.first else { return .notFound(occlusions.isEmpty ? "No area reported" : "None at the top edge") }
        let more = top.count > 1 ? " (the first of \(top.count) at the top edge)" : ""
        if f.maxX < width - 0.5 { return .notFound("Not against the right edge" + more) }
        if f.width >= width / 2 { return .notFound("Half the window's width or wider" + more) }
        return .notFound("Not wider than tall" + more)
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
/// Mac; two to a row on a window that can fold up its middle (the open Duo on its side), so the
/// fold falls between them and never through one. Keyed
/// to the window being foldable that way, not to the fold being there, so the tiles don't reflow
/// at every hinge move; an active fold up the window counts too, in case a flat Duo reports no
/// division. A fold across the window runs between rows: three stay.
enum HomeTiles {
    static func columns(regions: ReservedRegions) -> Int {
        #if os(macOS)
        3
        #else
        regions.foldable || regions.verticalFold != nil ? 2 : 3
        #endif
    }

    /// The grid's columns for a grid standing at `frame` (window space). Two to a row with a fold up the window
    /// (active or not) crossing the grid: the leading column ends at the fold's leading edge and the trailing one
    /// starts at its far edge, so the fold is the gap between them (Home's column is centred in the safe area, which
    /// a trailing strip moves off the window's middle and the fold). Even columns otherwise, or where a column would
    /// be under `minimum`.
    static func items(regions: ReservedRegions, frame: CGRect, spacing: CGFloat, minimum: CGFloat = 100) -> [GridItem] {
        let n = columns(regions: regions)
        if n == 2, let s = split(frame: frame, fold: regions.upFold ?? regions.verticalFold, minimum: minimum) {
            return [GridItem(.fixed(s.leading), spacing: s.gap), GridItem(.fixed(s.trailing))]
        }
        return EvenColumns.items(n, spacing: spacing)
    }

    /// The two columns' widths and the gap between them with `fold` as the gap; nil where the fold doesn't cross the
    /// grid or a column would be under `minimum`.
    static func split(frame: CGRect, fold: CGRect?, minimum: CGFloat) -> (leading: CGFloat, gap: CGFloat, trailing: CGFloat)? {
        FoldSplit.halves(frame: frame, fold: fold, minimum: minimum)
    }
}

/// A grid standing at `frame` (window space) cut in two by a fold up the window: the part before the fold, the fold
/// itself as the gap, and the part after it. Nil where the fold doesn't cross the grid or a part would be under
/// `minimum`. Home's tiles (`HomeTiles`) and the Board's column chips (`KanbanChips`) put their halves either side of it.
enum FoldSplit {
    static func halves(frame: CGRect, fold: CGRect?, minimum: CGFloat) -> (leading: CGFloat, gap: CGFloat, trailing: CGFloat)? {
        guard let fold, frame.width > 0, fold.minX > frame.minX, fold.maxX < frame.maxX else { return nil }
        let leading = fold.minX - frame.minX, trailing = frame.maxX - fold.maxX
        guard leading >= minimum, trailing >= minimum else { return nil }
        return (leading, fold.width, trailing)
    }
}

/// The Board's column chips (KanbanView): `count` to a row in even columns. On a window that can fold up its middle (the
/// open Duo on its side), with the fold crossing the chips, half of them stand each side of it and the fold is the gap
/// between the halves, so no chip lies across it (Duo stage 4, as Home's tiles). Keyed to the window being foldable,
/// not to the hinge, so the chips don't reflow as it moves. Even columns where the fold misses the chips or a chip
/// would be under `minimum`.
enum KanbanChips {
    static let minimum: CGFloat = 70

    static func items(regions: ReservedRegions, frame: CGRect, count: Int, spacing: CGFloat) -> [GridItem] {
        #if os(iOS)
        let perHalf = count / 2
        if perHalf > 0, count % 2 == 0, regions.foldable || regions.verticalFold != nil {
            let between = CGFloat(perHalf - 1) * spacing
            if let s = FoldSplit.halves(frame: frame, fold: regions.upFold ?? regions.verticalFold, minimum: CGFloat(perHalf) * minimum + between) {
                let leading = (s.leading - between) / CGFloat(perHalf), trailing = (s.trailing - between) / CGFloat(perHalf)
                return (0..<perHalf).map { GridItem(.fixed(leading), spacing: $0 == perHalf - 1 ? s.gap : spacing) }
                    + (0..<perHalf).map { _ in GridItem(.fixed(trailing), spacing: spacing) }
            }
        }
        #endif
        return EvenColumns.items(count, spacing: spacing)
    }
}

extension EnvironmentValues {
    @Entry var reservedRegions = ReservedRegions()
    /// The window's status stands in a top corner (`ReservedRegions.statusInCorner`: the open Duo upright), worked out once
    /// at the root (`StatusCornerEnvironment`), so the tab roots that give the top bar's row its room read one value that
    /// almost never changes rather than the window's geometry (#516).
    @Entry var statusInCorner = false
}

/// Puts `statusInCorner` into the environment from the window's regions and width.
struct StatusCornerEnvironment: ViewModifier {
    @Environment(\.reservedRegions) private var regions
    @Environment(\.windowGeometry) private var windowGeometry
    func body(content: Content) -> some View {
        content.environment(\.statusInCorner, regions.statusInCorner(width: windowGeometry.bounds.width))
    }
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
                let all = proxy.reservedRegions(kind: .division, options: .includeInactive).map { (ReservedRegions.Reported.Kind.fold, $0) }
                    + proxy.reservedRegions(kind: .occlusion, options: .includeInactive).map { (ReservedRegions.Reported.Kind.occlusion, $0) }
                let regions = ReservedRegions(
                    divisions: proxy.reservedRegions(kind: .division).filter(\.isActive).map { $0.frame.offsetBy(dx: origin.x, dy: origin.y) },
                    occlusions: proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map { $0.frame.offsetBy(dx: origin.x, dy: origin.y) },
                    upFold: ReservedRegions.upFold(proxy.reservedRegions(kind: .division, options: .includeInactive).map(\.frame), in: proxy.size)?
                        .offsetBy(dx: origin.x, dy: origin.y),
                    reported: all.map { .init(kind: $0.0, frame: $0.1.frame.offsetBy(dx: origin.x, dy: origin.y), active: $0.1.isActive) })
                content().environment(\.reservedRegions, regions)
            }
        }
    }
    #endif
}
