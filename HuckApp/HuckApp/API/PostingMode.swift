//
//  PostingMode.swift
//  HuckApp
//
//  Created by James Asbury on 11/1/26.
//

import Foundation

/// Whether writes to Hacker News — comments, posts, deletions — are really
/// sent, for testing the app against a real account without publishing
/// anything.
///
/// In a dry run, `NewsYCService` withholds each write and answers it itself the
/// way Hacker News would, so the rest of the app runs exactly as it would after
/// a real write: as accepted, or, with `simulatesFailure`, as refused.
///
/// Read from the API layer, which has no view to hold `@AppStorage`, so the
/// settings are read from `UserDefaults` directly; Settings writes them through
/// the same keys.
nonisolated enum PostingMode {
    /// `@AppStorage` key for the Dry Run setting.
    static let dryRunKey = "debug.postingDryRun"
    /// `@AppStorage` key for the Simulate Failure setting.
    static let simulatesFailureKey = "debug.postingSimulatesFailure"

    /// Whether writes are withheld: always in a build with posting disabled
    /// (`HUCK_DISABLE_POSTING`), and otherwise when Dry Run is on.
    static var isDryRun: Bool {
        isDryRun(dryRunSetting: UserDefaults.standard.bool(forKey: dryRunKey))
    }

    /// Whether a dry run answers writes as Hacker News refusing them, to try
    /// out the app's error handling. Has no effect on writes that are sent.
    static var simulatesFailure: Bool {
        isDryRun && UserDefaults.standard.bool(forKey: simulatesFailureKey)
    }

    /// `isDryRun` for a given value of the Dry Run setting — for views, which
    /// read the setting through `@AppStorage` so they update as it changes.
    static func isDryRun(dryRunSetting: Bool) -> Bool {
        BuildConfiguration.isPostingDisabled || dryRunSetting
    }
}
