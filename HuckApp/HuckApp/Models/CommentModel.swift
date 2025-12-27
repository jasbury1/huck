//
//  CommentData.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import SwiftUI

@Observable
class CommentModel {
    var id: Int
    var nestingLevel: Int
    var parent: CommentModel?
    var children: [CommentModel]
    
    init(id: Int) {
        self.id = id
        self.nestingLevel = 0
        children = [CommentModel]()
    }
}
