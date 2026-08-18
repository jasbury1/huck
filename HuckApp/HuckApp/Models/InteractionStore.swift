//
//  InteractionStore.swift
//  HuckApp
//
//  Created by James Asbury on 8/16/26.
//

import SwiftUI

/// A story's user-interaction state, read by views to drive their appearance
/// (e.g. an orange upvote arrow). Assembled on demand from `InteractionStore`.
struct StoryInteraction {
    var isUpvoted = false
    var isFavorited = false
    var isHidden = false
}

/// The single source of truth for per-story user interactions (upvoted, and later
/// favorited/hidden), keyed by story id.
///
/// This lives apart from `StoryModel` on purpose: the same story appears as
/// *different* `StoryModel` instances across the feed, the comments view, and
/// profiles, so interaction state can't live on the per-view model without
/// fragmenting. Injected app-wide via the environment; every view observes this
/// one instance, and it's where optimistic updates, network confirmation, and
/// (later) drift reconciliation all write.
@MainActor
@Observable
class InteractionStore {
    /// The persisted state, and the store's single observed property — reads in a
    /// view body track it, and any mutation invalidates those views.
    private(set) var interactions = PersistedInteractions()

    /// The user the loaded state belongs to; `nil` when logged out.
    private var username: String?

    /// Optimistic, per-story adjustment to the displayed score (e.g. +1 while an
    /// upvote is in effect), keyed by id. This lives here — not on `StoryModel` —
    /// because the same story is shown by multiple `StoryModel` instances (feed vs.
    /// comments view); keeping the delta in one shared place is what keeps their
    /// scores in sync. Not persisted: on relaunch the refetched score is truth.
    private var scoreDeltas: [Int: Int] = [:]

    init() {
        loadForCurrentUser()
    }

    /// (Re)loads persisted state for whoever is currently logged in. Call after a
    /// login/logout so the store reflects the active account.
    func loadForCurrentUser() {
        username = UserSession.shared?.username
        interactions = username.map(InteractionPersistence.load) ?? PersistedInteractions()
    }

    /// The interaction state for a story id. Views read this to render state.
    func interaction(for id: Int) -> StoryInteraction {
        StoryInteraction(
            isUpvoted: interactions.upvoted.contains(id),
            isFavorited: interactions.favorited.contains(id),
            isHidden: interactions.hidden.contains(id)
        )
    }

    /// The optimistic score adjustment for a story id. Views add this to the
    /// story's fetched score so every view for the same story shows one value.
    func scoreDelta(for id: Int) -> Int {
        scoreDeltas[id] ?? 0
    }

    /// Toggles the upvote on a story: updates local state and the shared score
    /// delta optimistically, calls the API, and rolls both back if the request
    /// fails. No-op when logged out (callers should route to login first).
    ///
    /// Note it adjusts the shared `scoreDeltas` rather than `story.score`: because
    /// the same story is represented by multiple `StoryModel` instances, mutating a
    /// single instance's score would desync the others (see the score-drift bug).
    func toggleUpvote(_ story: StoryModel) async {
        guard UserSession.shared != nil else { return }

        let id = story.id
        let wasUpvoted = interactions.upvoted.contains(id)

        // Optimistic: flip local state and the shared score delta immediately.
        setUpvoted(!wasUpvoted, for: id)
        adjustScoreDelta(by: wasUpvoted ? -1 : 1, for: id)

        do {
            if wasUpvoted {
                try await HackerNewsAPI.unvoteStory(id: id)
            } else {
                try await HackerNewsAPI.upvoteStory(id: id)
            }
            persist()
        } catch {
            // Roll back to the pre-tap state.
            setUpvoted(wasUpvoted, for: id)
            adjustScoreDelta(by: wasUpvoted ? 1 : -1, for: id)
            print("Vote failed for \(id): \(error)")
        }
    }

    /// Replaces the upvoted set for the current user (used by drift reconciliation
    /// in a later phase) and persists.
    func replaceUpvoted(with ids: Set<Int>) {
        interactions.upvoted = ids
        persist()
    }

    /// A page of the current user's liked (upvoted) stories for display (most-recent
    /// first). The `/upvoted` list is authoritative proof these are upvoted, so this
    /// also reconciles the store — keeping that invariant here, in the owner of
    /// upvote state, rather than at each call site. No score delta is applied: the
    /// fetched score already reflects these votes.
    func likedStories(page: Int = 0) async -> (ids: [Int], hasMore: Bool) {
        let result = await HackerNewsAPI.getLikedStories(page: page)
        if !result.ids.isEmpty {
            interactions.upvoted.formUnion(result.ids)
            persist()
        }
        return result
    }

    /// Toggles the favorite on a story: flips local state optimistically, calls the
    /// API, and rolls back if it fails. No-op when logged out (callers route to
    /// login first). Unlike voting, favoriting doesn't affect the score.
    func toggleFavorite(_ story: StoryModel) async {
        guard UserSession.shared != nil else { return }

        let id = story.id
        let wasFavorited = interactions.favorited.contains(id)

        setFavorited(!wasFavorited, for: id)

        do {
            if wasFavorited {
                try await HackerNewsAPI.unfavoriteStory(id: id)
            } else {
                try await HackerNewsAPI.favoriteStory(id: id)
            }
            persist()
        } catch {
            setFavorited(wasFavorited, for: id)
            print("Favorite failed for \(id): \(error)")
        }
    }

    /// A page of the *current user's* favorited stories for display. Their own
    /// `/favorites` list is authoritative for their favorite state, so this
    /// reconciles the store (keeping hearts in sync) — mirroring `likedStories`.
    /// Other users' favorites are fetched via `HackerNewsAPI.getFavoriteStories`
    /// directly and are *not* reconciled here, since they aren't the current user's.
    func favoriteStories(page: Int = 0) async -> (ids: [Int], hasMore: Bool) {
        guard let username = UserSession.shared?.username else { return ([], false) }
        let result = await HackerNewsAPI.getFavoriteStories(username: username, page: page)
        if !result.ids.isEmpty {
            interactions.favorited.formUnion(result.ids)
            persist()
        }
        return result
    }

    // MARK: - Helpers

    private func setUpvoted(_ value: Bool, for id: Int) {
        if value {
            interactions.upvoted.insert(id)
        } else {
            interactions.upvoted.remove(id)
        }
    }

    private func setFavorited(_ value: Bool, for id: Int) {
        if value {
            interactions.favorited.insert(id)
        } else {
            interactions.favorited.remove(id)
        }
    }

    private func adjustScoreDelta(by amount: Int, for id: Int) {
        let updated = (scoreDeltas[id] ?? 0) + amount
        // Drop zero entries so the dictionary doesn't grow unbounded.
        if updated == 0 {
            scoreDeltas[id] = nil
        } else {
            scoreDeltas[id] = updated
        }
    }

    private func persist() {
        guard let username else { return }
        InteractionPersistence.save(interactions, username: username)
    }
}
