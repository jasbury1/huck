//
//  LaunchConfiguration.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

import Foundation
import OSLog

/// How this launch was asked to run, from its launch arguments — the app's
/// one reader of them. UI tests and recording sessions set these; an ordinary
/// launch has none, and gets the real Hacker News.
///
/// Debug builds only: in a Release build every launch is ordinary, whatever
/// its arguments, and the fixtures aren't in the bundle to begin with.
enum LaunchConfiguration {
    /// Serve every request from the fixtures bundled into debug builds, so
    /// nothing touches the network. For UI tests and offline development.
    static let fixturesArgument = "-HuckFixtures"
    /// Use the real network, saving each anonymous read as a fixture. See
    /// `RecordingTransport`.
    static let recordFixturesArgument = "-HuckRecordFixtures"

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Huck", category: "Fixtures")

    /// The Hacker News this launch talks to.
    static func makeHackerNews(arguments: [String] = ProcessInfo.processInfo.arguments) -> any HackerNewsService {
        #if DEBUG
        if arguments.contains(fixturesArgument) {
            guard let store = FixtureStore.bundled else {
                fatalError("\(fixturesArgument) was passed, but this build has no Fixtures.bundle.")
            }
            log.notice("Serving \(store.count, privacy: .public) recorded responses; nothing goes to the network")
            return HackerNewsAPI(transport: FixtureTransport(store: store))
        }
        if arguments.contains(recordFixturesArgument) {
            // Each session records from scratch, so the fixtures are one
            // consistent snapshot of Hacker News rather than a mix of moments.
            try? FileManager.default.removeItem(at: FixtureRecorder.defaultDirectory)
            let recorder = FixtureRecorder(directory: FixtureRecorder.defaultDirectory)
            return HackerNewsAPI(transport: RecordingTransport(recorder: recorder))
        }
        #endif
        return HackerNewsAPI.live
    }
}
