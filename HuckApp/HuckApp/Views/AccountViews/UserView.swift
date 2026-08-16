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

    /// Owns upvote state and vends the current user's liked (upvoted) list — the
    /// source for the Liked tab, which also keeps upvote arrows in sync.
    @Environment(InteractionStore.self) private var interactionStore

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

    @State private var likedStoryIds: [Int] = []
    @State private var likedPage = 0
    @State private var hasMoreLiked = false
    @State private var isLoadingMoreLiked = false

    // Collapsing-header state. `collapse` is the single source of truth for how
    // far the header is translated up; only the visible tab drives it. Because it
    // persists across tab switches, the header (and its pinned tab bar) never
    // jumps — the incoming tab is instead scrolled to meet it. The measured
    // heights define how far the header travels and each scroll's top spacer.
    @State private var collapse: CGFloat = 0
    @State private var scrollOffsets: [UserTab: CGFloat] = [:]
    @State private var scrollPositions: [UserTab: ScrollPosition] = [:]
    @State private var collapsibleHeight: CGFloat = 0
    @State private var tabBarHeight: CGFloat = 0
    /// True while an incoming tab is being scrolled to meet the header. Its
    /// interim offsets are ignored so they can't drag `collapse` back to the top.
    @State private var isSyncing = false

    @Namespace private var namespace
    private let systemBackgroundColor = Color(UIColor.systemBackground)

    // MARK: - Tabs available

    /// Whether this profile belongs to the logged-in user. The "Liked" list is
    /// private to its owner, so its tab only appears here.
    private var isCurrentUser: Bool {
        username == UserSession.shared?.username
    }

    /// The tabs to show, in order. "Liked" is appended only for the current user.
    private var availableTabs: [UserTab] {
        var tabs: [UserTab] = [.posts, .comments, .favorites]
        if isCurrentUser { tabs.append(.liked) }
        return tabs
    }

    // MARK: - Collapse math

    /// 0 when the header is fully expanded, 1 when fully collapsed.
    private var collapseProgress: CGFloat {
        collapsibleHeight > 0 ? collapse / collapsibleHeight : 0
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

            // The Liked (upvoted) list is private to its owner, so only load it
            // for the current user's own profile.
            if isCurrentUser {
                let likedResult = await interactionStore.likedStories(page: 0)
                registerStoryModels(for: likedResult.ids)
                likedStoryIds = likedResult.ids
                hasMoreLiked = likedResult.hasMore
            }
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
        .offset(y: -collapse)
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
            ForEach(availableTabs, id: \.self) { tab in
                tabScroll(for: tab) { content(for: tab) }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: currentTab) { _, newTab in
            syncCollapse(to: newTab)
        }
    }

    /// Keeps the header (and its pinned tab bar) still when switching tabs. The
    /// header never moves on a switch; instead the incoming tab is scrolled —
    /// up or down, without animation — to meet the current `collapse`. The one
    /// exception is when the header is already fully collapsed and the incoming
    /// tab is also scrolled past full collapse: the header looks identical either
    /// way, so we leave that tab's deeper scroll position untouched. Every tab's
    /// `headerHeight` top spacer guarantees the room needed to reach `collapse`.
    private func syncCollapse(to newTab: UserTab) {
        let incoming = scrollOffsets[newTab] ?? 0
        if collapse >= collapsibleHeight && incoming >= collapsibleHeight {
            isSyncing = false
            return
        }
        guard abs(incoming - collapse) > 0.5 else {
            isSyncing = false
            return
        }
        isSyncing = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            var position = scrollPositions[newTab] ?? ScrollPosition()
            position.scrollTo(y: collapse)
            scrollPositions[newTab] = position
        }
    }

    /// Wraps a tab's content in a scroll view that clears space for the header
    /// and, while it's the visible tab, drives the header's collapse.
    @ViewBuilder
    func tabScroll<Content: View>(for tab: UserTab, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight)
                content()
            }
        }
        .scrollPosition(scrollPositionBinding(for: tab))
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffsets[tab] = offset
            guard tab == currentTab else { return }
            if isSyncing {
                // Ignore the interim offsets from a programmatic sync; only
                // release once the incoming tab has reached the header.
                if abs(offset - collapse) < 0.5 { isSyncing = false }
                return
            }
            collapse = min(max(offset, 0), collapsibleHeight)
        }
        .tag(tab)
    }

    /// A binding into a tab's scroll position, used to drive it programmatically
    /// when bringing it to meet the header on a tab switch.
    private func scrollPositionBinding(for tab: UserTab) -> Binding<ScrollPosition> {
        Binding(
            get: { scrollPositions[tab] ?? ScrollPosition() },
            set: { scrollPositions[tab] = $0 }
        )
    }

    var tabBarButtons: some View {
        HStack(spacing: 20) {
            ForEach(availableTabs, id: \.self) { tab in
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

    /// The scrollable content for a tab.
    @ViewBuilder
    func content(for tab: UserTab) -> some View {
        switch tab {
        case .posts: postsList
        case .comments: commentsList
        case .favorites: favoritesContent
        case .liked: likedList
        }
    }

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

    /// The current user's liked (upvoted) stories. Mirrors `postsList`, sharing the
    /// same retained `storyModels` so a story that also appears under Posts stays in
    /// sync.
    @ViewBuilder
    var likedList: some View {
        if likedStoryIds.isEmpty && !hasMoreLiked {
            Text("You haven't liked any stories yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(likedStoryIds, id: \.self) { storyId in
                    StoryCellView(model: model(for: storyId), path: $path)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    Divider()
                }
                if hasMoreLiked {
                    ProgressView()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            Task { await loadMoreLiked() }
                        }
                }
            }
        }
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

    private func loadMoreLiked() async {
        guard !isLoadingMoreLiked && hasMoreLiked else { return }
        isLoadingMoreLiked = true
        let nextPage = likedPage + 1
        let result = await interactionStore.likedStories(page: nextPage)
        registerStoryModels(for: result.ids)
        likedStoryIds.append(contentsOf: result.ids)
        likedPage = nextPage
        hasMoreLiked = result.hasMore
        isLoadingMoreLiked = false
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
        // The enclosing LazyVStack centers its rows, so a short comment would
        // otherwise appear indented. Fill the width and pin content leading.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        UserView(username: "zdw", path: .constant(NavigationPath()))
    }
    .environment(InteractionStore())
}
