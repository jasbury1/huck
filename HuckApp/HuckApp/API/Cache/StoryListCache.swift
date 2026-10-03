//
//  StoryListCache.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import Foundation

/// Caches the ranked id lists behind the main feeds (Top, Best, New, …), behind
/// the API facade.
///
/// Opening a feed starts from its list, so caching stories alone isn't enough
/// for a feed to appear instantly: without this, every open would wait on a
/// Firebase round trip before a single row could draw. The launch warm-up
/// fills it, so the feeds it covers open with no request at all.
///
/// The time-to-live is short because these lists are why the feeds use
/// Firebase — rankings move by the minute. Pull-to-refresh bypasses it
/// (see `refresh(_:)`).
actor StoryListCache {
    static let shared = StoryListCache()

    private let timeToLive: TimeInterval = 2 * 60

    private struct Entry {
        let ids: [Int]
        let fetchedAt: Date
    }
    private var entries: [StoryFilter: Entry] = [:]
    /// Fetches in progress, so a feed opened mid-warm-up shares its request.
    private var inFlight: [StoryFilter: Task<[Int], Never>] = [:]

    private init() {}

    /// The feed's ids, from memory when fresh, otherwise fetched.
    func ids(for filter: StoryFilter) async -> [Int] {
        if let entry = entries[filter],
           Date.now.timeIntervalSince(entry.fetchedAt) < timeToLive {
            return entry.ids
        }
        return await fetch(filter)
    }

    /// Fetches the feed's current ranking regardless of age. If the fetch
    /// fails, the list already held is returned, so a failed pull-to-refresh
    /// leaves the feed as it was rather than blank.
    func refresh(_ filter: StoryFilter) async -> [Int] {
        await fetch(filter)
    }

    private func fetch(_ filter: StoryFilter) async -> [Int] {
        if let existing = inFlight[filter] { return await existing.value }

        let task = Task { await FirebaseAPIService.getStoryIdsAsync(filter: filter) }
        inFlight[filter] = task
        let ids = await task.value
        inFlight[filter] = nil
        // An empty list is a failed fetch (every feed has stories); keep
        // whatever was held before rather than caching the failure.
        guard !ids.isEmpty else { return entries[filter]?.ids ?? [] }
        entries[filter] = Entry(ids: ids, fetchedAt: .now)
        return ids
    }
}
