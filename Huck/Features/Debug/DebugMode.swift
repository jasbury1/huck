//
//  DebugMode.swift
//  Huck
//
//  Created by James Asbury on 10/3/26.
//

import Foundation

/// Developer-only tooling: whether it's offered, and where the switch is stored.
///
/// Fixed at build time, so readable from any isolation domain — `PostingMode`
/// reads it off the main actor.
nonisolated enum DebugMode {
    /// `@AppStorage` key for the Settings toggle.
    static let enabledKey = "debug.enabled"

    /// Whether the debug mode toggle, and the Dry Run settings beside it, are
    /// offered. Debug builds only, so a release build has no developer tooling
    /// for anyone — and no hidden features for App Review to question.
    static var isAvailable: Bool {
        BuildConfiguration.isDebugBuild
    }
}
