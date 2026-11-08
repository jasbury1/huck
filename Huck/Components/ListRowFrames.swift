//
//  ListRowFrames.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

import SwiftUI

/// Where a lazy list's rows currently sit, for a scroll view that restores a
/// position by row rather than by offset.
///
/// A lazy list that's rebuilt — as `UserView`'s tabs are on every switch —
/// estimates the heights of the rows it hasn't laid out yet, so a saved scroll
/// offset lands on different rows from the ones it was taken at. A row's
/// identity survives the rebuild, so knowing which row sat where is what lets
/// a position be put back exactly.
///
/// Rows report in only while one of these is in the environment; elsewhere the
/// lists skip the measuring. Deliberately not observable: the frames change on
/// every frame of a scroll and are read only on demand, so nothing should
/// re-render when they do.
final class ListRowFrames {
    /// A laid-out row: its identity, and its frame in `space`.
    struct Row {
        let id: any Hashable & Sendable
        let frame: CGRect
    }

    /// The coordinate space the rows report their frames in.
    let space: NamedCoordinateSpace
    private var rows: [AnyHashable: Row] = [:]

    init(space: NamedCoordinateSpace) {
        self.space = space
    }

    /// The first laid-out row that starts at or below `y`, if any.
    func firstRow(startingAtOrBelow y: CGFloat) -> Row? {
        rows.values
            .filter { $0.frame.minY >= y }
            .min { $0.frame.minY < $1.frame.minY }
    }

    /// Records where row `id` sits, or that it's no longer laid out (`nil`).
    func update(_ id: some Hashable & Sendable, frame: CGRect?) {
        rows[AnyHashable(id)] = frame.map { Row(id: id, frame: $0) }
    }
}

extension EnvironmentValues {
    /// Collects the frames of list rows laid out beneath it; `nil` (the
    /// default) leaves rows unmeasured.
    @Entry var listRowFrames: ListRowFrames?
}

extension View {
    /// Reports this list row's frame to the environment's `ListRowFrames`, if
    /// there is one.
    func reportsListRowFrame(id: some Hashable & Sendable) -> some View {
        modifier(ListRowFrameReporting(id: id))
    }
}

private struct ListRowFrameReporting<ID: Hashable & Sendable>: ViewModifier {
    let id: ID
    @Environment(\.listRowFrames) private var rowFrames

    func body(content: Content) -> some View {
        if let rowFrames {
            let space = rowFrames.space
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: space) } action: {
                    rowFrames.update(id, frame: $0)
                }
                // A row the list has let go of no longer sits anywhere.
                .onDisappear { rowFrames.update(id, frame: nil) }
        } else {
            content
        }
    }
}
