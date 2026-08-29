//
//  StoryCache.swift
//  HuckApp
//
//  Created by James Asbury on 12/24/25.
//

import Foundation

/// Caches stories by id, behind the API facade.
///
/// `StoryCache` is an internal detail of the API layer — callers reach it only through
/// `HackerNewsAPI` (`getStory` / `prefetchStories`), never directly.
///
/// Storage, request coalescing, and LRU eviction all come from the shared `LRUCache`;
/// this type only adds the story-specific fetch and the bounded-concurrency prefetch
/// pass on top.
actor StoryCache {
    static let shared = StoryCache()

    private let cache = LRUCache<Int, FirebaseStoryData>(capacity: 500)

    /// Maximum number of concurrent fetches during a prefetch pass.
    private let maxConcurrentPrefetches = 8

    private init() {}

    /// Returns a story, fetching it if necessary. Concurrent calls for the same id
    /// share one network request.
    func story(id: Int) async -> FirebaseStoryData? {
        await cache.value(for: id) { await FirebaseAPIService.getStoryAsync(id: id) }
    }

    /// Warms the cache for the given ids, fetching missing ones in parallel with a
    /// bounded degree of concurrency. Ids already cached or in flight cost nothing —
    /// `story(id:)` serves them without a network request.
    func prefetch(ids: [Int]) async {
        var iterator = ids.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            var active = 0
            // Seed the group up to the concurrency limit.
            while active < maxConcurrentPrefetches, let id = iterator.next() {
                group.addTask { _ = await self.story(id: id) }
                active += 1
            }
            // As each finishes, start the next pending id.
            while await group.next() != nil {
                active -= 1
                if let id = iterator.next() {
                    group.addTask { _ = await self.story(id: id) }
                    active += 1
                }
            }
        }
    }
}
