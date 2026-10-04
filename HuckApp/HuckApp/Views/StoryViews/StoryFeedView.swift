//
//  StoryFeedView.swift
//  HuckApp
//
//  Created by James Asbury on 12/24/25.
//

import SwiftUI
import LinkPresentation
import UniformTypeIdentifiers

struct StoryFeedView: View {
    @State var feedKind: FeedKind
    @State private var feed: StoryFeed

    /// Whether the first page has been loaded. Guards the load `.task`, which
    /// SwiftUI also re-runs when the view reappears after navigating back — a
    /// reappear must leave the feed (and its scroll position) untouched. Filter
    /// changes are handled separately by `.onChange`, which doesn't fire on reappear.
    @State private var hasLoaded = false

    /// Backing text for the search field revealed by pulling the feed down.
    @State private var searchText = ""

    /// Upvote and favorite actions (each handles the login gate and the toggle).
    @Environment(\.upvote) private var upvote
    @Environment(\.favorite) private var favorite
    @Environment(\.composeNewPost) private var composeNewPost

    /// The filters turned on from the options menu, shared by every feed.
    @AppStorage(FeedSettings.filtersKey) private var filters = FeedFilters()

    /// Per-user recently-viewed record. "Mark Read" records a story here so its
    /// title greys in the feed, the same treatment an opened story gets.
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore

    /// Reconciles upvote/favorite state on pull-to-refresh.
    @Environment(InteractionSync.self) private var interactionSync

    /// Keeps the reader's hidden stories, which the feed's filters leave out.
    @Environment(InteractionStore.self) private var interactionStore
    /// Hiding is kept per account, so it's behind the same login sheet as
    /// upvoting.
    @Environment(\.requireLogin) private var requireLogin

    /// The story just hidden, offered back for a few seconds — hiding is a
    /// swipe away, and there's nowhere else to undo it.
    @State private var lastHidden: StoryModel?

    @Binding var path: NavigationPath

    init(feedKind: FeedKind, path: Binding<NavigationPath>) {
        self._feedKind = State(initialValue: feedKind)
        self._path = path
        self._feed = State(initialValue: .topStories(kind: feedKind))
    }

    var body: some View {
        List {
            ForEach(feed.visibleStories) { story in
                StoryCellView(model: story, path: $path)
                    // As each row appears, warm the details and thumbnails of the
                    // rows just below it so they are ready before they scroll in.
                    .onAppear {
                        Task { await feed.prefetchAhead(after: story.id) }
                    }
                    // Trailing swipe hides or marks the story read; a full swipe
                    // hides it. Hide is listed first so it's the full-swipe
                    // action.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            requireLogin { hide(story) }
                        } label: {
                            Label("Hide", systemImage: "eye.slash")
                        }
                        .tint(.gray)
                        Button {
                            // Toggle read state: recording greys the title (as an
                            // opened story does); removing it marks the story unread.
                            if recentlyViewedStore.hasViewed(story.id) {
                                recentlyViewedStore.removeView(story.id)
                            } else {
                                recentlyViewedStore.recordView(story.id)
                            }
                        } label: {
                            let isRead = recentlyViewedStore.hasViewed(story.id)
                            Label(
                                isRead ? "Mark Unread" : "Mark Read",
                                systemImage: isRead ? "circle" : "checkmark.circle"
                            )
                        }
                        .tint(.indigo)
                    }
                    // Leading swipe exposes Upvote and Favorite, matching the
                    // comment rows' leading Upvote. Upvote is listed first so a
                    // full swipe triggers it.
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            upvote(story)
                        } label: {
                            Label("Upvote", systemImage: "arrow.up")
                        }
                        .tint(.orange)
                        Button {
                            favorite(story)
                        } label: {
                            Label("Favorite", systemImage: "heart")
                        }
                        .tint(.red)
                    }
                    // Long-press shows the same options as the story's toolbar
                    // ellipsis, plus Hide — the swipe's action, for anyone who
                    // reaches for the menu instead. Hide is the feed's own, so
                    // it's added here rather than to the shared options.
                    .contextMenu {
                        Group {
                            StoryOptions(story: story)
                            Section {
                                Button("Hide", systemImage: "eye.slash") {
                                    requireLogin { hide(story) }
                                }
                            }
                        }
                        // Icons match their text, not the app's orange tint.
                        .tint(.primary)
                    }
            }
        }
        .listStyle(.plain)
        // The reader's filters have hidden everything loaded. Said plainly, with
        // the way back, rather than left as a blank screen.
        .overlay {
            if feed.isFilteredEmpty {
                VStack(spacing: 16) {
                    EmptyFeedView(
                        title: "All Caught Up",
                        systemImage: "checkmark.circle",
                        description: "Your filters are hiding every story here."
                    )
                    Button("Show All Stories") {
                        filters = FeedFilters()
                    }
                    .tint(.orange)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .overlay(alignment: .bottom) {
            if let lastHidden {
                HiddenStoryBanner {
                    undoHide(lastHidden)
                }
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                // Restarted by each hide, so the banner stays up for the
                // latest one.
                .task(id: lastHidden.id) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { self.lastHidden = nil }
                }
            }
        }
        // The one route by which hiding reaches the list — a swipe, an undo, or
        // switching accounts — so they can't disagree.
        .onChange(of: interactionStore.hiddenIDs) { _, hiddenIDs in
            withAnimation { feed.updateHiddenIDs(hiddenIDs) }
        }
        // A small pull-down reveals the search field (it stays hidden while
        // scrolled, per the drawer's automatic display mode); pulling further
        // triggers the refresh below.
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search \(feedKind.searchName)"
        )
        // Pull-to-refresh re-fetches the current feed kind's story ids, and takes the
        // opportunity to reconcile upvote/favorite state so the arrows and hearts
        // on the refreshed rows reflect anything done outside the app.
        .refreshable {
            async let reload: Void = refreshFeed()
            async let interactions: Void = interactionSync.refresh()
            _ = await (reload, interactions)
        }
        .task {
            // First-page load only. `.task` also re-runs when the view reappears
            // after navigating back, so the guard keeps that from reloading — the
            // feed and its scroll position survive the round trip.
            guard !hasLoaded else { return }
            hasLoaded = true
            applyFilters()
            await feed.loadMore()
        }
        .onChange(of: feedKind) {
            // A real kind change swaps in a fresh feed (a different id source)
            // and pages it in. Unlike `.task`, `.onChange` never fires on reappear.
            feed = .topStories(kind: feedKind)
            applyFilters()
            Task { await feed.loadMore() }
        }
        .onChange(of: filters) {
            withAnimation { applyFilters() }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Group {
                        Button("New Post", systemImage: "square.and.pencil") {
                            composeNewPost { path.append(ItemNavigation.textStory(id: $0)) }
                        }
                        Section {
                            ForEach(FeedFilter.toggleable) { filter in
                                Toggle(isOn: isOn(filter)) {
                                    Label(filter.title, systemImage: filter.systemImage)
                                }
                            }
                        }
                    }
                    // Icons match their text, not the app's orange tint.
                    .tint(.primary)
                } label: {
                    Label("Feed Options", systemImage: "ellipsis")
                }
            }
        }
        .navigationTitle(feedKind.displayName())
        // Says when filters are narrowing the feed, so missing stories are
        // never a mystery.
        .navigationSubtitle(filters.activeDescription.map { Text($0) } ?? Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            Group {
                Button("Top", systemImage: "arrow.up") {
                    feedKind = .topStories
                }
                Button("Best", systemImage: "trophy") {
                    feedKind = .bestStories
                }
                Button("New", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                    feedKind = .newStories
                }
                Divider()
                Button("Ask Hacker News", systemImage: "questionmark.bubble") {
                    feedKind = .askStories
                }
                Button("Show Hacker News", systemImage: "eye") {
                    feedKind = .showStories
                }
                Button("Job Listings", systemImage: "briefcase") {
                    feedKind = .jobStories
                }
            }
            // Icons match their text, not the app's orange tint.
            .tint(.primary)
        }
    }

    /// Pull-to-refresh. The feed's id list is cached for a couple of minutes
    /// so opening it is instant; a pull is an explicit ask for the current
    /// ranking, so it fetches a fresh list first, which the reload then reads.
    private func refreshFeed() async {
        _ = await HackerNewsAPI.refreshStoryIds(kind: feedKind)
        await feed.reload()
        // A refresh is when stories read since the last one drop out.
        withAnimation { applyFilters() }
    }

    /// Hands the feed the reader's filters, with a fresh snapshot of which
    /// stories they've read and hidden.
    private func applyFilters() {
        feed.applyFilters(
            filters,
            context: FeedFilterContext(recentlyViewed: recentlyViewedStore, interactions: interactionStore)
        )
    }

    /// Hides a story from the reader's feeds, offering it back for a moment.
    private func hide(_ story: StoryModel) {
        interactionStore.setHidden(true, for: story.id)
        withAnimation { lastHidden = story }
    }

    private func undoHide(_ story: StoryModel) {
        interactionStore.setHidden(false, for: story.id)
        withAnimation { lastHidden = nil }
    }

    /// A menu toggle's binding for one filter.
    private func isOn(_ filter: FeedFilter) -> Binding<Bool> {
        Binding {
            filters.contains(filter)
        } set: { isOn in
            filters.set(filter, isOn: isOn)
        }
    }
}

/// Confirms a story was hidden and offers it back: a small glass capsule over
/// the bottom of the feed, as Mail and Photos confirm a removal.
private struct HiddenStoryBanner: View {
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Label("Story Hidden", systemImage: "eye.slash")
                .font(.subheadline.weight(.medium))
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
                .tint(.orange)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
