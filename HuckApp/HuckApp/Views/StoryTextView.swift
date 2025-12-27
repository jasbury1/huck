//
//  StoryTextView.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

import SwiftUI

struct CommentCellView: View {
    @State private var commentData: Comment
    private var indentationLevel = 0
    
    init(commentData: Comment) {
        self.commentData = commentData
        indentationLevel = commentData.nestingLevel
    }
    
    var body: some View {
        HStack{
            ForEach(0..<indentationLevel, id:\.self) { _ in
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 1)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(commentData.author).font(.headline)
                Text(commentData.text)
                Divider()
            }
            Spacer()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct StoryTextView: View {
    let storyId: Int
    
    @State private var storyData: StoryModel
    @State private var commentFetcher: CommentFetcher
    
    init(storyId: Int) {
        self.storyId = storyId
        self.storyData = StoryModel(id: storyId)
        self.commentFetcher = CommentFetcher(id: storyId)
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
                ForEach(commentFetcher.comments, id: \.id) { comment in
                    CommentCellView(commentData: comment)
                }
            }
        }
        .listStyle(.inset)
        .task {
            await storyData.fetchData()
            await commentFetcher.fetchComments()
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
    StoryTextView(storyId: 46391572)
}

