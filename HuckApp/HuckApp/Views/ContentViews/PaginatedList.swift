//
//  PaginatedList.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

/// Renders a `PaginatedFeed` as a lazy, infinitely-scrolling list: one caller-
/// supplied row per item, a divider between them, and a trailing spinner that
/// loads the next page as it comes into view. Pairs with `PaginatedFeed` to
/// remove the duplicated list-plumbing that each activity tab used to repeat.
struct PaginatedList<Element: Identifiable, Row: View>: View {
    /// The feed to render. Owned (as `@State`) by the parent; read here so
    /// SwiftUI observes its `items`/`hasMore` and refreshes as pages arrive.
    let feed: PaginatedFeed<Element>
    /// Shown once the feed has finished loading with no items.
    let emptyState: EmptyFeedView
    @ViewBuilder let row: (Element) -> Row

    var body: some View {
        if feed.items.isEmpty && !feed.hasMore {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(feed.items) { element in
                    row(element)
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
