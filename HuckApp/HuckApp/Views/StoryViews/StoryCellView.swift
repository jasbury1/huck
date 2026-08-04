//
//  StoryCellView.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import SwiftUI

struct StoryCellView: View {
    /// The story's model, owned and retained by `StoriesFeedData`. Reading its
    /// `@Observable` properties in the body keeps the row in sync, and because
    /// the same instance survives recycling the row never resets to a placeholder.
    let storyData: StoryModel

    @Binding var path: NavigationPath

    private var storyId: Int { storyData.id }

    init(model: StoryModel, path: Binding<NavigationPath>) {
        self.storyData = model
        self._path = path
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                switch storyData.storyType {
                case .unknown:
                    Text(storyData.title)
                case .link, .text:
                    Button(action: openStory) {
                        Text(storyData.title)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("")
                // Clicking the username takes you to that user's page
                VStack(alignment: .leading){
                    Button(action: {
                        path.append(ItemNavigation.userProfile(user: storyData.by))
                    }) {
                        Text("\(storyData.by)")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                    
                    HStack {
                        // Button to upvote the post
                        Button(action: {
                            // TODO
                        }) {
                            HStack {
                                Image(systemName: "arrow.up")
                                    .foregroundColor(.gray)
                                Text("\(storyData.score)")
                                    .font(.footnote)
                                    .foregroundStyle(.gray)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Button to view the comments
                        Button(action: {
                            path.append(ItemNavigation.textStory(id: storyId))
                        }) {
                            HStack {
                                Image(systemName: "bubble")
                                    .foregroundColor(.gray)
                                Text("\(storyData.commentCount)")
                                    .font(.footnote)
                                    .foregroundStyle(.gray)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Timestamp
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                        Text(storyData.timestamp.ageString())
                            .font(.footnote)
                            .foregroundStyle(.gray)
                        
                        // Share the post
                        Image(systemName: "paperplane")
                            .foregroundColor(.gray)
                        
                        // Bookmark the post
                        Image(systemName: "bookmark")
                            .foregroundColor(.gray)
                    }
                }
            }
            Spacer()
            // The thumbnail navigates to the story just like the title does.
            switch storyData.storyType {
            case .unknown:
                thumbnail
            case .link, .text:
                Button(action: openStory) {
                    thumbnail
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            await storyData.fetchData()
        }
    }

    /// The image thumbnail (or its placeholder while loading / for text posts).
    private var thumbnail: some View {
        ZStack {
            switch storyData.thumbnailStatus {
                //case .loading:
                //ProgressView()
            case .image(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .text:
                Color(.systemGray6)
                Image(systemName: "text.alignleft")
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .foregroundStyle(Color(.systemFill))
            case .failed, .loading:
                Color(.quaternaryLabel)
                Image(systemName: "safari")
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .foregroundStyle(Color(.systemFill))
            }
        }
        .clipped()
        .frame(width: 70, height: 70)
        .cornerRadius(15)
    }

    /// Navigates to the story: the linked page for link posts, the comments
    /// view for text posts. Shared by the title and the thumbnail.
    private func openStory() {
        switch storyData.storyType {
        case .link:
            if let url = storyData.url {
                path.append(ItemNavigation.linkStory(id: storyId, url: url))
            }
        case .text:
            path.append(ItemNavigation.textStory(id: storyId))
        case .unknown:
            break
        }
    }
}
