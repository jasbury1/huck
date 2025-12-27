//
//  Comment.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//
import SwiftUI

@Observable
class Comment {
    var id: Int
    var nestingLevel: Int
    var text: String
    var points: Int
    var author: String
    var timestamp: Date
    var parent: Comment?
    var children: [Comment]
    
    init(item: ItemData) {
        self.id = item.id
        self.nestingLevel = 0
        self.text = item.text ?? ""
        self.points = item.points ?? 0
        self.author = item.author
        self.parent = nil
        self.children = []
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(item.createdAtI))
    }
}
