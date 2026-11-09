//
//  PinnedTabBarGeometryTests.swift
//  HuckTests
//

@testable import Huck
import SwiftUI
import Testing

struct PinnedTabBarGeometryTests {
    // MARK: Pinning

    @Test func restingBarIsNotPinned() {
        // Resting, the bar's top is exactly the header's height.
        #expect(PinnedTabBarGeometry.pinnedListOffset(tabBarMinY: 155, headerHeight: 155) == nil)
    }

    @Test func roundingAtThePinPointIsNotPinned() {
        #expect(PinnedTabBarGeometry.pinnedListOffset(tabBarMinY: 155.4, headerHeight: 155) == nil)
    }

    @Test func pushedBarReportsHowFarTheListScrolled() {
        #expect(PinnedTabBarGeometry.pinnedListOffset(tabBarMinY: 1536, headerHeight: 155) == 1381)
    }

    @Test func unmeasuredHeaderIsNeverPinned() {
        #expect(PinnedTabBarGeometry.pinnedListOffset(tabBarMinY: 500, headerHeight: 0) == nil)
    }

    // MARK: Restoring by row

    /// Where a row's top lands when scrolled to with `anchor`: its anchor
    /// point meets the same point of the visible region.
    private func landedTop(anchor: CGFloat, rowHeight: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        anchor * visibleHeight - anchor * rowHeight
    }

    @Test(arguments: [
        (0.0, 114.0, 736.0),
        (9.67, 114.0, 757.0),
        (149.67, 156.33, 757.0),
        (300.0, 400.0, 736.0),
    ])
    func anchorPutsTheRowBackWhereItWas(rowTop: CGFloat, rowHeight: CGFloat, visibleHeight: CGFloat) throws {
        let anchor = try #require(PinnedTabBarGeometry.restoreAnchor(
            rowTop: rowTop, rowHeight: rowHeight, visibleHeight: visibleHeight
        ))
        let top = landedTop(anchor: anchor.y, rowHeight: rowHeight, visibleHeight: visibleHeight)
        #expect(abs(top - rowTop) < 0.001)
    }

    @Test func rowTallerThanTheScreenHasNoAnchor() {
        #expect(PinnedTabBarGeometry.restoreAnchor(rowTop: 10, rowHeight: 800, visibleHeight: 736) == nil)
        #expect(PinnedTabBarGeometry.restoreAnchor(rowTop: 10, rowHeight: 736, visibleHeight: 736) == nil)
    }

    // MARK: Restoring by offset

    @Test func neverScrolledTabLandsJustPastThePinPoint() {
        // Exactly at the pin point the bar would read as resting and unpin.
        let y = PinnedTabBarGeometry.fallbackScrollY(headerHeight: 155, listOffset: nil)
        #expect(y == 156)
        #expect(PinnedTabBarGeometry.pinnedListOffset(tabBarMinY: y, headerHeight: 155) != nil)
    }

    @Test func scrolledTabLandsAtItsOffset() {
        #expect(PinnedTabBarGeometry.fallbackScrollY(headerHeight: 155, listOffset: 1381) == 1536)
    }
}
