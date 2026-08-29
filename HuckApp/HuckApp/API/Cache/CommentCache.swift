//
//  CommentCache.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import Foundation

/// Caches fully-loaded comment threads by story id, behind the API facade.
///
/// Its job is to keep re-opening a post (e.g. tapping back into it) from re-fetching a
/// thread we just built, which would abuse the APIs for no benefit. Unlike `StoryCache`,
/// entries carry a short **time-to-live**: comment threads change as replies arrive, and
/// the whole point of the Algolia/Firebase machinery is freshness, so a stale thread is
/// only worth serving for a few minutes before we re-fetch.
///
/// `CommentCache` is an internal detail of the API layer — callers reach it only through
/// `HackerNewsAPI.streamComments(for:)`, never directly.
actor CommentCache {
    static let shared = CommentCache()

    /// How long a cached thread is served before it's considered stale and re-fetched.
    private let timeToLive: TimeInterval = 5 * 60

    private let cache = LRUCache<Int, Entry>(capacity: 50)

    private init() {}

    private struct Entry {
        let thread: [Comment]
        let storedAt: Date
    }

    /// The cached thread for a story, or `nil` if absent or past its time-to-live.
    func thread(for id: Int) async -> [Comment]? {
        guard let entry = await cache.cachedValue(for: id) else { return nil }
        guard Date.now.timeIntervalSince(entry.storedAt) < timeToLive else { return nil }
        return entry.thread
    }

    /// Stores a freshly-loaded thread, stamped with the current time.
    func store(_ thread: [Comment], for id: Int) async {
        await cache.insert(Entry(thread: thread, storedAt: .now), for: id)
    }
}
