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
}

