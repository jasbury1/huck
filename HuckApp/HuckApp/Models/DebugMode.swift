//
//  DebugMode.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import Foundation

/// Developer-only tooling: who may turn it on, and where the switch is stored.
enum DebugMode {
    /// `@AppStorage` key for the Settings toggle.
    static let enabledKey = "debug.enabled"

    /// The Hacker News account allowed to use debug mode in release builds.
    private static let developerUsername = "jasbury"

    /// Whether the debug mode toggle is offered. Always in debug builds, so it
    /// can be used signed out or on a test account; in release builds, only to
    /// the developer's account.
    static func isAvailable(for username: String?) -> Bool {
        #if DEBUG
        true
        #else
        username == developerUsername
        #endif
    }
}
