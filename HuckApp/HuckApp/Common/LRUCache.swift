//
//  LRUCache.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import Foundation

/// A thread-safe, in-memory cache keyed by `Key`, bounded by an LRU eviction policy.
///
/// This is the shared core behind the app's domain caches (`StoryCache`,
/// `CommentCache`). Being an `actor` isolates its mutable state so concurrent callers
/// can never race on the underlying storage. It offers two ways to populate it:
///
///  - **Fetch-through with coalescing** — `value(for:fetch:)` returns a cached value or
///    runs `fetch`, and concurrent requests for the same key share a single in-flight
///    fetch rather than each hitting the network.
///  - **Manual** — `insert(_:for:)` / `cachedValue(for:)` for callers that produce the
///    value themselves (e.g. a streamed result) and just want storage + eviction.
///
/// Either way the cache is bounded to `capacity` entries; the least-recently-used entry
/// is dropped on overflow.
actor LRUCache<Key: Hashable, Value> {
    /// Completed values.
    private var entries: [Key: Value] = [:]
    /// Recency order for `entries`; most-recently-used key is last.
    private var lru: [Key] = []
    /// In-progress fetches, so concurrent requests for one key are coalesced.
    private var inFlight: [Key: Task<Value?, Never>] = [:]
    /// Maximum number of completed entries to retain.
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    /// Returns a value, fetching it via `fetch` on a miss. Concurrent calls for the
    /// same key share one `fetch`.
    func value(for key: Key, fetch: @escaping @Sendable () async -> Value?) async -> Value? {
        if let value = entries[key] {
            touch(key)
            return value
        }
        // A fetch for this key is already running — await its result.
        if let existing = inFlight[key] {
            return await existing.value
        }
        // Cache miss: record the task *before* suspending, so any request arriving
        // during the await coalesces onto it.
        let task = Task { await fetch() }
        inFlight[key] = task
        let value = await task.value
        inFlight[key] = nil

        if let value {
            insert(value, for: key)
        }
        return value
    }

    /// The cached value for `key`, if present, marking it most-recently-used. Does not
    /// fetch.
    func cachedValue(for key: Key) -> Value? {
        guard let value = entries[key] else { return nil }
        touch(key)
        return value
    }

    /// Stores a caller-produced value, evicting the least-recently-used entry if the
    /// cache is now over capacity.
    func insert(_ value: Value, for key: Key) {
        entries[key] = value
        touch(key)
        evictIfNeeded()
    }

    // MARK: - Storage helpers

    /// Marks `key` as most-recently-used.
    private func touch(_ key: Key) {
        if let index = lru.firstIndex(of: key) {
            lru.remove(at: index)
        }
        lru.append(key)
    }

    /// Drops least-recently-used entries until we are within `capacity`.
    private func evictIfNeeded() {
        while entries.count > capacity, let oldest = lru.first {
            lru.removeFirst()
            entries[oldest] = nil
        }
    }
}
