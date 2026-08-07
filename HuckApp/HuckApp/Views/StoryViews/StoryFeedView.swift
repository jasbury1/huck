//
//  StoryFeedView.swift
//  HuckApp
//
//  Created by James Asbury on 12/24/25.
//

import SwiftUI
import LinkPresentation
import UniformTypeIdentifiers
import UIKit

struct StoryFeedView: View {
    @State var storyFilter: StoryFilter
    @State var observableStories = StoriesFeedData()

    /// Backing text for the search field revealed by pulling the feed down.
    @State private var searchText = ""

    /// The story whose "More" swipe action was tapped, driving the options
    /// pop-up. Non-nil while the confirmation dialog is presented.
    @State private var moreOptionsStory: StoryModel?

    @Binding var path: NavigationPath
    
    var body: some View {
        List {
            ForEach(observableStories.storyIds, id: \.self) { id in
                StoryCellView(model: observableStories.model(for: id), path: $path)
                    // As each row appears, warm the thumbnails of the rows just
                    // below it so they are ready before they scroll into view.
                    .onAppear {
                        Task { await observableStories.prefetchThumbnailsAhead(after: id) }
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
                            // TODO: Mark this story read
                        } label: {
                            Label("Mark Read", systemImage: "checkmark.circle")
                        }
                        .tint(.indigo)
                    }
                    // Trailing swipe exposes Upvote, Save, and More. Upvote is
                    // listed first so a full swipe triggers it. All stubbed.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            // TODO: Upvote this story
                        } label: {
                            Label("Upvote", systemImage: "arrow.up")
                        }
                        .tint(.orange)
                        Button {
                            // TODO: Save this story
                        } label: {
                            Label("Save", systemImage: "bookmark")
                        }
                        .tint(.green)
                        Button {
                            moreOptionsStory = observableStories.model(for: id)
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                        .tint(.gray)
                    }
            }
        }
        .listStyle(.plain)
        // "More" swipe action pop-up. Rendered as a floating popover on iPad
        // and adapts to a sheet on iPhone. Presenting the tapped story lets
        // each action operate on it directly.
        .popover(
            isPresented: Binding(
                get: { moreOptionsStory != nil },
                set: { if !$0 { moreOptionsStory = nil } }
            )
        ) {
            if let story = moreOptionsStory {
                moreOptionsMenu(for: story)
            }
        }
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
            await observableStories.fetchStoryIds(filter: storyFilter)
        }
        .task (id: storyFilter) {
            await self.observableStories.fetchStoryIds(filter: storyFilter)
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

    /// The options list shown by the "More" swipe action's popover.
    private func moreOptionsMenu(for story: StoryModel) -> some View {
        List {
            Button {
                // Link posts copy the article URL; text posts (no URL) fall
                // back to the story's Hacker News discussion page.
                UIPasteboard.general.url = story.url
                    ?? URL(string: "https://news.ycombinator.com/item?id=\(story.id)")
                moreOptionsStory = nil
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        }
        .listStyle(.plain)
        .frame(minWidth: 260, minHeight: 60)
        .presentationDetents([.height(120)])
    }
}

@Observable
class StoriesFeedData {
    private(set) var storyIds: [Int] = []

    /// Populated view models, retained across cell recycling and keyed by story
    /// id. Because a recycled row reads its already-populated model from here
    /// (synchronously) rather than rebuilding an empty one and awaiting the
    /// cache, scrolling back to a story shows its content immediately instead
    /// of flashing the placeholder.
    private var models: [Int: StoryModel] = [:]

    /// The retained model for a story id. Every id in `storyIds` has an entry,
    /// created in `fetchStoryIds`, so this is a pure synchronous read.
    func model(for id: Int) -> StoryModel {
        models[id] ?? StoryModel(id: id)
    }

    /// Warms thumbnails for the window of stories following `id`. Called as each
    /// row appears; already-cached or in-flight thumbnails are skipped, so the
    /// overlapping windows from adjacent rows stay cheap.
    func prefetchThumbnailsAhead(after id: Int) async {
        guard let index = storyIds.firstIndex(of: id) else { return }
        let start = index + 1
        guard start < storyIds.count else { return }
        let end = min(start + HackerNewsAPI.thumbnailPrefetchWindow, storyIds.count)
        await HackerNewsAPI.prefetchThumbnails(ids: Array(storyIds[start..<end]))
    }

    func fetchStoryIds(filter: StoryFilter) async {
        let ids = await HackerNewsAPI.getStoryIds(filter: filter)

        // Create a model per id up front (reusing any we already hold), so rows
        // always find a retained instance. Set models before storyIds so the
        // list never reads an id that has no model yet.
        var updated: [Int: StoryModel] = [:]
        for id in ids {
            updated[id] = models[id] ?? StoryModel(id: id)
        }
        models = updated
        storyIds = ids

        // Prioritise the first screen: warm its details, then its thumbnails,
        // before touching the rest of the feed. Story details all share
        // URLSession.shared's ~6 connections per host, so warming the whole feed
        // first would saturate them and starve the visible rows' own fetches —
        // and a thumbnail can't start until its story's URL has been fetched.
        let firstWindow = Array(ids.prefix(HackerNewsAPI.thumbnailPrefetchWindow))
        await HackerNewsAPI.prefetchStories(ids: firstWindow)
        await HackerNewsAPI.prefetchThumbnails(ids: firstWindow)

        // With the top of the feed responsive, warm the remaining story details
        // in the background. Already-cached ids (the first window) are skipped.
        await HackerNewsAPI.prefetchStories(ids: ids)
    }
}
