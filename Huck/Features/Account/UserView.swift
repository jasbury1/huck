//
//  UserView.swift
//  Huck
//
//  Created by James Asbury on 12/30/25.
//

import SwiftUI

struct UserView: View {
    @Environment(\.hackerNews) private var api
    /// The profile being shown, or `nil` for the signed-out account tab. There's
    /// no Hacker News user to fetch in that case, so the page keeps its chrome
    /// but drops to what works without an account: the locally-recorded reading
    /// history, and a way to sign in.
    let username: String?
    @State private var user: User?
    @Binding var path: NavigationPath

    @State private var currentTab: ContentTab

    /// This user's activity, one feed per tab. Each grows as its list is
    /// scrolled; the posts feed also warms story details ahead of the scroll.
    /// Both are `nil` while signed out, where neither tab is offered.
    @State private var posts: StoryFeed?
    @State private var comments: PaginatedFeed<UserComment>?

    /// Whose activity `posts` and `comments` page. Compared against `username`
    /// so that signing in or out rebuilds them rather than leaving the previous
    /// account's pages on screen.
    @State private var feedsUsername: String?

    /// What the signed-out "Sign In" card does. The account tab owns the login
    /// sheet — it offers the same action from its toolbar menu — so this view
    /// only reports the tap. Profiles reached from a story always have a
    /// username and never show the card, so they can leave it unset.
    let onSignIn: (() -> Void)?

    /// Per-user record of recently-viewed stories, shown in the (current-user-only)
    /// "Recently viewed" tab.
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(UserSession.self) private var session
    /// A snapshot feed built from the store's current order (most-recent first).
    /// Rebuilt whenever the tab is shown so newly-opened stories appear.
    @State private var recentlyViewed: StoryFeed?

    init(
        username: String?,
        path: Binding<NavigationPath>,
        onSignIn: (() -> Void)? = nil
    ) {
        self.username = username
        _path = path
        self.onSignIn = onSignIn
        // The feeds are (re)built by `loadProfile()`, which also runs on any
        // later change of `username` — signing in or out, without this view
        // losing its identity. Seeding them here keeps a real profile's first
        // frame from flashing an empty list before that task runs.
        _posts = State(initialValue: username.map { StoryFeed.userStories(username: $0) })
        _comments = State(initialValue: username.map { PaginatedFeed<UserComment>.userComments(username: $0) })
        _feedsUsername = State(initialValue: username)
        // Signed out, Posts isn't among the available tabs, so the pager would
        // otherwise open with nothing selected.
        _currentTab = State(initialValue: username == nil ? .recentlyViewed : .posts)
    }

    /// Sizes of the scroll viewport and the pinned tab bar. A short or empty
    /// tab is padded to fill the space below the bar, so the page can always
    /// scroll far enough to collapse the large title and pin the bar, and the
    /// white list runs to the bottom of the screen.
    @State private var viewportSize: CGSize = .zero
    @State private var tabBarHeight: CGFloat = 0

    // MARK: Scroll state

    //
    // The tabs share one scroll view (it's what lets the nav bar track it).
    // Pinning is measured inside the scroll content, where nothing moves but
    // the pinned tab bar: it rests directly below the header, at the header's
    // height, and once pinned it's pushed down past that spot to stay under
    // the nav bar. How far it's been pushed is how far the current list has
    // scrolled beneath it. Measured this way it doesn't depend on the scroll
    // view's content insets, which the system changes as the bars change.
    //
    // `body` reads only `isTabBarPinned`, which changes once per pin or
    // unpin — never the measurements, which change every frame while pinned.
    // Reading them in `body` would re-render the page on every frame of a
    // scroll, from inside the scroll view's own layout pass.

    @State private var scrollPosition = ScrollPosition()
    /// The profile header's height, which is where the tab bar rests.
    @State private var headerHeight: CGFloat = 0
    /// The tab bar's top in the scroll content's coordinate space.
    @State private var tabBarMinY: CGFloat = 0
    /// Whether the tab bar is pinned beneath the navigation bar.
    @State private var isTabBarPinned = false
    /// The height of the scroll view's visible region (inside its insets).
    @State private var visibleHeight: CGFloat = 0
    /// Where the current list's laid-out rows sit, in the content space.
    @State private var rowFrames = ListRowFrames(space: .named(UserView.contentSpace))
    /// Each tab's list scroll, saved as the tab is left while the bar is pinned.
    @State private var savedScrolls: [ContentTab: SavedScroll] = [:]
    /// An offset to scroll to once a tab switch has swapped the list in.
    @State private var pendingScrollY: CGFloat?

    /// Where a tab's list was left, while the tab bar was pinned.
    ///
    /// Each switch rebuilds the incoming list, which estimates the heights of
    /// rows it hasn't laid out yet — so the same offset lands on different
    /// rows than it was taken at. The restore goes by row instead: the first
    /// row at or below the top of the visible region, and how far below it
    /// started. Its identity survives the rebuild. The offset is the fallback
    /// for when there's no such row to go by.
    private struct SavedScroll {
        /// How far the list had scrolled under the pinned tab bar.
        var listOffset: CGFloat
        /// The row to restore to: its identity, how far its top sat below the
        /// visible region's top, and its height.
        var row: (id: any Hashable & Sendable, top: CGFloat, height: CGFloat)?
    }

    /// The scroll content's coordinate space, which scrolls with it.
    private nonisolated static let contentSpace = "UserView.content"

    /// How far the current list has scrolled under the pinned tab bar, or
    /// `nil` while the bar rests below the header. Exactly at the pin point
    /// the two can't be told apart, so `switchTab(to:)` lands just past it.
    private var pinnedListOffset: CGFloat? {
        PinnedTabBarGeometry.pinnedListOffset(tabBarMinY: tabBarMinY, headerHeight: headerHeight)
    }

    /// Brings `isTabBarPinned` up to date, assigning it only when it changes
    /// so the page re-renders just once per pin or unpin.
    private func updateTabBarPinned() {
        let pinned = pinnedListOffset != nil
        if pinned != isTabBarPinned {
            isTabBarPinned = pinned
        }
    }

    /// The view's background (white in light mode).
    private let cardBackgroundColor = Color(UIColor.systemBackground)

    // MARK: - Tabs available

    /// Whether this profile belongs to the logged-in user. Their likes are private,
    /// so the Likes action only shows on their own profile.
    private var isCurrentUser: Bool {
        username != nil && username == session.username
    }

    /// What the header and nav bar title call this page. Signed out there's no
    /// username to show, so the tab names itself. A `String` rather than a
    /// `LocalizedStringKey` so a real username is rendered verbatim instead of
    /// being looked up as a translation key.
    private var displayName: String {
        username ?? String(localized: "Account")
    }

    /// The tabs to show, in order. Posts and Comments need a Hacker News account
    /// to read from, so signed out only the locally-recorded history remains.
    /// "Recently viewed" is private, so on a real profile it's the logged-in
    /// user's own only.
    private var availableTabs: [ContentTab] {
        guard username != nil else { return [.recentlyViewed] }
        var tabs: [ContentTab] = [.posts, .comments]
        if isCurrentUser {
            tabs.append(.recentlyViewed)
        }
        return tabs
    }

    /// One vertical scroll for the whole page — the profile summary, then the
    /// selected tab's list under a pinned tab bar. Being the page's only
    /// scroll view, it's the one the navigation bar tracks, so the username is
    /// a standard large title that collapses into the bar like any other page.
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                profileHeader
                Section {
                    tabContent
                } header: {
                    pinnedTabBar
                }
            }
            .coordinateSpace(.named(Self.contentSpace))
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
            visibleHeight = height
        }
        .refreshable { await refresh(currentTab) }
        // In a split view's leading column the bar draws no background of its
        // own, so once the tab bar pins, the header would go on scrolling
        // visibly behind the title and buttons. Instead, while pinned, a white
        // panel covers the page from the top of the scroll view up behind the
        // bar, joining the white tab bar below it.
        // The panel is always there, and only its opacity follows the pin, so
        // its frame never changes. Anything around the scroll view whose frame
        // reaches into the safe area resizes the scroll view's host container,
        // and with it the scroll view's insets — which move the pinned tab
        // bar. A mask that reached up under the bar only while unpinned did
        // exactly that: pinning moved the bar, which unpinned it, which moved
        // it back, forever (an observation-tracking feedback loop).
        .overlay(alignment: .top) {
            cardBackgroundColor
                .frame(height: 0)
                .ignoresSafeArea(edges: .top)
                .opacity(isTabBarPinned ? 1 : 0)
                .allowsHitTesting(false)
        }
        // Grey above, white below: the large title and an overscroll at the top
        // (behind the pull-to-refresh spinner) sit on the header's grey
        // backdrop, while a bounce at the bottom continues the white list.
        // White above too while the tab bar is pinned, matching the panel
        // above.
        .background {
            VStack(spacing: 0) {
                isTabBarPinned ? cardBackgroundColor : Color(.secondarySystemBackground)
                cardBackgroundColor
            }
            .ignoresSafeArea()
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.large)
        // Once the white tab bar pins, the nav bar turns solid white to join
        // it, reading as one bar rather than an opaque strip beneath a
        // translucent one. The edge effect goes with it, as there's no longer
        // content showing through to blur, and its blur would otherwise reach
        // down over the pills. Until then the bar is the system default, over
        // the header's grey.
        .toolbarBackground(cardBackgroundColor, for: .navigationBar)
        .toolbarBackground(isTabBarPinned ? .visible : .automatic, for: .navigationBar)
        .scrollEdgeEffectHidden(isTabBarPinned, for: .top)
        .onChange(of: currentTab) { _, newTab in
            // Refresh the snapshot each time the tab is opened so it picks up any
            // stories viewed since it was last shown.
            if newTab == .recentlyViewed {
                Task { await refreshRecentlyViewed() }
            }
            // An offset scroll made in the same update as the list swap lands
            // against the outgoing list; made here, after it, it lands right.
            if let y = pendingScrollY {
                pendingScrollY = nil
                withTransaction(\.animation, nil) {
                    scrollPosition.scrollTo(y: y)
                }
            }
        }
        // Keyed on `username` so signing in or out reloads in place rather than
        // through a fresh view — which would tear down the login sheet mid-flight.
        .task(id: username) { await loadProfile() }
        .sheet(isPresented: $showingFullBio) {
            BioSheet(username: username ?? "", about: user?.about ?? "")
        }
    }

    /// Loads everything this page shows for the current `username`, and rebuilds
    /// the per-user feeds when it changes. Signed out there's no profile to
    /// fetch and no activity to page, so only the local history is refreshed.
    private func loadProfile() async {
        // A tab from the previous account may no longer be offered.
        if !availableTabs.contains(currentTab), let first = availableTabs.first {
            currentTab = first
        }

        guard let username else {
            user = nil
            posts = nil
            comments = nil
            feedsUsername = nil
            await refreshRecentlyViewed()
            return
        }

        // Already built for this user by `init` (or a previous run); only a
        // change of account warrants discarding the pages fetched so far.
        if feedsUsername != username {
            posts = StoryFeed.userStories(username: username)
            comments = PaginatedFeed<UserComment>.userComments(username: username)
            feedsUsername = username
        }
        guard let posts, let comments else { return }

        // Eagerly warm the profile and both default tabs' first pages in
        // parallel, so switching between Posts and Comments feels instant.
        async let fetchedUser = api.getUser(for: username)
        async let loadedPosts: Void = posts.loadMore(using: api)
        async let loadedComments: Void = comments.loadMore(using: api)
        user = await fetchedUser
        _ = await (loadedPosts, loadedComments)
        // Warm the recently-viewed snapshot too (current user only).
        if isCurrentUser { await refreshRecentlyViewed() }
    }

    /// Pull-to-refresh: re-fetches the profile (karma and bio) alongside the
    /// tab being pulled. The other tabs keep their pages — they weren't asked
    /// for, and re-fetching them would spend requests on lists not on screen.
    private func refresh(_ tab: ContentTab) async {
        async let fetchedUser: User? = if let username {
            await api.getUser(for: username)
        } else {
            nil
        }
        switch tab {
        case .posts: await posts?.refresh(using: api)
        case .comments: await comments?.refresh(using: api)
        case .recentlyViewed: await refreshRecentlyViewed()
        }
        // A failed fetch keeps the profile already on screen.
        if let fetched = await fetchedUser { user = fetched }
    }

    /// Refreshes the recently-viewed feed so it reflects stories opened since the
    /// profile last appeared. Also folds in any signed-out browsing, covering the
    /// case where login happened via this tab.
    ///
    /// The feed is created once and only ever `reload()`ed — reusing the instance
    /// keeps its `StoryModel` cache, so already-loaded rows stay populated instead
    /// of blanking to placeholders (a fresh feed would hand each id a new empty
    /// model whose fetch `.task` won't re-run under the unchanged row identity).
    private func refreshRecentlyViewed() async {
        recentlyViewedStore.adoptGuestHistory()
        let feed = recentlyViewed ?? StoryFeed.recentlyViewed(recentlyViewedStore)
        recentlyViewed = feed
        await feed.reload(using: api)
    }

    // MARK: - Header

    /// The top of the page, under the large title: karma, bio, and actions.
    /// It scrolls away beneath the navigation bar, leaving the pinned tab bar.
    var profileHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            userSummary
            profileActionButtons
        }
        // Standard margins, so the summary lines up with the large title.
        .padding(.horizontal)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A subtle grey backdrop behind the profile info that sets the white
        // bio/action cards apart — stopping before the pinned tab bar below.
        .background(Color(.secondarySystemBackground))
        // The tab bar pins once the page has scrolled this far.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            headerHeight = $0
            updateTabBarPinned()
        }
    }

    /// The tab pills, pinned beneath the navigation bar once the profile
    /// header has scrolled away.
    var pinnedTabBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBarButtons
                .padding(.top, 8)
            Divider()
        }
        // White behind the tab bar, matching the content below it.
        .background(cardBackgroundColor)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .named(Self.contentSpace)).minY
        } action: {
            tabBarMinY = $0
            updateTabBarPinned()
        }
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
                    .init(color: .clear, location: 1),
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
            // Signed out there's no karma to report, so the subtitle explains
            // what signing in adds instead. Written as a branch rather than a
            // ternary inside `Text` so both stay `LocalizedStringKey`s.
            Group {
                if username == nil {
                    Text("Sign in to see your posts, comments, and favorites.")
                } else {
                    Text("Karma: \(user?.karma ?? 0)")
                }
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 10)
            if let about = user?.about, !about.isEmpty {
                // The "About" header and the bio grouped together in a card.
                VStack(alignment: .leading, spacing: 8) {
                    // sectionHeader("About")
                    // Cap the height so a long bio can't push the tab bar off screen.
                    // NOTE: no `.fixedSize` here — with it, the Text ignores the
                    // height cap below and lays out at full height, overflowing the
                    // frame. That overflow stays hit-testable (clip/mask only affect
                    // rendering), so a long bio would overhang and steal the tab
                    // list's scroll gestures. Without it, the Text respects the cap.
                    FormattedTextView(text: about)
                        // Links take the tint, which is primary outside content.
                        .tint(.orange)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        // A hidden copy at the same width reports the full height
                        // (`fixedSize` keeps it from being clipped), so we can decide
                        // whether to show "Expand".
                        .background(alignment: .topLeading) {
                            FormattedTextView(text: about)
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
    }

    /// Prominent actions below the bio. The current user sees Likes + Favorites
    /// side by side; other users see only Favorites (their likes are private),
    /// spanning the full width. Both need an account to resolve against, so
    /// signed out they give way to the action that gets you one.
    var profileActionButtons: some View {
        HStack(spacing: 12) {
            if let username {
                if isCurrentUser {
                    profileActionButton("Likes", systemImage: "arrow.up", iconColor: .orange) {
                        path.append(ItemNavigation.liked)
                    }
                }
                profileActionButton("Favorites", systemImage: "heart", iconColor: .red) {
                    path.append(ItemNavigation.favorites(user: username))
                }
            } else if let onSignIn {
                profileActionButton("Sign In", systemImage: "person.crop.circle", iconColor: .orange, action: onSignIn)
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

    /// Mail-style category tabs: each tab is a symbol in a colored capsule that
    /// expands to reveal its title when selected. Tapping a pill switches the
    /// list below it.
    var tabBarButtons: some View {
        PillTabBar(tabs: availableTabs, selection: pillSelection)
            .background(cardBackgroundColor)
    }

    /// Routes a pill tap through `switchTab(to:)`, so the incoming tab gets its
    /// own scroll position back.
    private var pillSelection: Binding<ContentTab> {
        Binding(
            get: { currentTab },
            set: { switchTab(to: $0) }
        )
    }

    /// The selected tab's list, padded to fill the space below the tab bar.
    private var tabContent: some View {
        content(for: currentTab)
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(0, viewportSize.height - tabBarHeight), alignment: .top)
            .background(cardBackgroundColor)
            // The list's rows report where they sit, for `switchTab(to:)`.
            .environment(\.listRowFrames, rowFrames)
    }

    /// Switches to `tab`. The header is shared by every tab, so a switch never
    /// moves it:
    /// - with the bar pinned, the incoming tab stays pinned, its list back
    ///   where it was left (or at its start, if never scrolled);
    /// - with the header showing, nothing scrolls, and the incoming tab shows
    ///   from the top of its list. Its saved spot is kept for the next switch
    ///   made while pinned.
    private func switchTab(to tab: ContentTab) {
        guard tab != currentTab else { return }
        let outgoingOffset = pinnedListOffset
        savedScrolls[currentTab] = outgoingOffset.map(saveScroll(listOffset:))
        let incoming = savedScrolls[tab]

        // The swap and the jump happen together, with no animation. The pill
        // tap arrives inside `withAnimation`; left in it, the incoming list's
        // height would animate in, and the jump — made against a page still
        // too short — would land short of the saved spot. The pills animate
        // regardless, through their own `.animation(_:value:)`.
        withTransaction(\.animation, nil) {
            currentTab = tab
            if outgoingOffset != nil {
                restoreScroll(incoming)
            }
        }
    }

    /// Records where the current list was left, `listOffset` under the
    /// pinned tab bar.
    private func saveScroll(listOffset: CGFloat) -> SavedScroll {
        // The pinned bar's top is the top of the visible region.
        let row = rowFrames.firstRow(startingAtOrBelow: tabBarMinY)
        return SavedScroll(
            listOffset: listOffset,
            row: row.map { ($0.id, $0.frame.minY - tabBarMinY, $0.frame.height) }
        )
    }

    /// Scrolls the incoming list back to where it was left, keeping the tab
    /// bar pinned.
    private func restoreScroll(_ saved: SavedScroll?) {
        // By row where there is one that fits on screen; by offset otherwise,
        // including for a tab never left while pinned.
        if let row = saved?.row,
           let anchor = PinnedTabBarGeometry.restoreAnchor(
               rowTop: row.top, rowHeight: row.height, visibleHeight: visibleHeight
           ) {
            scrollPosition.scrollTo(id: row.id, anchor: anchor)
        } else {
            pendingScrollY = PinnedTabBarGeometry.fallbackScrollY(
                headerHeight: headerHeight, listOffset: saved?.listOffset
            )
        }
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

    /// The current user's recently-viewed stories, most-recently-viewed first,
    /// rendered from the snapshot built by `refreshRecentlyViewed()`.
    @ViewBuilder
    var recentlyViewedList: some View {
        let empty = EmptyFeedView(
            title: "No Recently Viewed",
            systemImage: "clock",
            description: "Stories you open will show up here."
        )
        if let recentlyViewed {
            StoryList(feed: recentlyViewed, path: $path, emptyState: empty)
        } else {
            empty
        }
    }

    @ViewBuilder
    var postsList: some View {
        if let posts, let username {
            StoryList(
                feed: posts,
                path: $path,
                emptyState: EmptyFeedView(
                    title: "No Posts",
                    systemImage: "newspaper",
                    description: "Stories \(username) submits will show up here."
                )
            )
        }
    }

    @ViewBuilder
    var commentsList: some View {
        if let comments, let username {
            PaginatedList(
                feed: comments,
                emptyState: EmptyFeedView(
                    title: "No Comments",
                    systemImage: "bubble.left.and.bubble.right",
                    description: "Comments \(username) posts will show up here."
                )
            ) { comment in
                UserCommentRow(comment: comment, path: $path) {
                    comments.removeAll { $0.id == comment.id }
                }
            }
        }
    }
}

/// The actions offered for a profile, as menu rows. Shared by the profile's own
/// overflow menu and the account tab's menu, which shows your own profile.
struct ProfileOptions: View {
    let username: String

    var body: some View {
        let url = User.hackerNewsURL(for: username)
        Button {
            UIPasteboard.general.url = url
        } label: {
            Label("Copy Profile Link", systemImage: "link")
        }
        ShareLink(item: url) {
            Label("Share Profile", systemImage: "square.and.arrow.up")
        }
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
                FormattedTextView(text: about)
                    .tint(.orange)
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
    let session = UserSession()
    NavigationStack {
        UserView(username: "zdw", path: .constant(NavigationPath()))
    }
    .environment(session)
    .environment(InteractionStore(session: session))
    .environment(RecentlyViewedStore(session: session))
}
