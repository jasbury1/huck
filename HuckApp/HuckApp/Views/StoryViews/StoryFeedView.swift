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
    @State var storyFilter: StoryFilter
    @State private var feed: StoryFeed

    /// Whether the first page has been loaded. Guards the load `.task`, which
    /// SwiftUI also re-runs when the view reappears after navigating back — a
    /// reappear must leave the feed (and its scroll position) untouched. Filter
    /// changes are handled separately by `.onChange`, which doesn't fire on reappear.
    @State private var hasLoaded = false

    /// Backing text for the search field revealed by pulling the feed down.
    @State private var searchText = ""

    /// The story whose "More" swipe action was tapped, driving the options
    /// pop-up. Non-nil while the confirmation dialog is presented.
    @State private var moreOptionsStory: StoryModel?

    /// Upvote and favorite actions (each handles the login gate and the toggle).
    @Environment(\.upvote) private var upvote
    @Environment(\.favorite) private var favorite

    /// Per-user recently-viewed record. "Mark Read" records a story here so its
    /// title greys in the feed, the same treatment an opened story gets.
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore

    @Binding var path: NavigationPath

    init(storyFilter: StoryFilter, path: Binding<NavigationPath>) {
        self._storyFilter = State(initialValue: storyFilter)
        self._path = path
        self._feed = State(initialValue: .topStories(filter: storyFilter))
    }

    var body: some View {
        List {
            ForEach(feed.stories) { story in
                StoryCellView(model: story, path: $path)
                    // As each row appears, warm the details and thumbnails of the
                    // rows just below it so they are ready before they scroll in.
                    .onAppear {
                        Task { await feed.prefetchAhead(after: story.id) }
                    }
                    // Leading swipe hides or marks the story read; a full swipe
                    // hides it. Hide is listed first so it's the full-swipe
                    // action. Behavior is stubbed for now.
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            // TODO: Hide this story
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
                    // Trailing swipe exposes Upvote, Save, and More. Upvote is
                    // listed first so a full swipe triggers it. All stubbed.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
                        Button {
                            moreOptionsStory = story
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                        .tint(.gray)
                    }
            }
        }
        .listStyle(.plain)
        // "More" swipe action pop-up, shared with the story text view.
        .storyOptionsPopover(for: $moreOptionsStory)
        // A small pull-down reveals the search field (it stays hidden while
        // scrolled, per the drawer's automatic display mode); pulling further
        // triggers the refresh below.
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search \(storyFilter.searchName)"
        )
        // Pull-to-refresh re-fetches the current filter's story ids.
        .refreshable {
            await feed.reload()
        }
        .task {
            // First-page load only. `.task` also re-runs when the view reappears
            // after navigating back, so the guard keeps that from reloading — the
            // feed and its scroll position survive the round trip.
            guard !hasLoaded else { return }
            hasLoaded = true
            await feed.loadMore()
        }
        .onChange(of: storyFilter) {
            // A real filter change swaps in a fresh feed (a different id source)
            // and pages it in. Unlike `.task`, `.onChange` never fires on reappear.
            feed = .topStories(filter: storyFilter)
            Task { await feed.loadMore() }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // No action for now
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .navigationTitle(storyFilter.displayName())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            Button("Top", systemImage: "arrow.up") {
                storyFilter = .topStories
            }
            Button("Best", systemImage: "trophy") {
                storyFilter = .bestStories
            }
            Button("New", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                storyFilter = .newStories
            }
            Divider()
            Button("Ask Hacker News", systemImage: "questionmark.bubble") {
                storyFilter = .askStories
            }
            Button("Show Hacker News", systemImage: "eye") {
                storyFilter = .showStories
            }
            Button("Job Listings", systemImage: "briefcase") {
                storyFilter = .jobStories
            }
        }
    }

}
