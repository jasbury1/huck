//
//  UserPageView.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import SwiftUI

struct UserView: View {
    @State var username: String
    @State var user: User?
    @Binding var path: NavigationPath

    @State private var currentTab: UserTab = .posts
    @State private var userStoryIds: [Int] = []
    /// Retained story models keyed by id, so a post cell that scrolls back into
    /// view renders from its already-populated instance instead of flashing the
    /// placeholder. Mirrors `StoriesFeedData` in the main feed.
    @State private var storyModels: [Int: StoryModel] = [:]
    @State private var currentPage = 0
    @State private var hasMorePages = false
    @State private var isLoadingMore = false

    @State private var userComments: [UserComment] = []
    @State private var commentPage = 0
    @State private var hasMoreComments = false
    @State private var isLoadingMoreComments = false

    // Collapsing-header state. Each tab reports its own vertical scroll offset,
    // so switching tabs reflects that tab's scroll position. The measured heights
    // define how far the header travels and how tall each scroll's top spacer is.
    @State private var scrollOffsets: [UserTab: CGFloat] = [:]
    @State private var collapsibleHeight: CGFloat = 0
    @State private var tabBarHeight: CGFloat = 0

    @Namespace private var namespace
    private let systemBackgroundColor = Color(UIColor.systemBackground)

    // MARK: - Collapse math

    /// Vertical scroll offset of the currently-visible tab (0 at the top).
    private var currentOffset: CGFloat { scrollOffsets[currentTab] ?? 0 }
    /// How far the header is translated up, capped so the tab bar pins at the top.
    private var collapseAmount: CGFloat { min(max(currentOffset, 0), collapsibleHeight) }
    /// 0 when the header is fully expanded, 1 when fully collapsed.
    private var collapseProgress: CGFloat {
        collapsibleHeight > 0 ? collapseAmount / collapsibleHeight : 0
    }
    /// Total header height, used as the top spacer inside each tab's scroll.
    private var headerHeight: CGFloat { collapsibleHeight + tabBarHeight }

    var body: some View {
        ZStack(alignment: .top) {
            tabPager
            collapsingHeader
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // The small nav-bar username fades in as the large one collapses.
                Text(username)
                    .font(.headline)
                    .opacity(collapseProgress)
            }
        }
        .task {
            async let fetchedUser = HackerNewsAPI.getUser(for: username)
            async let firstPage = HackerNewsAPI.getUserStories(username: username, page: 0)
            async let firstCommentPage = HackerNewsAPI.getUserComments(username: username, page: 0)
            let (u, storyResult, commentResult) = await (fetchedUser, firstPage, firstCommentPage)
            user = u
            registerStoryModels(for: storyResult.ids)
            userStoryIds = storyResult.ids
            hasMorePages = storyResult.hasMore
            userComments = commentResult.comments
            hasMoreComments = commentResult.hasMore
        }
    }

    // MARK: - Header

    /// The header overlaid on top of the paged tabs. Its collapsible portion
    /// (large username + karma/about) translates up and fades as the active tab
    /// scrolls, until only the tab bar remains pinned at the top.
    var collapsingHeader: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(username)
                    .font(.largeTitle)
                    .bold()
                userSummary
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(1 - collapseProgress)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsibleHeight = $0 }

            VStack(spacing: 0) {
                tabBarButtons
                Divider()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
        }
        .background(systemBackgroundColor)
        .offset(y: -collapseAmount)
    }

    var userSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Karma: \(user?.karma ?? 0)")
                .foregroundStyle(.secondary)
            if let about = user?.about, !about.isEmpty {
                Text(about)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tabs

    /// Horizontally-paged tab content. Each page is its own vertical lazy scroll,
    /// so only the rows currently on screen are realised — and only those cells
    /// fetch their story data and thumbnail. Both swiping between pages and
    /// tapping a tab drive `currentTab`.
    var tabPager: some View {
        TabView(selection: $currentTab) {
            tabScroll(for: .posts) { postsList }
            tabScroll(for: .comments) { commentsList }
            tabScroll(for: .favorites) { favoritesContent }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// Wraps a tab's content in a scroll view that clears space for the header
    /// and reports its offset back so the header collapses in step.
    @ViewBuilder
    func tabScroll<Content: View>(for tab: UserTab, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight)
                content()
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffsets[tab] = offset
        }
        .tag(tab)
    }

    var tabBarButtons: some View {
        HStack(spacing: 20) {
            ForEach(UserTab.allCases, id: \.self) { tab in
                let selected = currentTab == tab
                Text(tab.title)
                    .font(.body)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.vertical, 8)
                    .onTapGesture {
                        withAnimation(.easeInOut) { currentTab = tab }
                    }
                    .background {
                        if selected {
                            Color.orange
                                .frame(height: 2)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .matchedGeometryEffect(id: "indicator", in: namespace)
                        }
                    }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .background(systemBackgroundColor)
        // Animate the underline for swipe-driven selection changes too.
        .animation(.easeInOut, value: currentTab)
    }

    // MARK: - Tab Content

    var postsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(userStoryIds, id: \.self) { storyId in
                StoryCellView(model: model(for: storyId), path: $path)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider()
            }
            if hasMorePages {
                ProgressView()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        Task { await loadMorePosts() }
                    }
            }
        }
    }

    var commentsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(userComments) { comment in
                UserCommentRow(comment: comment, path: $path)
                Divider()
            }
            if hasMoreComments {
                ProgressView()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        Task { await loadMoreComments() }
                    }
            }
        }
    }

    var favoritesContent: some View {
        Text("Favorites are not publicly available")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }

    /// Creates a retained `StoryModel` for any id that doesn't have one yet.
    private func registerStoryModels(for ids: [Int]) {
        for id in ids where storyModels[id] == nil {
            storyModels[id] = StoryModel(id: id)
        }
    }

    /// The retained model for a story id. Ids are registered as pages load, so
    /// this is a pure synchronous read.
    private func model(for id: Int) -> StoryModel {
        storyModels[id] ?? StoryModel(id: id)
    }

    private func loadMorePosts() async {
        guard !isLoadingMore && hasMorePages else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        let result = await HackerNewsAPI.getUserStories(username: username, page: nextPage)
        registerStoryModels(for: result.ids)
        userStoryIds.append(contentsOf: result.ids)
        currentPage = nextPage
        hasMorePages = result.hasMore
        isLoadingMore = false
    }

    private func loadMoreComments() async {
        guard !isLoadingMoreComments && hasMoreComments else { return }
        isLoadingMoreComments = true
        let nextPage = commentPage + 1
        let result = await HackerNewsAPI.getUserComments(username: username, page: nextPage)
        userComments.append(contentsOf: result.comments)
        commentPage = nextPage
        hasMoreComments = result.hasMore
        isLoadingMoreComments = false
    }
}

struct UserCommentRow: View {
    let comment: UserComment
    @Binding var path: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = comment.storyTitle, let storyId = comment.storyId {
                Button {
                    path.append(ItemNavigation.textStory(id: storyId))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.up.left")
                            .font(.caption2)
                        Text(title)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            Text(comment.text)
                .font(.body)
                .lineLimit(4)
            Text(comment.timestamp.ageString())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        UserView(username: "zdw", path: .constant(NavigationPath()))
    }
}
