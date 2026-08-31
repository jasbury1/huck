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
            SortableHeader(title: title)
            tabBarButtons
            Divider()
            pages
        }
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
    
    /// A single tab pill. Unselected it shows only its symbol on a neutral fill;
    /// selected it fills with the tab's color and expands to include the title.
    private func tabPill(for tab: ContentTab) -> some View {
        let selected = currentTab == tab
        return Button {
            withAnimation(.snappy(duration: 0.3)) { currentTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                if selected {
                    Text(tab.title)
                        .fontWeight(.semibold)
                        .fixedSize()
                }
            }
            .font(.subheadline)
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, selected ? 14 : 11)
            .background {
                Capsule(style: .continuous)
                    .fill(selected ? AnyShapeStyle(tab.color) : AnyShapeStyle(Color(.secondarySystemFill)))
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    var tabBarButtons: some View {
        HStack(spacing: 10) {
            ForEach(availableTabs, id: \.self) { tab in
                tabPill(for: tab)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(cardBackgroundColor)
        // Animate the pills for swipe-driven selection changes too.
        .animation(.snappy(duration: 0.3), value: currentTab)
    }
}

