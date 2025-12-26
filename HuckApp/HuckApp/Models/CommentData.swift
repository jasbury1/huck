//
//  CommentData.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

class CommentData {
    var id: Int
    var nestingLevel: Int
    var parent: CommentData?
    var children: [CommentData]
    
    init(id: Int) {
        self.id = id
        self.nestingLevel = 0
        children = [CommentData]()
    }
}
