//
//  Comment.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//
import SwiftUI

@Observable
class Comment {
    var id: Int
    var nestingLevel: Int
    var text: String
    var points: Int
    var author: String
    var timestamp: Date
    var parent: Comment?
    var children: [Comment]
    
    init(item: AlgoliaItemData) {
        self.id = item.id
        self.nestingLevel = 0
        self.text = item.text?.normalizeHtmlText() ?? ""
        self.points = item.points ?? 0
        self.author = item.author
        self.parent = nil
        self.children = []
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(item.createdAtI))
    }

    /// Builds a comment the reader has just posted, so the thread can show it
    /// straight away instead of after a round trip.
    ///
    /// `id` is the one Hacker News assigned, recovered after the fact — the
    /// comment form never reports it. Pass `nil` when it couldn't be confirmed
    /// and the comment stands in with a negative id instead, which can never
    /// collide with a real item id. `isPending` keys off exactly that: such a
    /// comment is real and posted, but not yet addressable, so it can't be
    /// replied to or voted on until the thread is reloaded.
    init(posted text: String, author: String, id: Int?, nestingLevel: Int) {
        self.id = id ?? Int.random(in: Int.min ..< 0)
        self.nestingLevel = nestingLevel
        self.text = text
        self.points = 1
        self.author = author
        self.parent = nil
        self.children = []
        self.timestamp = .now
    }

    /// Whether this comment is posted but not yet addressable — its Hacker News
    /// id couldn't be recovered, so it carries a stand-in one.
    var isPending: Bool { id < 0 }

    /// Builds a comment from the realtime Firebase API, used as a fallback when a
    /// story is too new to be indexed by Algolia. Firebase omits a comment's
    /// score, so `points` defaults to 0.
    init(firebase item: FirebaseCommentData, nestingLevel: Int) {
        self.id = item.id
        self.nestingLevel = nestingLevel
        self.text = item.text?.normalizeHtmlText() ?? ""
        self.points = 0
        self.author = item.by ?? ""
        self.parent = nil
        self.children = []
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(item.time ?? 0))
    }
}
