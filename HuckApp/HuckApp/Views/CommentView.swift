//
//  CommentView.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

import SwiftUI



struct CommentView: View {
    let storyId: Int
    @State private var comments: [CommentModel] = []
    
    var body: some View {
        Text("ID: \(storyId)")
        ForEach(comments, id: \.id) { commentData in
            CommentCellView(commentData: commentData)
        }
        .task(id: storyId){
            print("Calling task for Story ID: \(storyId)")
            //wait comments = getCommentThread(storyId: storyId)
        }
        .onAppear {
            print("Story ID: \(storyId)")
        }
    }
}
