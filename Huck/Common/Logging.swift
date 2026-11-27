//
//  Logging.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

import Foundation
import OSLog

/// The app's log categories, one per area, all under the app's subsystem.
///
/// Every log line goes through one of these rather than `print`, so it lands in
/// the unified log: filterable by category in Xcode's console and Console.app,
/// kept on device after the fact, and redacted where it should be. To follow one
/// area, filter by `subsystem:<bundle id> category:<name>`.
///
/// Levels follow Apple's guidance — `debug` for detail only worth seeing live,
/// `info` for the normal course of events, `notice` for things worth keeping,
/// `error` for failures, `fault` for states that mean the app has a bug.
/// Interpolated values are private unless marked `privacy: .public`; only ids,
/// counts, paths and statuses are ever marked so. Credentials, tokens, and what
/// someone typed never are, and are best left out entirely.
nonisolated extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Huck"

    /// Requests that failed in transit, non-2xx JSON responses, and responses
    /// that didn't decode — the last usually meaning an upstream schema change.
    static let network = Logger(subsystem: subsystem, category: "Network")

    /// Which source a story's comments came from, and why.
    static let commentFetch = Logger(subsystem: subsystem, category: "CommentFetch")

    /// One line per Algolia search sent, to audit what the hourly allowance is
    /// actually being spent on — the debouncing and result reuse upstream are
    /// only as good as this is quiet. The query text is deliberately absent:
    /// it's what someone typed.
    static let algoliaSearch = Logger(subsystem: subsystem, category: "AlgoliaSearch")

    /// Reading and writing `news.ycombinator.com`'s HTML: pages that couldn't be
    /// fetched, tokens and forms that couldn't be found, and writes HN refused.
    /// A markup change upstream shows up here first.
    static let scraping = Logger(subsystem: subsystem, category: "Scraping")

    /// Signing in and out, and actions attempted without a session.
    static let auth = Logger(subsystem: subsystem, category: "Auth")

    /// Posting comments and stories, and recovering the ids HN assigned them.
    static let posting = Logger(subsystem: subsystem, category: "Posting")

    /// Votes and favorites, and reconciling them with the reader's lists on HN.
    static let interactions = Logger(subsystem: subsystem, category: "Interactions")

    /// The app's own files in Application Support.
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")

    /// Mirroring collections to iCloud.
    static let cloudSync = Logger(subsystem: subsystem, category: "CloudSync")

    /// Crash, hang, and performance reports delivered by MetricKit.
    static let diagnostics = Logger(subsystem: subsystem, category: "Diagnostics")

    /// Window and layout changes.
    static let layout = Logger(subsystem: subsystem, category: "Layout")

    /// Fixture replay and recording, in debug builds.
    static let fixtures = Logger(subsystem: subsystem, category: "Fixtures")
}
