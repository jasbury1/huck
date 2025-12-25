//
//  Story.swift
//  HuckApp
//
//  Created by James Asbury on 12/24/25.
//

struct Story: Codable {
    let title: String
    let by: String
    let score: Int
    let kids: [Int]
    let time: Int
    let url: String?
    let text: String?
}
