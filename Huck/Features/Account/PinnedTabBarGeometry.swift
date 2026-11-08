//
//  PinnedTabBarGeometry.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

import SwiftUI

/// The arithmetic behind `UserView`'s pinned tab bar and its per-tab scroll
/// positions, kept apart from the view so it can be tested.
///
/// Everything is measured in the scroll content's own coordinate space, where
/// the only thing that moves is the pinned tab bar: it rests directly below
/// the profile header and, once pinned, is pushed down to stay under the
/// navigation bar.
enum PinnedTabBarGeometry {
    /// How far the list has scrolled under the pinned tab bar, or `nil` while
    /// the bar rests below the header (or before the header is measured).
    ///
    /// Exactly at the pin point, resting and pinned look the same, so it
    /// counts as resting; `fallbackScrollY` lands just past it for that reason.
    static func pinnedListOffset(tabBarMinY: CGFloat, headerHeight: CGFloat) -> CGFloat? {
        guard headerHeight > 0 else { return nil }
        let pushed = tabBarMinY - headerHeight
        // Half a point of slack for rounding in the layout.
        return pushed > 0.5 ? pushed : nil
    }

    /// The anchor that scrolls a row of `rowHeight` back so its top sits
    /// `rowTop` below the top of a visible region `visibleHeight` tall, or
    /// `nil` if the row doesn't fit in the region.
    ///
    /// Scrolling to a row lines up the row's anchor point with the same point
    /// of the visible region, so anchor y = a puts the row's top
    /// a · (visibleHeight − rowHeight) below the region's top.
    static func restoreAnchor(rowTop: CGFloat, rowHeight: CGFloat, visibleHeight: CGFloat) -> UnitPoint? {
        guard visibleHeight > rowHeight else { return nil }
        return UnitPoint(x: 0.5, y: rowTop / (visibleHeight - rowHeight))
    }

    /// The content offset that keeps the tab bar pinned with its list
    /// scrolled `listOffset` beneath it — at least a point past the pin
    /// point, where the bar would otherwise read as resting.
    static func fallbackScrollY(headerHeight: CGFloat, listOffset: CGFloat?) -> CGFloat {
        headerHeight + max(1, listOffset ?? 0)
    }
}
