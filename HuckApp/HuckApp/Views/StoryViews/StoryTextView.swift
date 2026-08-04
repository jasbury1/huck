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
        HStack(spacing: 8) {
            // Full-height indentation rails. Because the row has no vertical
            // insets (see `.listRowInsets` in StoryTextView), a rail reaches the
            // top and bottom edges of its row, so rails on adjacent same-level
            // comments meet to form one continuous line.
            ForEach(0..<indentationLevel, id:\.self) { _ in
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(commentData.author).font(.headline)
                    Spacer()
                    Text(commentData.timestamp.ageString())
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }
                Text(try! AttributedString(markdown: commentData.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    .font(.callout)
                //Text(commentData.text)
                Divider()
            }
            // Padding lives inside the text column so the rails stay full-height.
            .padding(.top, 8)
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
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    Text(storyData.title)
                        .font(.title2)
                        .fontWeight(.heavy)
                    if storyData.text != nil {
                        Text(try! AttributedString(markdown: storyData.text!, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                        //Text(storyData.text!)
                    }
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
                        Text(storyData.timestamp.ageString())
                            .font(.footnote)
                            .foregroundStyle(.gray)
                        Image(systemName: "paperplane")
                            .foregroundColor(.gray)
                        Image(systemName: "bookmark")
                            .foregroundColor(.gray)
                    }
                }
            }

            Section {
                ForEach(commentFetcher.comments, id: \.id) { comment in
                    CommentCellView(commentData: comment)
                        // The cell draws its own Divider; hide the List's
                        // built-in row separator so lines don't double up.
                        .listRowSeparator(.hidden)
                        // No vertical inset, so rows meet edge-to-edge and the
                        // indentation rails connect between comments.
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            } header: {
                commentsHeader
            }
        }
        .listStyle(.inset)
        .task {
            await storyData.fetchData()
            await commentFetcher.fetchComments()
        }
    }

    /// Pinned section header for the comments. Plain/inset list styles keep
    /// section headers stuck to the top while their section scrolls.
    private var commentsHeader: some View {
        HStack {
            Text("Comments")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                Button("Hot") {}
                Button("Newest") {}
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            Button {
                // TODO: More options
            } label: {
                Image(systemName: "ellipsis")
            }
            .padding(.leading, 12)
        }
        // Section headers are uppercased by default; keep the title as written.
        .textCase(nil)
    }
}

@Observable
class CommentSectionData {
    var storyIds: [Int] = []
    
    func fetchStoryIds(filter: StoryFilter) async {
        let ids = await HackerNewsAPI.getStoryIds(filter: filter)
        self.storyIds = ids
    }
}

#Preview {
    StoryTextView(storyId: 46391572)
}

