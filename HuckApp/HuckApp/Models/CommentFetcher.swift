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

    /// Ids of comments whose reply subtrees are collapsed (hidden).
    var collapsedIds: Set<Int> = []

    init(id: Int) {
        self.id = id
    }

    /// Loads the thread, updating `comments` as it arrives. Algolia threads land in
    /// one snapshot; a Firebase-walked thread streams in progressively (top-level
    /// comments first, deeper replies filling in), so the list renders as it loads.
    func fetchComments() async {
        for await snapshot in HackerNewsAPI.streamComments(for: id) {
            comments = snapshot
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
