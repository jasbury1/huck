//
//  AlgoliaAPIService.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import Foundation
import OSLog

// MARK: - Algolia Response Data

/// A single item (story or comment) as returned by the Algolia `items` endpoint.
nonisolated struct AlgoliaItemData: Codable, Sendable {
    let id: Int
    let createdAt: String
    let createdAtI: Int
    let author: String
    let title: String?
    let url: String?
    let text: String?
    let points: Int?
    let parentId: Int?
    let children: [AlgoliaItemData]?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case createdAtI = "created_at_i"
        case author
        case title
        case url
        case text
        case points
        case parentId = "parent_id"
        case children
    }
}

/// A user profile as returned by the Algolia `users` endpoint.
nonisolated struct AlgoliaUserData: Codable, Sendable {
    let username: String
    let about: String?
    let karma: Int?
    let created: Int?
    let submitted: [Int]?
}

private nonisolated struct AlgoliaSearchResponse: Codable, Sendable {
    let hits: [AlgoliaHit]
    let nbPages: Int
}

private nonisolated struct AlgoliaHit: Codable, Sendable {
    let objectID: String
}

private nonisolated struct AlgoliaCommentSearchResponse: Codable, Sendable {
    let hits: [AlgoliaCommentHit]
    let nbPages: Int
}

private nonisolated struct AlgoliaCommentHit: Codable, Sendable {
    let objectID: String
    let author: String?
    let commentText: String?
    let storyTitle: String?
    let storyId: Int?
    let createdAtI: Int

    enum CodingKeys: String, CodingKey {
        case objectID
        case author
        case commentText = "comment_text"
        case storyTitle = "story_title"
        case storyId = "story_id"
        case createdAtI = "created_at_i"
    }
}

// MARK: - Service

struct AlgoliaAPIService {
    private static let baseUri = "https://hn.algolia.com/api/v1"

    /// Results per search request. Larger than a screenful on purpose: the API
    /// is capped at 10,000 requests an hour, and a bigger page means a long
    /// scroll spends fewer of them.
    static let defaultHitsPerPage = 30

    /// One line per search request sent. Filter Console/Xcode by this category
    /// to audit what the hourly allowance is actually being spent on — the
    /// debouncing and result reuse upstream are only as good as this is quiet.
    /// The query text is deliberately absent: it's what someone typed.
    private static let searchLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "HuckApp",
        category: "AlgoliaSearch"
    )

    static func getItemById(id: Int) async -> AlgoliaItemData? {
        print("Calling Algolia API")
        //Ex: http://hn.algolia.com/api/v1/items/1
        let url = "\(baseUri)/items/\(id)"
        guard let item: AlgoliaItemData = await WebService().downloadData(fromURL: url) else {
            print("Algolia API returned nil")
            return nil
        }
        print("Item: \(item.title ?? "No title")")
        return item
    }

    static func getUserData(_ username: String) async -> AlgoliaUserData? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let url = "\(baseUri)/users/\(encoded)"
        guard let user: AlgoliaUserData = await WebService().downloadData(fromURL: url) else {
            return nil
        }
        return user
    }

    // MARK: - Search

    /// Searches the `story`-shaped indexes and returns the matching item ids.
    ///
    /// Only ids come back because every story surface in the app renders from
    /// `StoryModel`, which reads details through `StoryCache`. The hits do carry
    /// title/url/points, but adopting them would mean a second, subtly different
    /// story type — and the cache fetch that replaces it is a Firebase request,
    /// which doesn't draw on Algolia's hourly allowance.
    static func searchStoryIds(
        query: String = "",
        tags: [String] = [],
        numericFilters: [String] = [],
        page: Int = 0,
        hitsPerPage: Int = defaultHitsPerPage
    ) async -> (ids: [Int], hasMore: Bool) {
        guard let url = searchURL(
            query: query, tags: tags, numericFilters: numericFilters,
            page: page, hitsPerPage: hitsPerPage
        ) else {
            return ([], false)
        }
        guard let response: AlgoliaSearchResponse = await WebService().downloadData(fromURL: url) else {
            return ([], false)
        }
        let ids = response.hits.compactMap { Int($0.objectID) }
        return (ids, page + 1 < response.nbPages)
    }

    /// Searches the comment index, returning comments ready to display.
    static func searchComments(
        query: String = "",
        tags: [String] = [],
        numericFilters: [String] = [],
        page: Int = 0,
        hitsPerPage: Int = defaultHitsPerPage
    ) async -> (comments: [UserComment], hasMore: Bool) {
        guard let url = searchURL(
            query: query, tags: tags, numericFilters: numericFilters,
            page: page, hitsPerPage: hitsPerPage
        ) else {
            return ([], false)
        }
        guard let response: AlgoliaCommentSearchResponse = await WebService().downloadData(fromURL: url) else {
            return ([], false)
        }
        let comments = response.hits.compactMap { hit -> UserComment? in
            guard let id = Int(hit.objectID), let text = hit.commentText else { return nil }
            return UserComment(
                id: id,
                author: hit.author ?? "",
                text: text.normalizeHtmlText(),
                storyTitle: hit.storyTitle,
                storyId: hit.storyId,
                timestamp: Date(timeIntervalSince1970: TimeInterval(hit.createdAtI))
            )
        }
        return (comments, page + 1 < response.nbPages)
    }

    /// Builds a `/search` URL. `URLComponents` handles the percent-encoding,
    /// with one correction: it leaves `+` alone, which the server would read as
    /// a space — and "C++" is an entirely ordinary thing to search Hacker News
    /// for.
    private static func searchURL(
        query: String,
        tags: [String],
        numericFilters: [String],
        page: Int,
        hitsPerPage: Int
    ) -> String? {
        guard var components = URLComponents(string: "\(baseUri)/search") else { return nil }
        var items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "hitsPerPage", value: String(hitsPerPage)),
        ]
        if !tags.isEmpty {
            items.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
        }
        if !numericFilters.isEmpty {
            items.append(URLQueryItem(name: "numericFilters", value: numericFilters.joined(separator: ",")))
        }
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        let tagList = tags.joined(separator: ",")
        let numericList = numericFilters.joined(separator: ",")
        searchLog.info(
            "Search request: tags=[\(tagList, privacy: .public)] numericFilters=[\(numericList, privacy: .public)] page=\(page, privacy: .public) hitsPerPage=\(hitsPerPage, privacy: .public)"
        )
        return components.url?.absoluteString
    }

    // MARK: - User feeds

    /// Stories submitted by a user — the same search endpoint, narrowed to one
    /// author with no query text.
    static func getUserStoryIds(username: String, page: Int = 0) async -> (ids: [Int], hasMore: Bool) {
        await searchStoryIds(tags: ["story", "author_\(username)"], page: page, hitsPerPage: 20)
    }

    static func getUserComments(username: String, page: Int = 0) async -> (comments: [UserComment], hasMore: Bool) {
        await searchComments(tags: ["comment", "author_\(username)"], page: page, hitsPerPage: 20)
    }
}
