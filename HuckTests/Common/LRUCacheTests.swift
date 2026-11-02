//
//  LRUCacheTests.swift
//  HuckTests
//

@testable import Huck
import Testing

struct LRUCacheTests {
    @Test func returnsInsertedValues() async {
        let cache = LRUCache<Int, String>(capacity: 2)
        await cache.insert("one", for: 1)
        #expect(await cache.cachedValue(for: 1) == "one")
        #expect(await cache.cachedValue(for: 2) == nil)
    }

    @Test func evictsTheLeastRecentlyUsedEntry() async {
        let cache = LRUCache<Int, String>(capacity: 2)
        await cache.insert("one", for: 1)
        await cache.insert("two", for: 2)
        // Reading 1 makes 2 the least recently used.
        _ = await cache.cachedValue(for: 1)
        await cache.insert("three", for: 3)

        #expect(await cache.cachedValue(for: 1) == "one")
        #expect(await cache.cachedValue(for: 2) == nil)
        #expect(await cache.cachedValue(for: 3) == "three")
    }

    @Test func removeDropsAnEntry() async {
        let cache = LRUCache<Int, String>(capacity: 2)
        await cache.insert("one", for: 1)
        await cache.remove(1)
        #expect(await cache.cachedValue(for: 1) == nil)
    }

    @Test func fetchesOnAMissAndCachesTheResult() async {
        let cache = LRUCache<Int, String>(capacity: 2)
        let fetched = await cache.value(for: 1) { "fetched" }
        #expect(fetched == "fetched")
        // A second fetch would return something else, so a hit proves caching.
        let cached = await cache.value(for: 1) { "refetched" }
        #expect(cached == "fetched")
    }

    @Test func doesNotCacheAFailedFetch() async {
        let cache = LRUCache<Int, String>(capacity: 2)
        _ = await cache.value(for: 1) { nil }
        #expect(await cache.cachedValue(for: 1) == nil)
    }
}
