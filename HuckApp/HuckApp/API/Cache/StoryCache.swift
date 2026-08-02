//
//  StoryCache.swift
//  HuckApp
//
//  Created by James Asbury on 12/24/25.
//

import Foundation

/// A thread-safe, in-memory cache of stories, keyed by id.
///
/// `StoryCache` is an internal detail of the API layer — callers reach it only
/// through `HackerNewsAPI` (`getStory` / `prefetchStories`), never directly.
///
/// Being an `actor` isolates its mutable state so concurrent readers (many
/// story cells fetching at once) can never race on the underlying storage.
/// It provides three efficiency behaviours:
///  - **Request coalescing:** concurrent requests for the same id share a single
///    network fetch (tracked in `inFlight`).
///  - **Bounded prefetch:** `prefetch(ids:)` warms the cache in parallel with a
///    capped number of concurrent fetches, so we load ahead without abusing the API.
///  - **LRU eviction:** the cache is bounded to `capacity` entries; the least
///    recently used story is dropped when it overflows.
actor StoryCache {
    static let shared = StoryCache()

    /// Completed story values.
    private var entries: [Int: FirebaseStoryData] = [:]
    /// Recency order for `entries`; most-recently-used id is last.
    /// TODO: Make a proper linked list LRU implementation once the project is mature enough to start tackling performance optimization...
    private var lru: [Int] = []
    /// In-progress fetches, so concurrent requests for one id are coalesced.
    private var inFlight: [Int: Task<FirebaseStoryData?, Never>] = [:]

    /// Maximum number of completed entries to retain.
    private let capacity = 200
    /// Maximum number of concurrent fetches during a prefetch pass.
    private let maxConcurrentPrefetches = 8

    private init() {}

    /// Returns a story, fetching it if necessary. Concurrent calls for the same
    /// id share one network request.
    func story(id: Int) async -> FirebaseStoryData? {
        // Cache hit.
        if let story = entries[id] {
            touch(id)
            return story
        }
        // A fetch for this id is already running — await its result.
        if let existing = inFlight[id] {
            return await existing.value
        }
        // Cache miss: start a fetch and record it *before* suspending, so that
        // any request arriving during the await coalesces onto this same task.
        let task = Task { await FirebaseAPIService.getStoryAsync(id: id) }
        inFlight[id] = task
        let story = await task.value
        inFlight[id] = nil

        if let story {
            insert(story, for: id)
        }
        return story
    }

    /// Warms the cache for the given ids, fetching missing ones in parallel with
    /// a bounded degree of concurrency. Already-cached or in-flight ids are skipped.
    func prefetch(ids: [Int]) async {
        var iterator = ids.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            var active = 0
            // Seed the group up to the concurrency limit.
            while active < maxConcurrentPrefetches, let id = iterator.next() {
                if entries[id] == nil {
                    group.addTask { _ = await self.story(id: id) }
                    active += 1
                }
            }
            // As each finishes, start the next pending id.
            while await group.next() != nil {
                active -= 1
                while let id = iterator.next() {
                    if entries[id] == nil {
                        group.addTask { _ = await self.story(id: id) }
                        active += 1
                        break
                    }
                }
            }
        }
    }

    // MARK: - Storage helpers

    private func insert(_ story: FirebaseStoryData, for id: Int) {
        entries[id] = story
        touch(id)
        evictIfNeeded()
    }

    /// Marks `id` as most-recently-used.
    private func touch(_ id: Int) {
        if let index = lru.firstIndex(of: id) {
            lru.remove(at: index)
        }
        lru.append(id)
    }

    /// Drops least-recently-used entries until we are within `capacity`.
    private func evictIfNeeded() {
        while entries.count > capacity, let oldest = lru.first {
            lru.removeFirst()
            entries[oldest] = nil
        }
    }
}
