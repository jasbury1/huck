//
//  UserPageView.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import SwiftUI

struct UserView: View {
    let username: String
    @State private var user: User?
    @Binding var path: NavigationPath

    @State private var currentTab: ContentTab = .posts

    /// This user's activity, one paginated feed per tab. Each grows as its list
    /// is scrolled; see `PaginatedFeed`.
    @State private var posts: PaginatedFeed<StoryModel>
    @State private var comments: PaginatedFeed<UserComment>

    init(username: String, path: Binding<NavigationPath>) {
        self.username = username
        self._path = path
        self._posts = State(initialValue: .userStories(username: username))
        self._comments = State(initialValue: .userComments(username: username))
    }

    // Collapsing-header state. `collapse` is the single source of truth for how
    // far the header is translated up; only the visible tab drives it. Because it
    // persists across tab switches, the header (and its pinned tab bar) never
    // jumps — the incoming tab is instead scrolled to meet it. The measured
    // heights define how far the header travels and each scroll's top spacer.
    @State private var collapse: CGFloat = 0
    @State private var scrollOffsets: [ContentTab: CGFloat] = [:]
    @State private var scrollPositions: [ContentTab: ScrollPosition] = [:]
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

    /// The tabs to show, in order. "Recently viewed" is private to the logged-in
    /// user, so it only appears on their own profile.
    private var availableTabs: [ContentTab] {
        var tabs: [ContentTab] = [.posts, .comments]
        if isCurrentUser {
            tabs.append(.recentlyViewed)
        }
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
            // Eagerly warm the profile and both default tabs' first pages in
            // parallel, so switching between Posts and Comments feels instant.
            async let fetchedUser = HackerNewsAPI.getUser(for: username)
            async let loadedPosts: Void = posts.loadMore()
            async let loadedComments: Void = comments.loadMore()
            user = await fetchedUser
            _ = await (loadedPosts, loadedComments)
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
            // A subtle grey backdrop behind the profile info that sets the white
            // bio/action cards apart — running to the top and stopping before the
            // pinned Activity section below.
            .background(Color(.secondarySystemBackground))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsibleHeight = $0 }

            // Pinned region: the "Activity" title anchors to the top with the
            // tab pills directly beneath it, both staying put as content scrolls.
            VStack(alignment: .leading, spacing: 0) {
                SortableHeader(title: "Activity")
                tabBarButtons
                Divider()
            }
            // White behind the tab bar, matching the content below it.
            .background(cardBackgroundColor)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
        }
        .offset(y: -collapse)
    }

    /// Length of the fade ramp (opaque → clear) at the bottom of a clipped bio.
    private let bioFadeHeight: CGFloat = 32
    /// How far above the bottom edge the fade reaches fully clear.
    private let bioFadeEndInset: CGFloat = 24

    /// Mask for the bio: opaque for a bio that fits, but ramping to clear near the
    /// bottom when it's clipped, softening the cut-off. The clear point sits
    /// `bioFadeEndInset` above the bottom so the text is gone slightly higher up.
    @ViewBuilder
    private var bioFadeMask: some View {
        if bioFullHeight > bioMaxHeight {
            let clearLocation = max(0, (bioMaxHeight - bioFadeEndInset) / bioMaxHeight)
            let blackLocation = max(0, (bioMaxHeight - bioFadeEndInset - bioFadeHeight) / bioMaxHeight)
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: blackLocation),
                    .init(color: .clear, location: clearLocation),
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
    /// show "Read more".
    @State private var bioFullHeight: CGFloat = 0
    /// Whether the full-bio sheet is presented.
    @State private var showingFullBio = false

    var userSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Karma: \(user?.karma ?? 0)")
                .foregroundStyle(.secondary)
                // Tuck the karma closer to the username above it.
                .padding(.top, -6)
                .padding(.bottom, 10)
            if let about = user?.about, !about.isEmpty {
                // The "About" header and the bio grouped together in a card.
                VStack(alignment: .leading, spacing: 8) {
                    //sectionHeader("About")
                    // Cap the height so a long bio can't push the tab bar off screen.
                    // NOTE: no `.fixedSize` here — with it, the Text ignores the
                    // height cap below and lays out at full height, overflowing the
                    // frame. That overflow stays hit-testable (clip/mask only affect
                    // rendering), so a long bio would overhang and steal the tab
                    // list's scroll gestures. Without it, the Text respects the cap.
                    Text(about)
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
                        // Hard-clip the overflow to the frame. `mask` only affects
                        // alpha — without this, a long bio's invisible overflow still
                        // extends past the frame and steals scroll gestures from the
                        // tab section below. `clipped()` bounds both drawing AND hit
                        // testing to the frame.
                        .clipped()
                        // When the bio is clipped, fade the last stretch to hint at
                        // more content instead of a hard cut. Short bios that fit are
                        // fully opaque.
                        .mask(bioFadeMask)
                        // A "Read more" affordance sits over the fade, blending in
                        // from the trailing edge, and opens the full bio in a sheet.
                        .overlay(alignment: .bottomTrailing) {
                            if bioFullHeight > bioMaxHeight {
                                Button {
                                    showingFullBio = true
                                } label: {
                                    Text("Read more")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.leading, 32)
                                        .background(
                                            LinearGradient(
                                                colors: [.clear, cardBackgroundColor, cardBackgroundColor],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingFullBio) {
            BioSheet(username: username, about: user?.about ?? "")
        }
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
                path.append(ItemNavigation.favorites(user: username))
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
    private func syncCollapse(to newTab: ContentTab) {
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
    func tabScroll<Content: View>(for tab: ContentTab, @ViewBuilder content: () -> Content) -> some View {
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
    private func scrollPositionBinding(for tab: ContentTab) -> Binding<ScrollPosition> {
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

    // MARK: - Tab Content

    /// The scrollable content for a tab.
    @ViewBuilder
    func content(for tab: ContentTab) -> some View {
        switch tab {
        case .posts: postsList
        case .comments: commentsList
        case .recentlyViewed: recentlyViewedList
        }
    }

    /// Placeholder for the recently-viewed stories. Tracking and content will be
    /// wired up in a later change.
    var recentlyViewedList: some View {
        ContentUnavailableView(
            "No Recently Viewed",
            systemImage: "clock",
            description: Text("Stories you open will show up here.")
        )
        .padding(.top, 40)
    }

    var postsList: some View {
        PaginatedList(feed: posts) { model in
            StoryCellView(model: model, path: $path)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }

    var commentsList: some View {
        PaginatedList(feed: comments) { comment in
            UserCommentRow(comment: comment, path: $path)
        }
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

/// A sheet that shows a user's full bio, scrollable, for bios too long to fit
/// in the profile card.
struct BioSheet: View {
    let username: String
    let about: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(about)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    NavigationStack {
        UserView(username: "zdw", path: .constant(NavigationPath()))
    }
    .environment(InteractionStore())
}
