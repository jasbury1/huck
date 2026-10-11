//
//  ReadableContentWidth.swift
//  HuckApp
//
//  Created by James Asbury on 10/11/26.
//

import SwiftUI

/// Caps content at a comfortable reading width, centered in whatever space is
/// left — SwiftUI's counterpart to UIKit's `readableContentGuide`. On iPhone the
/// cap is wider than the screen, so nothing changes; on an unfolded iPhone Duo,
/// iPad, or a wide window it keeps lines from running edge to edge.
private struct ReadableContentWidthModifier: ViewModifier {
    /// About UIKit's readable width at the default text size, scaled with
    /// Dynamic Type so larger text keeps roughly the same words per line.
    @ScaledMetric(relativeTo: .body) private var maxWidth: CGFloat = 672

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Limits this view to a readable line length, centered horizontally.
    func readableContentWidth() -> some View {
        modifier(ReadableContentWidthModifier())
    }
}
