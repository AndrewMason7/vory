import CoreGraphics
import Testing
@testable import Vory

/// The fold of a half-open iPhone Duo (Duo stage 2): how far the composer's lists may grow under
/// a fold across the window, when the dock lifts over it, where the list column ends at a fold
/// up the window, how a floating piece steps off the fold, and Home's tiles on a window that folds.
/// Window space throughout: the open Duo's 669 x 951 window upright (the laptop pose folds it
/// across) and 951 x 669 on its side (the book pose folds it up the middle).
/// Expected values are typed CGFloat: an untyped sum on the right of `#expect`'s `==` is an Int
/// there, and 206.0 against 206 compared false.
@Suite struct FoldLayoutTests {
    /// A fold across the window (laptop): a 20 pt band at y 466 to 486.
    let laptop = ReservedRegions(divisions: [CGRect(x: 0, y: 466, width: 669, height: 20)])
    /// A fold up the window (book): a 20 pt band at x 466 to 486.
    let book = ReservedRegions(divisions: [CGRect(x: 466, y: 0, width: 20, height: 669)])
    let none = ReservedRegions()

    // MARK: The room under a fold

    @Test func underAFoldAcrossTheWindowAListMayGrowUpToTheFoldLessTheMargin() {
        #expect(laptop.room(under: 700) == CGFloat(700 - 486 - 8))
    }

    @Test func noFloorCrossesTheFold() {
        // The 10-12 round: the + panel took its 180 pt floor with about 60 pt of room and opened
        // across the fold. Room under the fold is what is there, down to none at all.
        #expect(laptop.room(under: 554) == 60)
        #expect(laptop.room(under: 490) == 0)
    }

    @Test func noRoomLimitAboveTheFoldOrWithoutOne() {
        #expect(laptop.room(under: 300) == nil)
        #expect(book.room(under: 700) == nil)
        #expect(none.room(under: 700) == nil)
    }

    // MARK: The dock's lift

    /// A 70 pt dock with its bottom edge at `bottom`.
    func dock(bottom: CGFloat) -> CGRect { CGRect(x: 0, y: bottom - 70, width: 669, height: 70) }

    @Test func aDockOnTheFoldLiftsToTheMarginAboveIt() {
        // The keyboard has pushed the dock onto the fold: its bottom ends 8 pt above the fold.
        let lift = laptop.dockLift(dock: dock(bottom: 520))
        #expect(lift == CGFloat(520 - 466 + 8))
        #expect(dock(bottom: 520).maxY - lift == CGFloat(466 - 8))
    }

    @Test func aDockJustAboveTheFoldMovesUpToTheMargin() {
        #expect(laptop.dockLift(dock: dock(bottom: 462)) == 4)
        #expect(laptop.dockLift(dock: dock(bottom: 458)) == 0)
    }

    @Test func aDockUnderTheFoldStaysWithNoListOpen() {
        #expect(laptop.dockLift(dock: dock(bottom: 917)) == 0)
    }

    @Test func aListThatFitsUnderTheFoldLeavesTheDockWhereItIs() {
        // The "/" list's top at 600: well under the fold's 486 plus the margin.
        #expect(laptop.dockLift(dock: dock(bottom: 917), listTop: 600) == 0)
    }

    @Test func aListThatWouldCrossTheFoldLiftsTheDockOverIt() {
        // The + panel at full size would reach up to y 400, across the fold: the dock goes over
        // the fold (its bottom 8 pt above it) while the panel is open.
        let lift = laptop.dockLift(dock: dock(bottom: 917), listTop: 400)
        #expect(lift == CGFloat(917 - 466 + 8))
        // Its top reaching to the margin under the fold is already too far.
        #expect(laptop.dockLift(dock: dock(bottom: 917), listTop: 493) > 0)
        #expect(laptop.dockLift(dock: dock(bottom: 917), listTop: 494) == 0)
    }

    @Test func aLiftForAnOpenListHoldsUntilTheListCloses() {
        // Lifted, the list gets the whole room above and reports a different reach: held, the
        // dock stays up rather than dropping back under it.
        #expect(laptop.dockLift(dock: dock(bottom: 917), listTop: 600, held: true) == CGFloat(917 - 466 + 8))
        // Closed (no list), the hold no longer counts.
        #expect(laptop.dockLift(dock: dock(bottom: 917), listTop: nil, held: true) == 0)
    }

    @Test func aDockAboveTheFoldNeverMovesForAList() {
        #expect(laptop.dockLift(dock: dock(bottom: 400), listTop: 100) == 0)
        #expect(laptop.dockLift(dock: dock(bottom: 400), listTop: 100, held: true) == 0)
    }

    @Test func noFoldAcrossTheWindowNoLift() {
        #expect(book.dockLift(dock: dock(bottom: 520), listTop: 100) == 0)
        #expect(none.dockLift(dock: dock(bottom: 520), listTop: 100) == 0)
        #expect(laptop.dockLift(dock: .zero) == 0)
    }

    // MARK: The list column at a fold up the window

    @Test func theListColumnEndsAtTheFoldsMiddle() {
        #expect(book.listWidth(leading: 0, range: 280...480) == 476)
        // A bar down the leading side moves the split view in: the column is narrower.
        #expect(book.listWidth(leading: 84, range: 280...480) == 392)
    }

    @Test func aFoldOutsideTheColumnsRangeLeavesTheUsualWidth() {
        let early = ReservedRegions(divisions: [CGRect(x: 200, y: 0, width: 20, height: 669)])
        #expect(early.listWidth(leading: 0, range: 280...480) == nil)
        let late = ReservedRegions(divisions: [CGRect(x: 600, y: 0, width: 20, height: 669)])
        #expect(late.listWidth(leading: 0, range: 280...480) == nil)
    }

    @Test func noFoldUpTheWindowNoListWidth() {
        #expect(laptop.listWidth(leading: 0, range: 280...480) == nil)
        #expect(none.listWidth(leading: 0, range: 280...480) == nil)
    }

    // MARK: Stepping off the fold

    @Test func aPieceClearOfTheFoldStaysPut() {
        let fold = CGRect(x: 466, y: 0, width: 20, height: 669)
        #expect(FoldAvoidance.offset(for: CGRect(x: 100, y: 10, width: 200, height: 40), fold: fold, in: 951) == 0)
        #expect(FoldAvoidance.offset(for: CGRect(x: 380, y: 10, width: 200, height: 40), fold: nil, in: 951) == 0)
    }

    @Test func aPieceOnTheFoldStepsToTheRoomierSide() {
        // More room to the right of the fold: the piece's leading edge goes to the fold's far edge.
        let right = CGRect(x: 400, y: 0, width: 20, height: 669)
        #expect(FoldAvoidance.offset(for: CGRect(x: 380, y: 10, width: 200, height: 40), fold: right, in: 951) == CGFloat(420 - 380))
        // More room to the left: the piece's trailing edge goes to the fold's near edge.
        let left = CGRect(x: 600, y: 0, width: 20, height: 669)
        #expect(FoldAvoidance.offset(for: CGRect(x: 500, y: 10, width: 200, height: 40), fold: left, in: 951) == CGFloat(600 - 700))
    }

    // MARK: Home's tiles

    @Test func homesTilesGoTwoToARowOnAWindowThatCanFold() {
        // The open Duo flat (an inactive division) and in either half-open pose: two to a row. The Mac (this suite
        // runs there too) keeps three whatever it is handed.
        #if os(macOS)
        let folding = 3
        #else
        let folding = 2
        #endif
        #expect(HomeTiles.columns(regions: ReservedRegions(foldable: true)) == folding)
        #expect(HomeTiles.columns(regions: book) == folding)
        var laptopOpen = laptop; laptopOpen.foldable = true
        #expect(HomeTiles.columns(regions: laptopOpen) == folding)
    }

    @Test func homesTilesStayThreeToARowOnAnIPad() {
        // A wide window with no fold (an iPad) and a phone: unchanged.
        #expect(HomeTiles.columns(regions: none) == 3)
    }
}
