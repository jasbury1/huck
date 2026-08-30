//
//  RecentlyViewedStore.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import SwiftUI

/// The source of truth for each user's recently-viewed stories, kept most-recent
/// first. A story counts as "viewed" when its link or its comments are opened;
/// views read this to grey already-seen titles in the feed and to build the
/// "Recently viewed" list on the account profile.
///
/// Browsing while signed out is recorded against a reserved *guest* bucket, which
/// is merged into a real account the first time that account is seen after login
/// (see `adoptGuestHistory()`), so history carries across the sign-in boundary.
///
/// It holds every retained bucket in memory (bounded to two real users, plus the
/// transient guest one) and resolves the *current* bucket live from
/// `UserSession`, so switching accounts simply reads a different one — a
/// login/logout needs no explicit reload, unlike `InteractionStore`, which keeps
/// one file per user. Injected app-wide via the environment; every story view
/// observes this one instance.
@MainActor
@Observable
final class RecentlyViewedStore {
    /// All retained buckets — the store's single observed property. Reads in a
    /// view body track it, so recording a view both greys the story in the feed
    /// and refreshes the account list.
    private(set) var storage = RecentlyViewedStorage()

    /// The bucket key for views recorded while signed out. Empty is safe as a
    /// sentinel because a real HN username is never empty.
    private static let guestKey = ""

    /// The bucket the current session reads and writes: the signed-in user, or
    /// the guest bucket when signed out.
    private var currentKey: String { UserSession.shared?.username ?? Self.guestKey }

    init() {
        storage = RecentlyViewedPersistence.load()
    }

    /// The current session's viewed story ids, most-recently-viewed first. Drives
    /// the account profile's "Recently viewed" list.
    var viewedIDs: [Int] {
        storage.byUser[currentKey] ?? []
    }

    /// Whether the current session has recently viewed a story — used to grey its
    /// title in the feed.
    func hasViewed(_ id: Int) -> Bool {
        storage.byUser[currentKey]?.contains(id) ?? false
    }

    /// Records that the current session opened a story (its link or its
    /// comments): moves it to the front of the active bucket, enforcing the
    /// per-bucket story cap, then persists. Signed out, this writes to the guest
    /// bucket instead of no-op'ing.
    func recordView(_ id: Int) {
        let key = currentKey
        storage.byUser[key] = movedToFront(id, in: storage.byUser[key] ?? [])

        // The two-user retention cap only applies to real accounts; the guest
        // bucket is transient and merged away on login, so it doesn't take a slot.
        if let username = UserSession.shared?.username {
            touch(username)
        }

        RecentlyViewedPersistence.save(storage)
    }

    /// Merges any guest (signed-out) history into the now-current user's list,
    /// most-recent first, and clears the guest bucket. Call after login so
    /// browsing done while signed out carries into the account. No-op when signed
    /// out or when there's nothing to merge.
    func adoptGuestHistory() {
        guard let username = UserSession.shared?.username else { return }
        let guestIDs = storage.byUser[Self.guestKey] ?? []
        guard !guestIDs.isEmpty else { return }

        // Guest views are the most recent activity, so they lead; the user's
        // existing history follows with any duplicates dropped.
        var merged = guestIDs
        for id in storage.byUser[username] ?? [] where !guestIDs.contains(id) {
            merged.append(id)
        }
        storage.byUser[username] = capped(merged)
        storage.byUser[Self.guestKey] = nil

        touch(username)
        RecentlyViewedPersistence.save(storage)
    }

    /// Removes a story from the current session's history — marking it unread, so
    /// its feed title is no longer greyed — then persists. No-op if it wasn't
    /// viewed. Signed out, this edits the guest bucket.
    func removeView(_ id: Int) {
        let key = currentKey
        guard var ids = storage.byUser[key], ids.contains(id) else { return }
        ids.removeAll { $0 == id }
        storage.byUser[key] = ids.isEmpty ? nil : ids
        RecentlyViewedPersistence.save(storage)
    }

    /// Clears the current session's recently-viewed history, then persists.
    /// Signed out, this empties the guest bucket.
    func clearHistory() {
        storage.byUser[currentKey] = nil
        RecentlyViewedPersistence.save(storage)
    }

    // MARK: - Helpers

    /// `ids` with `id` moved to (or inserted at) the front, capped to `maxStories`.
    private func movedToFront(_ id: Int, in ids: [Int]) -> [Int] {
        var ids = ids
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        return capped(ids)
    }

    /// `ids` trimmed to the most recent `maxStories`.
    private func capped(_ ids: [Int]) -> [Int] {
        Array(ids.prefix(RecentlyViewedPersistence.maxStories))
    }

    /// Marks a real user most-recently-active and evicts any user beyond the
    /// retention cap, so at most `maxUsers` accounts are kept.
    private func touch(_ username: String) {
        storage.userOrder.removeAll { $0 == username }
        storage.userOrder.insert(username, at: 0)
        for evicted in storage.userOrder.dropFirst(RecentlyViewedPersistence.maxUsers) {
            storage.byUser[evicted] = nil
        }
        storage.userOrder = Array(storage.userOrder.prefix(RecentlyViewedPersistence.maxUsers))
    }
}
