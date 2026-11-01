//
//  ThumbnailPosition.swift
//  HuckApp
//
//  Created by James Asbury on 10/11/26.
//

import SwiftUI

/// Which side of a story row its thumbnail sits on, chosen in Settings.
///
/// Raw values are spelled out rather than left implicit because they're what
/// gets written to `UserDefaults`, as with `AppAppearance`.
enum ThumbnailPosition: String, CaseIterable, Identifiable {
    /// Left on a window shaped wider than an iPhone's — an iPhone Duo, open or
    /// closed — and right otherwise. The default.
    case automatic = "auto"
    case left = "left"
    case right = "right"

    /// The `@AppStorage` key, shared by the Settings picker and the root that
    /// applies the choice.
    static let storageKey = "feed.thumbnailPosition"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .automatic: "Auto"
        case .left: "Left"
        case .right: "Right"
        }
    }

    var systemImage: String {
        switch self {
        // Both halves outlined, neither filled: either side, decided for it.
        case .automatic: "rectangle.split.2x1"
        case .left: "rectangle.lefthalf.filled"
        case .right: "rectangle.righthalf.filled"
        }
    }

    /// The story row layout this choice gives in a window of `windowSize`.
    func storyRowLayout(windowSize: CGSize) -> StoryRowLayout {
        switch self {
        case .automatic: StoryRowLayout(windowSize: windowSize)
        case .left: .wide
        case .right: .standard
        }
    }
}
