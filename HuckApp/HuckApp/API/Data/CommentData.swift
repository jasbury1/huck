//
//  Comment.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

struct CommentData: Codable {
    let by: String
    let id: Int
    let kids: [Int]
    let parent: Int
    let text: String
    let time: Int
}
