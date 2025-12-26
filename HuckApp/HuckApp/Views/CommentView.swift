//
//  CommentView.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

import SwiftUI

struct CommentCellView: View {
    //@State private var commentData: CommentData
    
    var body: some View {
        Text("Comment")
    }
}

struct CommentView: View {
    let storyId: Int
    
    var body: some View {
        ForEach([1, 2, 3, 4, 5], id: \.self) { id in
            CommentCellView()
        }
    }
}
