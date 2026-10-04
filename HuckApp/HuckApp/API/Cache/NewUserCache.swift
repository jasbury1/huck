//
//  NewUserCache.swift
//  HuckApp
//
//  Created by James Asbury on 10/4/26.
//

import Foundation

/// Caches which commenters on a thread Hacker News marks as new accounts, by
/// story id, behind the API facade.
///
/// The answer costs a read of the thread's full HN page, so it's kept for a
/// while: re-opening a story, or backing into it, shouldn't read the page
/// again. Entries expire on the same footing as `CommentCache` — a thread
/// gains new commenters as it goes, and a returning reader should see them
/// marked — and concurrent asks for one thread share a single read.
///
/// `NewUserCache` is an internal detail of the API layer — callers reach it
/// only through `HackerNewsAPI.newUsers(inThread:)`, never directly.
actor NewUserCache {
    static let shared = NewUserCache()

    private let timeToLive: TimeInterval = 5 * 60

    private let cache = LRUCache<Int, Entry>(capacity: 50)

    /// Page reads in progress, so concurrent asks for a thread share one.
    private var inFlight: [Int: Task<Set<String>?, Never>] = [:]

    private init() {}

    private struct Entry {
        let usernames: Set<String>
        let storedAt: Date
    }

    /// The new accounts commenting on a story, from memory when fresh,
    /// otherwise from its page. Empty if the page couldn't be read — the names
    /// then simply aren't marked, and a failed read isn't kept, so the next
    /// visit tries again.
    func usernames(inThread id: Int) async -> Set<String> {
        if let entry = await cache.cachedValue(for: id),
           Date.now.timeIntervalSince(entry.storedAt) < timeToLive {
            return entry.usernames
        }
        if let existing = inFlight[id] {
            return await existing.value ?? []
        }
        let task = Task { await NewsYCService.newUsers(onItem: id) }
        inFlight[id] = task
        let usernames = await task.value
        inFlight[id] = nil
        guard let usernames else { return [] }
        await cache.insert(Entry(usernames: usernames, storedAt: .now), for: id)
        return usernames
    }
}
