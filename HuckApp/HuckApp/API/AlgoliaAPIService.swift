//
//  AlgoliaAPIService.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

struct AlgoliaAPIService {
    private static let baseUri = "https://hn.algolia.com/api/v1"
    
    static func getItemById(id: Int) async -> ItemData? {
        //Ex: http://hn.algolia.com/api/v1/items/1
        let url = "\(baseUri)/items/\(id)"
        guard let item: ItemData = await WebService().downloadData(fromURL: url) else {
            print("Algolia API returned nil")
            return nil
        }
        print("Item: \(item.title ?? "No title")")
        return item
    }
}

