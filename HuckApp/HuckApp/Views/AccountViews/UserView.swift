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

    /// The view's background (white in light mode).
    private let cardBackgroundColor = Color(UIColor.systemBackground)

    // MARK: - Tabs available

    /// Whether this profile belongs to the logged-in user. Their likes are private,
    /// so the Likes action only shows on their own profile.
    private var isCurrentUser: Bool {
        username == UserSession.shared?.username
    }

    /// The tabs to show, in order.
    private var availableTabs: [UserTab] {
        [.posts, .comments]
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
        .background(cardBackgroundColor)
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
                profileActionButtons
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(1 - collapseProgress)
            .background(cardBackgroundColor)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsibleHeight = $0 }

            // Pinned region: the "Activity" title anchors to the top with the
            // tab pills directly beneath it, both staying put as content scrolls.
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Activity")
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                tabBarButtons
                Divider()
            }
            // White behind the tab bar, matching the content below it.
            .background(cardBackgroundColor)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
        }
        .offset(y: -collapse)
    }

    /// Height of the soft fade at the bottom of a clipped bio.
    private let bioFadeHeight: CGFloat = 32

    /// Mask for the bio: opaque for a bio that fits, but fading to clear over the
    /// last `bioFadeHeight` points when it's clipped, softening the cut-off.
    @ViewBuilder
    private var bioFadeMask: some View {
        if bioFullHeight > bioMaxHeight {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: max(0, (bioMaxHeight - bioFadeHeight) / bioMaxHeight)),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color.black
        }
    }

    /// A lightweight section title used above the bio and the activity tabs.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Maximum height of the bio before it clips. A future "Expand" control will
    /// lift this cap.
    private let bioMaxHeight: CGFloat = 140
    /// The bio's full (unclipped) height, measured to decide whether to clip and
    /// show "Expand".
    @State private var bioFullHeight: CGFloat = 0

    var userSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Karma: \(user?.karma ?? 0)")
                    .foregroundStyle(.secondary)
                Spacer()
                // Shown only when the bio is clipped; expands it (no-op for now).
                if bioFullHeight > bioMaxHeight {
                    Button {
                        // TODO: Expand the bio
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let about = user?.about, !about.isEmpty {
                // The "About" header and the bio grouped together in a card.
                VStack(alignment: .leading, spacing: 8) {
                    //sectionHeader("About")
                    // Cap the height so a long bio can't push the tab bar off screen;
                    // overflow is hard-clipped.
                    Text(about)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        // A hidden copy at the same width reports the full height
                        // (`fixedSize` keeps it from being clipped), so we can decide
                        // whether to show "Expand".
                        .background(alignment: .topLeading) {
                            Text(about)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .hidden()
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                    bioFullHeight = $0
                                }
                        }
                        // Clamp to the measured bio height (capped at `bioMaxHeight`)
                        // and hard-clip the overflow. Using an exact height rather
                        // than `maxHeight` keeps the frame from expanding to fill the
                        // header's offered space, which left dead space for short bios.
                        // Before measurement (`bioFullHeight == 0`) fall back to the
                        // natural height.
                        .frame(
                            height: bioFullHeight > 0 ? min(bioFullHeight, bioMaxHeight) : nil,
                            alignment: .top
                        )
                        // When the bio is clipped, fade the last stretch to hint at
                        // more content instead of a hard cut. Short bios that fit are
                        // fully opaque. The mask also clips overflow to the frame.
                        .mask(bioFadeMask)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Prominent actions below the bio. The current user sees Likes + Favorites
    /// side by side; other users see only Favorites (their likes are private),
    /// spanning the full width. Non-functional for now.
    var profileActionButtons: some View {
        HStack(spacing: 12) {
            if isCurrentUser {
                profileActionButton("Likes", systemImage: "arrow.up", iconColor: .orange) {
                    // TODO: Show this user's likes (upvoted posts and comments)
                }
            }
            profileActionButton("Favorites", systemImage: "heart", iconColor: .red) {
                // TODO: Show this user's favorites (posts and comments)
            }
        }
        .padding(.top, 8)
    }

    /// A neutral (system-background) card button: a colored leading icon, the
    /// left-aligned title, and a trailing chevron.
    private func profileActionButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    /// Mail-style category tabs: each tab is a symbol in a colored capsule that
    /// expands to reveal its title when selected. Both tapping a pill and
    /// swiping the pager below drive `currentTab`, and the shared animation
    /// keeps the expand/collapse smooth either way.
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

    /// A single tab pill. Unselected it shows only its symbol on a neutral fill;
    /// selected it fills with the tab's color and expands to include the title.
    private func tabPill(for tab: UserTab) -> some View {
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

    // MARK: - Tab Content

    /// The scrollable content for a tab.
    @ViewBuilder
    func content(for tab: UserTab) -> some View {
        switch tab {
        case .posts: postsList
        case .comments: commentsList
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
