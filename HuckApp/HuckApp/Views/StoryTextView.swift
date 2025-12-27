//
//  StoryTextView.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

import SwiftUI

struct CommentCellView: View {
    private var commentData: CommentModel
    
    init(commentData: CommentModel) {
        self.commentData = commentData
    }
    
    var body: some View {
        Text("Comment ID: \(commentData.id)")
            ForEach(commentData.children, id: \.id) { comment in
                Text("Child")
        }
    }
}

struct StoryTextView: View {
    let storyId: Int
    
    @State private var storyData: StoryModel
    @State private var rootComments: [CommentModel] = []
    
    init(storyId: Int) {
        self.storyId = storyId
        self.storyData = StoryModel(id: storyId)
    }
    
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 20) {
                Text(storyData.title)
                    .font(.title2)
                    .fontWeight(.heavy)
                Text(storyData.text ?? "")
                Text("By \(storyData.by)")
                    .font(.callout)
                    .foregroundStyle(.gray)
                HStack {
                    Image(systemName: "arrow.up")
                        .foregroundColor(.gray)
                    Text("\(storyData.score)")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    Image(systemName: "bubble")
                        .foregroundColor(.gray)
                    Text("\(storyData.commentCount)")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    Image(systemName: "clock")
                        .foregroundColor(.gray)
                    //Text("\(observableStory.story?.time ?? 0)")
                    Text("1h")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    Image(systemName: "paperplane")
                        .foregroundColor(.gray)
                    Image(systemName: "bookmark")
                        .foregroundColor(.gray)
                }
                Divider()
                //Spacer()
                //CommentView(storyId: storyId)
                ForEach(rootComments, id: \.id) { commentData in
                    CommentCellView(commentData: commentData)
                }
            }
        }
        .listStyle(.inset)
        .task {
            await storyData.fetchData()
            await rootComments = getRootComments(storyId: storyId)
        }
    }
}

@Observable
class CommentSectionData {
    var storyIds: [Int] = []
    
    func fetchStoryIds(filter: StoryFilter) async {
        let ids = await getStoryIdsAsync(filter: filter)
        self.storyIds = ids
    }
}

#Preview {
    StoryTextView(storyId: 123123)
}

