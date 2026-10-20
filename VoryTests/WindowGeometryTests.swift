import CoreGraphics
import Testing
@testable import Vory

/// The window's geometry replaces every read of the main screen and the key window (1.5, iPad
/// and the Duo): the rules that decide what counts as a keyboard, how far the dock moves, how
/// much the tab bar reserves, and how a grid splits on a wide layout.
@Suite struct WindowGeometryTests {
    let window = CGRect(x: 0, y: 0, width: 393, height: 852)

    @Test func aKeyboardOnTheBottomEdgeCounts() {
        let kb = CGRect(x: 0, y: 852 - 336, width: 393, height: 336)
        #expect(WindowGeometry.keyboardRect(window: window, end: kb) == kb)
        #expect(abs(WindowGeometry.keyboardOverlap(window: window, keyboard: kb, safeBottom: 34) - 302) < 0.001)
    }

    @Test func aHiddenKeyboardIsBelowTheWindowAndDoesNotCount() {
        let kb = CGRect(x: 0, y: 852, width: 393, height: 336)
        #expect(WindowGeometry.keyboardRect(window: window, end: kb).isNull)
        #expect(WindowGeometry.keyboardOverlap(window: window, keyboard: .null, safeBottom: 34) == 0)
    }

    @Test func aFloatingKeyboardAwayFromTheBottomEdgeDoesNotCount() {
        let kb = CGRect(x: 40, y: 300, width: 320, height: 260)
        #expect(WindowGeometry.keyboardRect(window: window, end: kb).isNull)
    }

    @Test func aWholeWindowRectIsNotAKeyboard() {
        #expect(WindowGeometry.keyboardRect(window: window, end: window).isNull)
    }

    @Test func theOverlapNeverExceedsMostOfTheWindow() {
        let kb = CGRect(x: 0, y: 852 - 560, width: 393, height: 560)
        #expect(abs(WindowGeometry.keyboardOverlap(window: window, keyboard: kb, safeBottom: 0) - 852 * 0.6) < 0.001)
    }

    @Test func aSplitWindowMeasuresItsOwnBottomEdge() {
        // Half of a 951 x 669 inner display: the window's own bounds, not the screen's.
        let half = CGRect(x: 0, y: 0, width: 475, height: 669)
        let kb = CGRect(x: 0, y: 669 - 300, width: 475, height: 300)
        #expect(abs(WindowGeometry.keyboardOverlap(window: half, keyboard: kb, safeBottom: 20) - 280) < 0.001)
    }

    #if os(iOS)
    @Test func theTabBarReservesLessOnAHomeButtonPhone() {
        // With a home indicator the capsule hangs 13 pt into its area; without one it cannot hang,
        // so the bar keeps those 13 pt as a gap above the window's edge instead.
        #expect(abs(VoryTabBar.reservedHeight(safeBottom: 34) - 43) < 0.001)
        #expect(abs(VoryTabBar.reservedHeight(safeBottom: 0) - 69) < 0.001)
        #expect(VoryTabBar.overhang(safeBottom: 8) == 8)
    }
    #endif

    @Test func wideGridsGetAnEvenColumnCount() {
        #expect(EvenColumns.count(width: 720, minimum: 150, spacing: 18) == 4)
        #expect(EvenColumns.count(width: 520, minimum: 150, spacing: 18) == 2)   // three fit; two keeps it even
        #expect(EvenColumns.count(width: 951, minimum: 150, spacing: 18) == 4)   // five fit
        #expect(EvenColumns.count(width: 0, minimum: 150, spacing: 18) == 2)
    }

    /// A keyboard frame is forgotten when the window changes size (a turn), kept while it stays:
    /// the open Duo's bar stayed hidden behind a keyboard the turn had taken away.
    @Test func aKeyboardFrameDoesNotOutliveTheWindowsSize() {
        #expect(WindowGeometry.keyboardCarriesOver(from: .zero, to: CGSize(width: 669, height: 951)))
        #expect(WindowGeometry.keyboardCarriesOver(from: CGSize(width: 669, height: 951), to: CGSize(width: 669, height: 951)))
        #expect(!WindowGeometry.keyboardCarriesOver(from: CGSize(width: 669, height: 951), to: CGSize(width: 951, height: 669)))
    }

    /// #340: the floating top bar's row gets room only where the system's bars stand in a side strip (the closed Duo)
    /// and the bar is up; the row's bottom (in the bar's space) plus the bar's top padding and a gap.
    @Test func theTopBarsRowGetsRoomOnlyBesideASideStrip() {
        #expect(TopBarRoom.inset(barsVertical: true, barOn: true, rowBottom: 44) == 56)
        #expect(TopBarRoom.inset(barsVertical: true, barOn: true, rowBottom: 41.3) == 53)
        // Along the bottom (any phone, the open Duo upright), the system keeps its band: no room.
        #expect(TopBarRoom.inset(barsVertical: false, barOn: true, rowBottom: 44) == 0)
        // No bar (a wide window: two columns and the system's own bar).
        #expect(TopBarRoom.inset(barsVertical: true, barOn: false, rowBottom: 44) == 0)
        // Not measured yet.
        #expect(TopBarRoom.inset(barsVertical: true, barOn: true, rowBottom: 0) == 0)
    }
}
