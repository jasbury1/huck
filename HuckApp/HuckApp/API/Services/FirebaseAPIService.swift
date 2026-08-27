//
//  FirebaseAPIService.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import Foundation

// MARK: - Firebase Response Data

/// A story item as returned by the official Firebase HN `item` endpoint.
struct FirebaseStoryData: Codable {
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
}

/// A comment item as returned by the official Firebase HN `item` endpoint.
///
/// Most fields are optional because leaf comments omit `kids` and
/// deleted/dead comments omit `by` and `text`; requiring them would fail the
/// decode and drop the whole comment.
struct FirebaseCommentData: Codable {
    let id: Int
    let by: String?
    let kids: [Int]?
    let parent: Int?
    let text: String?
    let time: Int?
    let deleted: Bool?
    let dead: Bool?
}

// MARK: - Service

struct FirebaseAPIService {
    static let baseUri = "https://hacker-news.firebaseio.com"

    static func getStoryIdsAsync(filter: StoryFilter) async -> [Int] {
        let url = switch filter {
        case .topStories:
            "\(baseUri)/v0/topstories.json?print=pretty"
        case .bestStories:
            "\(baseUri)/v0/beststories.json?print=pretty"
        case .newStories:
            "\(baseUri)/v0/newstories.json?print=pretty"
        case .askStories:
            "\(baseUri)/v0/askstories.json?print=pretty"
        case .showStories:
            "\(baseUri)/v0/showstories.json?print=pretty"
        case .jobStories:
            "\(baseUri)/v0/jobstories.json?print=pretty"
        }
        guard let stories: [Int] = await WebService().downloadData(fromURL: url) else {
            return []
        }
        return stories
    }

    static func getStoryAsync(id: Int) async -> FirebaseStoryData? {
        let url = "\(baseUri)/v0/item/\(id).json?print=pretty"
        guard let story: FirebaseStoryData = await WebService().downloadData(fromURL: url) else {
            return nil
        }
        return story
    }

    static func getCommentAsync(id: Int) async -> FirebaseCommentData? {
        let url = "\(baseUri)/v0/item/\(id).json?print=pretty"
        guard let comment: FirebaseCommentData = await WebService().downloadData(fromURL: url) else {
            return nil
        }
        return comment
    }
}
