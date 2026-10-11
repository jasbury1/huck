//
//  StoryCellView.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import SwiftUI

struct StoryCellView: View {
    /// The story's model, owned and retained by its feed (`StoryFeed`). Reading its
    /// `@Observable` properties in the body keeps the row in sync, and because
    /// the same instance survives recycling the row never resets to a placeholder.
    let storyData: StoryModel

    @Binding var path: NavigationPath

    /// Opens link posts in the standardized in-app Safari browser.
    @Environment(\.openInAppBrowser) private var openInAppBrowser
    @Environment(\.openThread) private var openThread

    /// Which side the thumbnail sits on; chosen for the window's shape.
    @Environment(\.storyRowLayout) private var layout

    /// Shared interaction state (drives the upvote arrow's color) and the upvote
    /// action (handles the login gate and the vote toggle).
    @Environment(InteractionStore.self) private var interactionStore
    @Environment(\.upvote) private var upvote
    @Environment(\.favorite) private var favorite

    /// Per-user recently-viewed record: read to grey a seen title, written when
    /// the story is opened.
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore

    /// Whether to show the link's domain after the title; set in Settings.
    @AppStorage(FeedSettings.displayStoryDomainKey) private var displayStoryDomain = true

    private var storyId: Int { storyData.id }

    private var isUpvoted: Bool { interactionStore.interaction(for: storyId).isUpvoted }
    private var isFavorited: Bool { interactionStore.interaction(for: storyId).isFavorited }

    /// Whether the current user has already opened this story — its title is greyed.
    private var isViewed: Bool { recentlyViewedStore.hasViewed(storyId) }

    /// The fetched score plus any optimistic vote adjustment from the shared store,
    /// so this row stays in sync with the story's other views.
    private var displayedScore: Int { storyData.score + interactionStore.scoreDelta(for: storyId) }

    init(model: StoryModel, path: Binding<NavigationPath>) {
        self.storyData = model
        self._path = path
    }

    var body: some View {
        HStack {
            if layout == .wide {
                thumbnailButton
                    // More room than the stack's spacing alone, so the image
                    // doesn't crowd the title beside it.
                    .padding(.trailing, 8)
            }
            VStack(alignment: .leading) {
                switch storyData.storyType {
                case .unknown:
                    titleText
                case .link, .text:
                    Button(action: openStory) {
                        titleText
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
                            openThread(.textStory(id: storyId), from: $path)
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
                        
                        // Share the post's Hacker News page via the share sheet.
                        ShareLink(item: storyData.hackerNewsURL) {
                            Image(systemName: "paperplane")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                        
                        // Favorite the post. The heart fills red once favorited;
                        // the action handles login and the toggle.
                        Button(action: {
                            favorite(storyData)
                        }) {
                            Image(systemName: isFavorited ? "heart.fill" : "heart")
                                .foregroundColor(isFavorited ? .red : .gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            if layout == .standard {
                thumbnailButton
            }
        }
        .task {
            await storyData.fetchData()
        }
    }

    /// The title with the link's domain appended in smaller, secondary text when
    /// the setting is on. Built as a single `Text` so the domain flows right after
    /// the title and wraps onto the next line when it doesn't fit.
    private var titleText: Text {
        let title = Text(storyData.title)
            .foregroundStyle(isViewed ? Color.secondary : Color.primary)

        guard displayStoryDomain, let domain = storyData.displayDomain else {
            return title
        }

        let domainText = Text("(\(domain))")
            .font(.footnote)
            .foregroundStyle(Color.secondary)
        return Text("\(title)  \(domainText)")
    }

    /// The thumbnail, navigating to the story just like the title does.
    @ViewBuilder
    private var thumbnailButton: some View {
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

    /// The image thumbnail (or its placeholder while loading / for text posts).
    private var thumbnail: some View {
        StoryThumbnailView(status: storyData.thumbnailStatus)
    }

    /// Navigates to the story: the linked page opens in the in-app Safari
    /// browser, a text post pushes the comments view. Shared by the title and
    /// the thumbnail. Either counts as viewing the story, so it's recorded here;
    /// opening the comments separately is recorded by `StoryTextView`.
    private func openStory() {
        switch storyData.storyType {
        case .link:
            if let url = storyData.url {
                recentlyViewedStore.recordView(storyId)
                openInAppBrowser(url)
            }
        case .text:
            recentlyViewedStore.recordView(storyId)
            openThread(.textStory(id: storyId), from: $path)
        case .unknown:
            break
        }
    }
}

/// How a story row arranges its parts. `standard` is the iPhone row, with the
/// thumbnail trailing. `wide` moves the thumbnail to the leading edge, for a
/// window shaped wider than an iPhone's — an iPhone Duo, open or closed. Either
/// way the author and actions sit under the title.
enum StoryRowLayout {
    case standard
    case wide

    /// The window's short side over its long side, above which it's wider than
    /// any iPhone's. Face ID iPhones are about 0.46 and the SE 0.56 (375 × 667);
    /// the closed iPhone Duo is 0.59 (382 × 644), and it and iPads only get
    /// squarer from there. A ratio holds in either orientation, so a sideways
    /// iPhone stays standard.
    private static let minimumAspectRatio: CGFloat = 0.58

    init(windowSize: CGSize) {
        let shortSide = min(windowSize.width, windowSize.height)
        let longSide = max(windowSize.width, windowSize.height)
        let isWide = longSide > 0 && shortSide / longSide > Self.minimumAspectRatio
        self = isWide ? .wide : .standard
    }
}

extension EnvironmentValues {
    @Entry var storyRowLayout = StoryRowLayout.standard
}
