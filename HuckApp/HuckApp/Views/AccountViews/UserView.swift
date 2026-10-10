//
//  UserPageView.swift
//  HuckApp
//
//  Created by James Asbury on 12/30/25.
//

import SwiftUI

struct UserView: View {
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

    /// Whether the page adds its own overflow menu to the nav bar. The account
    /// tab turns this off: it already has an account menu there, and folds the
    /// profile options into it rather than showing two ellipses side by side.
    let showsOptionsMenu: Bool

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
        onSignIn: (() -> Void)? = nil,
        showsOptionsMenu: Bool = true
    ) {
        self.username = username
        self._path = path
        self.onSignIn = onSignIn
        self.showsOptionsMenu = showsOptionsMenu
        // The feeds are (re)built by `loadProfile()`, which also runs on any
        // later change of `username` — signing in or out, without this view
        // losing its identity. Seeding them here keeps a real profile's first
        // frame from flashing an empty list before that task runs.
        self._posts = State(initialValue: username.map { StoryFeed.userStories(username: $0) })
        self._comments = State(initialValue: username.map { PaginatedFeed<UserComment>.userComments(username: $0) })
        self._feedsUsername = State(initialValue: username)
        // Signed out, Posts isn't among the available tabs, so the pager would
        // otherwise open with nothing selected.
        self._currentTab = State(initialValue: username == nil ? .recentlyViewed : .posts)
    }

    /// Heights of the scroll viewport and the pinned tab bar. A short or empty
    /// tab is padded to fill the space below the bar, so the page can always
    /// scroll far enough to collapse the large title and pin the bar, and the
    /// white list runs to the bottom of the screen.
    @State private var viewportHeight: CGFloat = 0
    @State private var tabBarHeight: CGFloat = 0

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
                    content(for: currentTab)
                        .frame(minHeight: max(0, viewportHeight - tabBarHeight), alignment: .top)
                        .background(cardBackgroundColor)
                } header: {
                    pinnedTabBar
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .refreshable { await refresh(currentTab) }
        // Grey above, white below: the large title and an overscroll at the top
        // (behind the pull-to-refresh spinner) sit on the header's grey
        // backdrop, while a bounce at the bottom continues the white list.
        .background {
            VStack(spacing: 0) {
                Color(.secondarySystemBackground)
                cardBackgroundColor
            }
            .ignoresSafeArea()
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: currentTab) { _, newTab in
            // Refresh the snapshot each time the tab is opened so it picks up any
            // stories viewed since it was last shown.
            if newTab == .recentlyViewed {
                Task { await refreshRecentlyViewed() }
            }
        }
        .toolbar {
            // Signed out there's no profile to act on.
            if showsOptionsMenu, let username {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ProfileOptions(username: username)
                            // Menu icons match their text rather than the app's
                            // orange tint. Set on the content, not the `Menu`,
                            // so the ellipsis button itself keeps the tint.
                            .tint(.primary)
                    } label: {
                        Label("Profile Options", systemImage: "ellipsis")
                    }
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
        async let fetchedUser = HackerNewsAPI.getUser(for: username)
        async let loadedPosts: Void = posts.loadMore()
        async let loadedComments: Void = comments.loadMore()
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
            await HackerNewsAPI.getUser(for: username)
        } else {
            nil
        }
        switch tab {
        case .posts: await posts?.refresh()
        case .comments: await comments?.refresh()
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
        await feed.reload()
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
        PillTabBar(tabs: availableTabs, selection: $currentTab)
            .background(cardBackgroundColor)
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
    let session = UserSession()
    NavigationStack {
        UserView(username: "zdw", path: .constant(NavigationPath()))
    }
    .environment(session)
    .environment(InteractionStore(session: session))
    .environment(RecentlyViewedStore(session: session))
}
