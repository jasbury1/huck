//
//  StoryCellView.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import SwiftUI

enum ThumbnailType {
    case loading
    case image(Image)
    case failed
    case text
}

struct StoryCellView: View {
    let storyId: Int
    
    @State private var storyData: StoryModel
    
    @State private var thumbnailStatus: ThumbnailType = .loading

    @Binding var path: NavigationPath
    
    init(storyId: Int, path: Binding<NavigationPath>) {
        self.storyId = storyId
        self.storyData = StoryModel(id: storyId)
        self._path = path
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                switch storyData.storyType {
                case .link:
                    Button(action: {
                        path.append(ItemNavigation.linkStory(id: storyId, url: storyData.url!))
                    }) {
                        Text(storyData.title)
                    }
                    .buttonStyle(.plain)
                case .text:
                    Button(action: {
                        path.append(ItemNavigation.textStory(id: storyId))
                    }) {
                        Text(storyData.title)
                    }
                    .buttonStyle(.plain)
                case .unknown:
                    Text(storyData.title)
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
            // The image thumbnail
            VStack() {
                ZStack() {
                    switch thumbnailStatus {
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
            }
            .clipped()
            .frame(width: 70, height: 70)
            .cornerRadius(15)
        }
        .task {
            await storyData.fetchData()
            await fetchThumbnail()
        }
        
    }
    
    private func fetchThumbnail() async {
        guard storyData.storyType == .link else {
            thumbnailStatus = .text
            return
        }
        guard let url = storyData.url else {
            thumbnailStatus = .failed
            return
        }

        // ThumbnailCache fetches the page's Open Graph image (favicon fallback)
        // with a plain URLSession and caches the result, so scrolling never
        // re-fetches. It replaces the heavyweight LPMetadataProvider path.
        if let image = await ThumbnailCache.shared.thumbnail(for: url) {
            thumbnailStatus = .image(Image(uiImage: image))
        } else {
            thumbnailStatus = .failed
        }
    }
}
