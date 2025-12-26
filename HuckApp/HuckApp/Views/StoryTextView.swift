//
//  StoryTextView.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

import SwiftUI

struct StoryTextView: View {
    let storyId: Int
    @State private var storyData: StoryCellData?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Divider()
            Text(storyData?.title ?? "")
                .font(.title2)
                .fontWeight(.heavy)
            Text(storyData?.text ?? "")
            Text("By \(storyData?.by ?? "")")
                .font(.callout)
                .foregroundStyle(.gray)
            HStack {
                Image(systemName: "arrow.up")
                    .foregroundColor(.gray)
                Text("\(storyData?.score ?? 0)")
                    .font(.footnote)
                    .foregroundStyle(.gray)
                Image(systemName: "bubble")
                    .foregroundColor(.gray)
                Text("\(storyData?.commentCount ?? 0)")
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
            Spacer()
        }.padding(.horizontal, 20)
        .task {
            storyData = await StoryCache.getStory(id: storyId)
        }
    }
}

#Preview {
    StoryTextView(storyId: 123123)
}

