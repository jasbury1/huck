//
//  CommentFetcher.swift
//  HuckApp
//
//  Created by James Asbury on 12/26/25.
//

import SwiftUI

@Observable
class CommentFetcher {
    let id: Int
    var comments: [Comment] = []
    
    init(id: Int) {
        self.id = id
    }
    
    func fetchComments() async {
        print("Fetching Comments")
        comments = await getComments(for: id)
    }
}
