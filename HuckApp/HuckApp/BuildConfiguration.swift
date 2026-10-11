//
//  BuildConfiguration.swift
//  HuckApp
//
//  Created by James Asbury on 10/11/26.
//

import Foundation

/// Everything fixed when the app is built, as set in `Config/*.xcconfig`. The
/// app's one reader of build configuration: nothing else checks a compilation
/// condition or a build-time Info.plist key directly, so every switch is listed
/// here, with a type and a doc comment.
///
/// To add a switch, declare it in `Base.xcconfig` (which explains how), then
/// expose it here:
/// - an on/off feature, as a `Bool` set from a compilation condition with `#if`;
/// - a typed value (string, number, URL), read from the Info.plist key the
///   xcconfig passes it through.
///
/// These are about how the app was *built*. Choices the user makes belong in
/// `@AppStorage`, not here.
enum BuildConfiguration {
    /// Whether this is a debug build — Xcode's Debug configuration.
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// Whether collections sync through iCloud. Set by `HUCK_ICLOUD_SYNC`, which
    /// also adds the iCloud entitlement, so the two can't get out of step. Off by
    /// default because a Personal Team can't provision iCloud; turn it on in
    /// `Local.xcconfig` when signing with a paid team.
    #if ICLOUD_SYNC
    static let isCloudSyncEnabled = true
    #else
    static let isCloudSyncEnabled = false
    #endif
}
