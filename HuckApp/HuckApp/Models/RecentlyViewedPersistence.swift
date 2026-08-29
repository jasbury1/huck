//
//  RecentlyViewedPersistence.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import Foundation

/// The recently-viewed story lists we persist to disk, bounded on two axes so
/// storage can't grow without limit: at most two users are retained (the
/// least-recently-active is evicted when a third appears) and each keeps only
/// its most recent 100 story ids.
///
/// Kept separate from `PersistedInteractions` because this is an *ordered*,
/// capped, multi-user structure with cross-user eviction — not the per-user
/// interaction sets, which live one file per user.
struct RecentlyViewedStorage: Codable {
    /// Each retained bucket's viewed story ids, most-recently-viewed first —
    /// keyed by username, plus a reserved guest bucket for signed-out browsing
    /// (see `RecentlyViewedStore`).
    var byUser: [String: [Int]] = [:]
    /// Retained usernames in most-recently-active-first order, so the user to
    /// evict when over the cap is always the last one. Excludes the guest bucket,
    /// which is transient and merged into an account on login rather than capped.
    var userOrder: [String] = []
}

/// Loads and saves `RecentlyViewedStorage` as a single JSON file in Application
/// Support. One combined file (rather than one per user, as with interactions)
/// keeps the two-user cap and its eviction logic in a single place.
enum RecentlyViewedPersistence {
    /// The largest number of users whose lists are retained at once.
    static let maxUsers = 2
    /// The largest number of story ids retained per user.
    static let maxStories = 100

    private static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("RecentlyViewed", isDirectory: true)
            .appendingPathComponent("store.json")
    }

    /// The stored lists, or empty state if nothing is saved yet.
    static func load() -> RecentlyViewedStorage {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(RecentlyViewedStorage.self, from: data) else {
            return RecentlyViewedStorage()
        }
        return decoded
    }

    /// Writes the lists atomically.
    static func save(_ storage: RecentlyViewedStorage) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(storage)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to persist recently viewed: \(error)")
        }
    }
}
