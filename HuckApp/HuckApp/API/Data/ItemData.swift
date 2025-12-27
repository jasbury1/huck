//
//  ItemData.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

struct ItemData: Codable {
    let id: Int
    let createdAt: String
    let createdAtI: Int
    let author: String
    let title: String?
    let url: String?
    let text: String?
    let points: Int?
    let parentId: Int?
    let children: [ItemData]?
    
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
