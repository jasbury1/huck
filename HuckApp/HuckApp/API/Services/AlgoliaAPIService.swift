//
//  AlgoliaAPIService.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import Foundation

private struct AlgoliaSearchResponse: Codable {
    let hits: [AlgoliaHit]
    let nbPages: Int
}

private struct AlgoliaHit: Codable {
    let objectID: String
}

private struct AlgoliaCommentSearchResponse: Codable {
    let hits: [AlgoliaCommentHit]
    let nbPages: Int
}

private struct AlgoliaCommentHit: Codable {
    let objectID: String
    let commentText: String?
    let storyTitle: String?
    let storyId: Int?
    let createdAtI: Int

    enum CodingKeys: String, CodingKey {
        case objectID
        case commentText = "comment_text"
        case storyTitle = "story_title"
        case storyId = "story_id"
        case createdAtI = "created_at_i"
    }
}

struct UserCommentResult: Identifiable {
    let id: Int
    let text: String
    let storyTitle: String?
    let storyId: Int?
    let timestamp: Date
}

struct AlgoliaAPIService {
    private static let baseUri = "https://hn.algolia.com/api/v1"

    static func getItemById(id: Int) async -> ItemData? {
        print("Calling Algolia API")
        //Ex: http://hn.algolia.com/api/v1/items/1
        let url = "\(baseUri)/items/\(id)"
        guard let item: ItemData = await WebService().downloadData(fromURL: url) else {
            print("Algolia API returned nil")
            return nil
        }
        print("Item: \(item.title ?? "No title")")
        return item
    }

    static func getUserData(_ username: String) async -> UserData? {
        let url = "\(baseUri)/users/\(username)"
        guard let user: UserData = await WebService().downloadData(fromURL: url) else {
            return nil
        }
        return user
    }

    static func getUserStoryIds(username: String, page: Int = 0) async -> (ids: [Int], hasMore: Bool) {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let url = "\(baseUri)/search?tags=story,author_\(encoded)&hitsPerPage=20&page=\(page)"
        guard let response: AlgoliaSearchResponse = await WebService().downloadData(fromURL: url) else {
            return ([], false)
        }
        let ids = response.hits.compactMap { Int($0.objectID) }
        return (ids, page + 1 < response.nbPages)
    }

    static func getUserComments(username: String, page: Int = 0) async -> (comments: [UserCommentResult], hasMore: Bool) {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let url = "\(baseUri)/search?tags=comment,author_\(encoded)&hitsPerPage=20&page=\(page)"
        guard let response: AlgoliaCommentSearchResponse = await WebService().downloadData(fromURL: url) else {
            return ([], false)
        }
        let comments = response.hits.compactMap { hit -> UserCommentResult? in
            guard let id = Int(hit.objectID), let text = hit.commentText else { return nil }
            return UserCommentResult(
                id: id,
                text: text.normalizeHtmlText(),
                storyTitle: hit.storyTitle,
                storyId: hit.storyId,
                timestamp: Date(timeIntervalSince1970: TimeInterval(hit.createdAtI))
            )
        }
        return (comments, page + 1 < response.nbPages)
    }
}

