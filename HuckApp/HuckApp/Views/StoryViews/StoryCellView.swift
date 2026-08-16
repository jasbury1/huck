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

    /// Opens link posts in the standardized in-app Safari browser.
    @Environment(\.openInAppBrowser) private var openInAppBrowser

    /// Shared interaction state (drives the upvote arrow's color) and the upvote
    /// action (handles the login gate and the vote toggle).
    @Environment(InteractionStore.self) private var interactionStore
    @Environment(\.upvote) private var upvote

    private var storyId: Int { storyData.id }

    private var isUpvoted: Bool { interactionStore.interaction(for: storyId).isUpvoted }

    /// The fetched score plus any optimistic vote adjustment from the shared store,
    /// so this row stays in sync with the story's other views.
    private var displayedScore: Int { storyData.score + interactionStore.scoreDelta(for: storyId) }

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
                        // Button to upvote the post. The arrow turns orange once
                        // upvoted; the action handles login and the toggle.
                        Button(action: {
                            upvote(storyData)
                        }) {
                            HStack {
                                Image(systemName: "arrow.up")
                                    .foregroundColor(isUpvoted ? .orange : .gray)
                                Text("\(displayedScore)")
                                    .font(.footnote)
                                    .foregroundStyle(isUpvoted ? .orange : .gray)
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
        StoryThumbnailView(status: storyData.thumbnailStatus)
    }

    /// Navigates to the story: the linked page opens in the in-app Safari
    /// browser, a text post pushes the comments view. Shared by the title and
    /// the thumbnail.
    private func openStory() {
        switch storyData.storyType {
        case .link:
            if let url = storyData.url {
                openInAppBrowser(url)
            }
        case .text:
            path.append(ItemNavigation.textStory(id: storyId))
        case .unknown:
            break
        }
    }
}
