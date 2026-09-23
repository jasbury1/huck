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
    /// `id` is the one Hacker News assigned, or `nil` if it couldn't be
    /// confirmed — see `Comment.init(posted:author:id:nestingLevel:)`.
    func insertPostedComment(id: Int?, text: String, author: String, replyingTo parent: Comment?) {
        let comment = Comment(
            posted: text,
            author: author,
            id: id,
            nestingLevel: (parent?.nestingLevel ?? -1) + 1
        )
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

    func toggleCollapsed(_ comment: Comment) {
        if collapsedIds.contains(comment.id) {
            collapsedIds.remove(comment.id)
        } else {
            collapsedIds.insert(comment.id)
        }
    }
}
