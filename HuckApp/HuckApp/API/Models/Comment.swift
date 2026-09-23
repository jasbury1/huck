//
//  Comment.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//
import SwiftUI

@Observable
class Comment {
    /// Identifies the comment to SwiftUI, and never changes for the lifetime of
    /// the object. For a comment from either API this is its Hacker News id; for
    /// one the reader just posted it's a negative stand-in, because HN's comment
    /// form doesn't report the id it assigned. Use `itemID` to *act* on a
    /// comment; this is only for identity and diffing.
    var id: Int
    /// The Hacker News item id, once known — what's needed to reply to or vote
    /// on this comment.
    ///
    /// Normally just `id`. For a comment the reader has posted it starts out
    /// `nil` and is filled in once recovered from the API, a second or two
    /// later. Keeping it apart from `id` is what lets that happen without
    /// changing the row's identity, which would make SwiftUI tear the comment
    /// down and build it again in front of the reader.
    var itemID: Int?
    var nestingLevel: Int
    var text: String
    var points: Int
    var author: String
    var timestamp: Date
    var parent: Comment?
    var children: [Comment]
    
    init(item: AlgoliaItemData) {
        self.id = item.id
        self.itemID = item.id
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
    /// It arrives with no `itemID`: Hacker News' comment form never reports the
    /// id it assigned, so that's recovered in the background and set afterwards.
    /// Until then the comment is real and posted but not yet addressable, which
    /// `isPending` reports. The stand-in `id` is negative so it can never
    /// collide with a real item id.
    init(posted text: String, author: String, nestingLevel: Int) {
        self.id = Int.random(in: Int.min ..< 0)
        self.itemID = nil
        self.nestingLevel = nestingLevel
        self.text = text
        self.points = 1
        self.author = author
        self.parent = nil
        self.children = []
        self.timestamp = .now
    }

    /// Whether this comment is posted but not yet addressable, because its
    /// Hacker News id hasn't come back yet.
    var isPending: Bool { itemID == nil }

    /// This comment's permalink on Hacker News, matching `StoryModel`'s. `nil`
    /// while `itemID` is unknown — there's nothing to link to until then.
    var hackerNewsURL: URL? {
        itemID.flatMap { URL(string: "https://news.ycombinator.com/item?id=\($0)") }
    }

    /// Builds a comment from the realtime Firebase API, used as a fallback when a
    /// story is too new to be indexed by Algolia. Firebase omits a comment's
    /// score, so `points` defaults to 0.
    init(firebase item: FirebaseCommentData, nestingLevel: Int) {
        self.id = item.id
        self.itemID = item.id
        self.nestingLevel = nestingLevel
        self.text = item.text?.normalizeHtmlText() ?? ""
        self.points = 0
        self.author = item.by ?? ""
        self.parent = nil
        self.children = []
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(item.time ?? 0))
    }
}
