//
//  TabableContent.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

struct TabableContentView: View {
    @State private var currentTab: ContentTab = .posts

    private let title: String
    /// The story feed shown in the Posts tab (e.g. a user's favorited stories).
    private let postsFeed: StoryFeed
    /// Placeholder shown when the Posts tab has no stories. Caller-supplied so
    /// the wording matches the context (favorites vs. likes).
    private let postsEmptyState: EmptyFeedView
    /// Placeholder shown when the Comments tab has no comments.
    private let commentsEmptyState: EmptyFeedView
    @Binding private var path: NavigationPath

    private let cardBackgroundColor = Color(UIColor.systemBackground)

    private var availableTabs: [ContentTab] {
        var tabs: [ContentTab] = [.posts, .comments]
        // TODO: This is so that this view can later be purposed for the logged in user's profile
        if false {
            tabs.append(.recentlyViewed)
        }
        return tabs
    }

    init(
        title: String,
        postsFeed: StoryFeed,
        postsEmptyState: EmptyFeedView,
        commentsEmptyState: EmptyFeedView,
        path: Binding<NavigationPath>
    ) {
        self.title = title
        self.postsFeed = postsFeed
        self.postsEmptyState = postsEmptyState
        self.commentsEmptyState = commentsEmptyState
        self._path = path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBarButtons
                .padding(.top, 8)
            Divider()
            pages
        }
        // The page title lives in the navigation bar — centered, and matching
        // every other pushed screen — rather than in an in-content header.
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Horizontally-paged tab content; both tapping a pill and swiping drive
    /// `currentTab`.
    private var pages: some View {
        TabView(selection: $currentTab) {
            ForEach(availableTabs, id: \.self) { tab in
                content(for: tab)
                    .tag(tab)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// The scrollable content for a tab. Each tab lives in its own scroll view
    /// so empty-state placeholders (posts vs comments) sit at the same height.
    @ViewBuilder
    private func content(for tab: ContentTab) -> some View {
        ScrollView {
            switch tab {
            case .posts:
                StoryList(
                    feed: postsFeed,
                    path: $path,
                    emptyState: postsEmptyState
                )
            case .comments:
                // TODO: Show the user's favorited/liked comments once that feed exists.
                commentsEmptyState
            case .recentlyViewed:
                EmptyView()
            }
        }
    }
    
    var tabBarButtons: some View {
        PillTabBar(tabs: availableTabs, selection: $currentTab)
            .background(cardBackgroundColor)
    }
}

