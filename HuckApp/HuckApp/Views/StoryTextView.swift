//
//  StoryTextView.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

import SwiftUI

struct StoryTextView: View {
    let storyId: Int
    
    @State private var storyData: StoryData
    
    init(storyId: Int) {
        self.storyId = storyId
        self.storyData = StoryData(id: storyId)
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
                CommentView(storyId: storyId)
            }
        }
        .listStyle(.inset)
        .task {
            await storyData.fetchData()
        }
    }
}

#Preview {
    StoryTextView(storyId: 123123)
}

