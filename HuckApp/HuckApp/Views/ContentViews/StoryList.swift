//
//  StoryList.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

/// Renders a `StoryFeed` as a lazy, infinitely-scrolling column of story cells.
/// As each row appears it warms the details of the rows just below it, and a
/// trailing spinner pages in more as it scrolls into view. A `LazyVStack` (not
/// a `List`) so it drops into custom scroll containers such as `UserView`'s
/// collapsing-header pager.
struct StoryList: View {
    /// The feed to render. Owned (as `@State`) by the parent; read here so
    /// SwiftUI observes its `stories`/`hasMore` and refreshes as pages arrive.
    let feed: StoryFeed
    @Binding var path: NavigationPath
    /// Shown once the feed has finished loading with no stories.
    let emptyState: EmptyFeedView

    var body: some View {
        if feed.stories.isEmpty && !feed.hasMore {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(feed.stories) { story in
                    StoryCellView(model: story, path: $path)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        // Warm the window of stories below this row before they scroll in.
                        .onAppear {
                            Task { await feed.prefetchAhead(after: story.id) }
                        }
                    Divider()
                }
                // Only realised (and thus only triggers a load) once the list has
                // scrolled to the end while more pages remain.
                if feed.hasMore {
                    ProgressView()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            Task { await feed.loadMore() }
                        }
                }
            }
        }
    }
}
