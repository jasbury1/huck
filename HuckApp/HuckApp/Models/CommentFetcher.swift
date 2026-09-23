//
//  CommentFetcher.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import SwiftUI

@MainActor
@Observable
class CommentFetcher {
    let id: Int
    var comments: [Comment] = []

    /// True while the thread is still loading. Drives the loading indicator: a centred
    /// spinner before any comments arrive, then a footer spinner while the rest of a
    /// streamed Firebase thread fills in.
    private(set) var isLoading = false

    /// Ids of comments whose reply subtrees are collapsed (hidden).
    var collapsedIds: Set<Int> = []

    /// What's needed to recover the Hacker News id of a comment posted from this
    /// thread, keyed by that comment's `id`, for as long as it's still unknown.
    ///
    /// Held here rather than on `Comment` so the model stays a model: this is
    /// bookkeeping for one narrow case, not a property of a comment.
    private var unresolvedPosts: [Int: (author: String, parentID: Int)] = [:]

    init(id: Int) {
        self.id = id
    }

    /// Loads the thread, updating `comments` as it arrives. Algolia threads land in one
    /// snapshot; a Firebase-walked thread streams in progressively. Each snapshot only
    /// appends to the last, so the list grows downward without reflowing — the animated
    /// assignment simply fades the new rows in.
    func fetchComments() async {
        isLoading = true
        for await snapshot in HackerNewsAPI.streamComments(for: id) {
            withAnimation(.easeIn(duration: 0.2)) {
                comments = snapshot
            }
        }
        isLoading = false
    }

    /// Places a comment the reader has just posted into the thread, where the
    /// server will eventually put it.
    ///
    /// This is deliberately done instead of re-fetching. A refetch reads the
    /// thread back as *growing* snapshots — the realtime walk starts from a
    /// handful of comments and builds up — and assigning those over a list
    /// that's already full empties the screen and refills it in front of the
    /// reader. Posting already invalidated the caches, so the server's copy,
    /// carrying a real id, arrives on the next load of the story.
    /// The comment arrives with no Hacker News id, and no lookup is made to find
    /// one — that waits until something actually needs it. See
    /// `resolveItemID(for:)`.
    ///
    /// Returns the comment as placed, so the caller can bring it into view.
    @discardableResult
    func insertPostedComment(text: String, author: String, replyingTo parent: Comment?) -> Comment {
        let comment = Comment(
            posted: text,
            author: author,
            nestingLevel: (parent?.nestingLevel ?? -1) + 1
        )
        // Note what a later lookup would need. The parent's own id is read now,
        // while it's certainly known: a pending comment can only have been
        // replied to through `resolveItemID`, which resolves it first, so a
        // chain of self-replies never leaves a gap here.
        unresolvedPosts[comment.id] = (author: author, parentID: parent?.itemID ?? id)
        withAnimation(.easeIn(duration: 0.2)) {
            guard let parent,
                  let parentIndex = comments.firstIndex(where: { $0.id == parent.id }) else {
                // A new top-level comment goes at the foot of the thread.
                comments.append(comment)
                return
            }
            // Replying to a comment that's collapsed would file the reply out of
            // sight, so open it back up.
            collapsedIds.remove(parent.id)
            // A reply joins the end of the parent's existing replies. In this
            // flat pre-order list that's just past the run of deeper-nested
            // comments following the parent — the same shape `visibleComments`
            // relies on below.
            var insertionIndex = parentIndex + 1
            while insertionIndex < comments.count,
                  comments[insertionIndex].nestingLevel > parent.nestingLevel {
                insertionIndex += 1
            }
            comments.insert(comment, at: insertionIndex)
        }
        return comment
    }

    /// The comment's Hacker News id, looking it up first if it isn't known yet.
    /// `nil` only if the lookup couldn't confirm one.
    ///
    /// Resolution is deliberately lazy. Hacker News' comment form never reports
    /// the id it assigns, and recovering one costs a couple of reads against a
    /// mirror that trails the site — but the id is needed for exactly one thing:
    /// replying to a comment the reader posted in this same sitting. That's rare,
    /// so paying for it after every post was almost always waste. Waiting until
    /// it's asked for also makes it far more likely to succeed: by the time
    /// someone has read their comment and decided to answer it, the lag that made
    /// an immediate lookup fail has long since passed.
    ///
    /// Assigning `itemID` (rather than `id`) keeps the row's identity stable, so
    /// SwiftUI updates the comment in place instead of tearing it down.
    func resolveItemID(for comment: Comment) async -> Int? {
        if let itemID = comment.itemID { return itemID }
        guard let post = unresolvedPosts[comment.id] else { return nil }

        let resolved = await HackerNewsAPI.findPostedCommentId(
            username: post.author,
            parentID: post.parentID
        )
        guard let resolved else { return nil }
        comment.itemID = resolved
        unresolvedPosts[comment.id] = nil
        return resolved
    }

    /// The comments currently on screen: the flat, pre-order list with the reply
    /// subtree of every collapsed comment removed. Because the list is
    /// depth-first and each comment carries its `nestingLevel`, a collapsed
    /// comment's descendants are exactly the following run of deeper-nested
    /// comments — so one linear pass is enough to drop them.
    var visibleComments: [Comment] {
        var result: [Comment] = []
        // While set, skip every comment nested deeper than this level.
        var hiddenBelowLevel: Int?
        for comment in comments {
            if let threshold = hiddenBelowLevel {
                if comment.nestingLevel > threshold { continue }
                // Back at the collapsed comment's level or shallower: stop hiding.
                hiddenBelowLevel = nil
            }
            result.append(comment)
            if collapsedIds.contains(comment.id) {
                hiddenBelowLevel = comment.nestingLevel
            }
        }
        return result
    }

    func isCollapsed(_ comment: Comment) -> Bool {
        collapsedIds.contains(comment.id)
    }

    /// Folds away the whole reply chain this comment sits in, collapsing it at
    /// the top-level comment it descends from.
    ///
    /// In the flat pre-order list that root is simply the nearest comment at
    /// nesting level 0 at or before this one — the same structure
    /// `visibleComments` walks. A top-level comment is its own root, so this
    /// behaves like `toggleCollapsed` for one.
    ///
    /// Returns the comment it folded at, which is the one worth scrolling to:
    /// the root can be far above the reply the reader acted on, and everything
    /// between just disappeared.
    @discardableResult
    func collapseThread(containing comment: Comment) -> Comment? {
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return nil }
        let root = comments[...index].last { $0.nestingLevel == 0 } ?? comment
        collapsedIds.insert(root.id)
        return root
    }

    func toggleCollapsed(_ comment: Comment) {
        if collapsedIds.contains(comment.id) {
            collapsedIds.remove(comment.id)
        } else {
            collapsedIds.insert(comment.id)
        }
    }
}
