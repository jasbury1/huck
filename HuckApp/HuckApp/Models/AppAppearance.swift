//
//  AppAppearance.swift
//  HuckApp
//
//  Created by James Asbury on 9/23/26.
//

import SwiftUI

/// Whether the app follows the system's light/dark setting or overrides it.
///
/// Raw values are spelled out rather than left implicit because they're what
/// gets written to `UserDefaults`: renaming a case would silently strand a
/// choice someone had already made.
enum AppAppearance: String, CaseIterable, Identifiable {
    /// Follow the system — the default, and what most people want.
    case system = "system"
    case light = "light"
    case dark = "dark"

    /// The `@AppStorage` key, shared by the Settings picker and the root that
    /// applies the choice so the two can't drift onto different identifiers.
    /// Mirrors how `FeedSettings` holds its own keys.
    static let storageKey = "appearance.colorScheme"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// What to hand `preferredColorScheme`. `nil` is how SwiftUI spells
    /// "state no preference", which is precisely deferring to the system —
    /// so `.system` needs no special handling at the call site.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
