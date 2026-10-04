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

    /// Who is signed in. Held rather than read globally so the store has one
    /// declared dependency instead of an ambient one.
    private let session: UserSession

    /// The user the *loaded* state belongs to; `nil` when logged out. Distinct
    /// from `session.username`: the in-memory sets belong to whoever they were
    /// loaded for, and persisting against anyone else would corrupt their file.
    private var username: String?

    /// Optimistic, per-story adjustment to the displayed score (e.g. +1 while an
    /// upvote is in effect), keyed by id. This lives here — not on `StoryModel` —
    /// because the same story is shown by multiple `StoryModel` instances (feed vs.
    /// comments view); keeping the delta in one shared place is what keeps their
    /// scores in sync. Not persisted: on relaunch the refetched score is truth.
    private var scoreDeltas: [Int: Int] = [:]

    /// Progress through the current walk of the user's own `/favorites` and
    /// `/upvoted` lists — see `ListWalk` and `reconcile`.
    private var favoritesWalk = ListWalk()
    private var upvotedWalk = ListWalk()
    private var upvotedCommentsWalk = ListWalk()

    init(session: UserSession) {
        self.session = session
        loadForCurrentUser()
    }

    /// (Re)loads persisted state for whoever is currently logged in. Call after a
    /// login/logout so the store reflects the active account.
    func loadForCurrentUser() {
        username = session.username
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
        guard session.isSignedIn else { return }

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

    /// A page of a user's liked (upvoted) stories for display (most-recent first).
    /// When the list belongs to the user whose state is loaded, `/upvoted` is
    /// authoritative for it, so each page is folded in by `reconcile` — keeping
    /// that invariant here, in the owner of upvote state, rather than at each call
    /// site. No score delta is applied: the fetched score already reflects these
    /// votes. In practice `username` is always the signed-in user, since Hacker
    /// News shows `/upvoted` to no one else.
    func likedStories(username: String, page: Int = 0) async -> (ids: [Int], hasMore: Bool) {
        guard let result = await HackerNewsAPI.getLikedStories(username: username, page: page) else {
            return ([], false)
        }
        if username == self.username {
            reconcile(&upvotedWalk, page: page, result: result, into: \.upvoted)
        }
        return result
    }

    // MARK: - Comment votes

    /// Whether the reader has upvoted a comment. Read by every comment row to
    /// colour its arrow.
    func isCommentUpvoted(_ id: Int) -> Bool {
        interactions.upvotedComments.contains(id)
    }

    /// Toggles the upvote on a comment: flips local state optimistically, calls
    /// the API, and rolls back if the request fails. No-op when logged out
    /// (callers route to login first).
    ///
    /// No score delta, unlike a story: Hacker News doesn't publish a comment's
    /// score, so there's no number on screen for a vote to move.
    func toggleCommentUpvote(id: Int) async {
        guard session.isSignedIn else { return }

        let wasUpvoted = interactions.upvotedComments.contains(id)
        setCommentUpvoted(!wasUpvoted, for: id)

        do {
            if wasUpvoted {
                try await HackerNewsAPI.unvoteComment(id: id)
            } else {
                try await HackerNewsAPI.upvoteComment(id: id)
            }
            persist()
        } catch {
            setCommentUpvoted(wasUpvoted, for: id)
            print("Comment vote failed for \(id): \(error)")
        }
    }

    /// A page of a user's upvoted comments for display, most-recent first.
    ///
    /// As with `likedStories`, `/upvoted` is authoritative for the list it
    /// covers, so each page is folded into the store — which is what fills in
    /// orange arrows for comments upvoted on the web or before this install.
    /// Hacker News shows the list to no one but its owner, so in practice
    /// `username` is always the signed-in user.
    func likedComments(username: String, page: Int = 0) async -> (comments: [UserComment], hasMore: Bool) {
        guard let result = await HackerNewsAPI.getLikedComments(username: username, page: page) else {
            return ([], false)
        }
        if username == self.username {
            reconcile(
                &upvotedCommentsWalk,
                page: page,
                result: (result.comments.map(\.id), result.hasMore),
                into: \.upvotedComments
            )
        }
        return result
    }

    // MARK: - Hidden stories

    /// Stories the reader has hidden from their feeds.
    var hiddenIDs: Set<Int> {
        interactions.hidden
    }

    /// Hides a story from the reader's feeds, or brings it back. Kept on this
    /// device for now, per account like the rest of the store; Hacker News has
    /// its own hide, which this doesn't yet send to. No-op when logged out
    /// (callers route to login first).
    func setHidden(_ isHidden: Bool, for id: Int) {
        guard session.isSignedIn else { return }
        if isHidden {
            interactions.hidden.insert(id)
        } else {
            interactions.hidden.remove(id)
        }
        persist()
    }

    /// Brings every hidden story back into the reader's feeds.
    func unhideAll() {
        guard session.isSignedIn else { return }
        interactions.hidden.removeAll()
        persist()
    }

    /// Toggles the favorite on a story: flips local state optimistically, calls the
    /// API, and rolls back if it fails. No-op when logged out (callers route to
    /// login first). Unlike voting, favoriting doesn't affect the score.
    func toggleFavorite(_ story: StoryModel) async {
        guard session.isSignedIn else { return }

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

    /// A page of a user's favorited stories for display. When the list belongs to
    /// the *current* user it is authoritative for their favorite state, so each
    /// page is folded into the store by `reconcile` — filling in hearts for
    /// stories favorited on the web or before this install, and, once a walk
    /// reaches the end of the list, clearing ones unfavorited elsewhere. Another
    /// user's favorites are returned untouched: they say nothing about what *we*
    /// have favorited.
    func favoriteStories(username: String, page: Int = 0) async -> (ids: [Int], hasMore: Bool) {
        guard let result = await HackerNewsAPI.getFavoriteStories(username: username, page: page) else {
            return ([], false)
        }
        if username == self.username {
            reconcile(&favoritesWalk, page: page, result: result, into: \.favorited)
        }
        return result
    }

    // MARK: - Reconciliation

    /// Progress through one walk of a server-side list (`/favorites`, `/upvoted`)
    /// as its pages are read in order. Traversal-scoped and never persisted.
    private struct ListWalk {
        /// Every id seen so far in this walk.
        var seen: Set<Int> = []
        /// The page number that must come next for `seen` to stay meaningful.
        var expectedPage = 0
    }

    /// Folds one page of a server list into the matching local set.
    ///
    /// Each page proves the ids on it *are* in the list, so they're always added.
    /// Removal needs more: only once a walk has read the list from page 0 through
    /// to its end (`hasMore == false`) is `seen` the complete server-side truth,
    /// and only then can ids missing from it be dropped — which is what clears a
    /// story unfavorited on the web but still showing a filled heart here.
    ///
    /// Two guards keep that from ever removing wrongly. Pages must arrive in
    /// sequence, so a gap (two feeds paging the same list concurrently) demotes
    /// the walk to add-only. And a failed fetch reaches us as `nil` upstream
    /// rather than an empty final page, so a network blip mid-walk can't be
    /// mistaken for the end of the list.
    private func reconcile(
        _ walk: inout ListWalk,
        page: Int,
        result: (ids: [Int], hasMore: Bool),
        into keyPath: WritableKeyPath<PersistedInteractions, Set<Int>>
    ) {
        if page == 0 { walk = ListWalk() }
        let inSequence = page == walk.expectedPage
        walk.seen.formUnion(result.ids)
        walk.expectedPage = page + 1

        if inSequence, !result.hasMore {
            interactions[keyPath: keyPath] = walk.seen
        } else {
            interactions[keyPath: keyPath].formUnion(result.ids)
        }
        persist()
    }

    // MARK: - Helpers

    private func setUpvoted(_ value: Bool, for id: Int) {
        if value {
            interactions.upvoted.insert(id)
        } else {
            interactions.upvoted.remove(id)
        }
    }

    private func setCommentUpvoted(_ value: Bool, for id: Int) {
        if value {
            interactions.upvotedComments.insert(id)
        } else {
            interactions.upvotedComments.remove(id)
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
