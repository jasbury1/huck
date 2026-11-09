//
//  FirebaseAPIService.swift
//  Huck
//
//  Created by James Asbury on 12/26/25.
//

import Foundation

// MARK: - Firebase Response Data

/// A story item as returned by the official Firebase HN `item` endpoint.
nonisolated struct FirebaseStoryData: Codable, Sendable {
    let title: String
    let by: String
    let score: Int
    let time: Int
    let kids: [Int]?
    let url: String?
    let text: String?
    /// Total comment count for the whole thread, across every nesting level (not
    /// just direct `kids`). Used as the realtime yardstick for whether Algolia's
    /// indexed comment tree is still complete. Optional because non-story items
    /// omit it.
    let descendants: Int?
    /// A poll's options, as `pollopt` item ids in display order. Absent on
    /// anything that isn't a poll.
    let parts: [Int]?
}

/// One of a poll's options as returned by the Firebase `item` endpoint. Its
/// `score` is the option's vote count. Algolia carries these items too, but
/// without their text, so Firebase is the only source for what an option says.
nonisolated struct FirebasePollOptionData: Codable, Sendable {
    let id: Int
    let text: String?
    let score: Int?
}

/// A comment item as returned by the official Firebase HN `item` endpoint.
///
/// Most fields are optional because leaf comments omit `kids` and
/// deleted/dead comments omit `by` and `text`; requiring them would fail the
/// decode and drop the whole comment.
nonisolated struct FirebaseCommentData: Codable, Sendable {
    let id: Int
    let by: String?
    let kids: [Int]?
    let parent: Int?
    let text: String?
    let time: Int?
    let deleted: Bool?
    let dead: Bool?
}

/// The kind of any item and its parent, read from the Firebase `item` endpoint
/// when all that's known is an id — a link to it, say — and not yet whether
/// it's a story or a comment.
nonisolated struct FirebaseItemHeader: Codable, Sendable {
    /// `story`, `comment`, `job`, `poll`, or `pollopt`.
    let type: String?
    let parent: Int?
    /// For a `pollopt`, the poll it belongs to. (Options have no `parent`.)
    let poll: Int?
}

/// A user as returned by the official Firebase HN `user` endpoint.
///
/// `submitted` lists the ids of everything the user has posted, **newest
/// first**. That ordering is what makes it the one realtime way to recover the
/// id of a comment we've just written, which HN's comment form never reports
/// back. It's optional because an account that has never posted omits it.
nonisolated struct FirebaseUserData: Codable, Sendable {
    let id: String
    let submitted: [Int]?
}

// MARK: - Service

/// The official Firebase HN API: realtime story lists, items and users.
struct FirebaseAPIService {
    static let baseUri = "https://hacker-news.firebaseio.com"

    let transport: any HTTPTransport

    // MARK: Requests

    static func storyIdsURL(kind: FeedKind) -> String {
        let list = switch kind {
        case .topStories: "topstories"
        case .bestStories: "beststories"
        case .newStories: "newstories"
        case .askStories: "askstories"
        case .showStories: "showstories"
        case .jobStories: "jobstories"
        }
        return "\(baseUri)/v0/\(list).json?print=pretty"
    }

    static func itemURL(id: Int) -> String {
        "\(baseUri)/v0/item/\(id).json?print=pretty"
    }

    static func userURL(username: String) -> String {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return "\(baseUri)/v0/user/\(encoded).json?print=pretty"
    }

    // MARK: Fetching

    func getStoryIdsAsync(kind: FeedKind) async -> [Int] {
        await transport.json(fromURL: Self.storyIdsURL(kind: kind)) ?? []
    }

    func getStoryAsync(id: Int) async -> FirebaseStoryData? {
        await transport.json(fromURL: Self.itemURL(id: id))
    }

    func getUserAsync(username: String) async -> FirebaseUserData? {
        await transport.json(fromURL: Self.userURL(username: username))
    }

    /// Just enough of any item to say what it is and what it hangs from.
    func getItemHeaderAsync(id: Int) async -> FirebaseItemHeader? {
        await transport.json(fromURL: Self.itemURL(id: id))
    }

    func getPollOptionAsync(id: Int) async -> FirebasePollOptionData? {
        await transport.json(fromURL: Self.itemURL(id: id))
    }

    func getCommentAsync(id: Int) async -> FirebaseCommentData? {
        await transport.json(fromURL: Self.itemURL(id: id))
    }
}
