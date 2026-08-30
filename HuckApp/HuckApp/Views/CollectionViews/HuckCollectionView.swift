//
//  HuckCollectionView.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import SwiftUI

/// Shows the stories in a Huck-curated collection. Read-only (no add/remove),
/// unlike the user's own `CollectionView`.
struct HuckCollectionView: View {
    let collection: HuckCollection
    @Binding var path: NavigationPath

    /// A one-page feed over the curated ids. Kept as a single instance and only
    /// `reload()`ed to preserve its `StoryModel` cache, the same rule as the
    /// other id-list feeds.
    @State private var feed: StoryFeed?

    var body: some View {
        Group {
            if let feed {
                List {
                    ForEach(feed.stories) { story in
                        StoryCellView(model: story, path: $path)
                            .onAppear {
                                Task { await feed.prefetchAhead(after: story.id) }
                            }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if feed.stories.isEmpty && !feed.hasMore {
                        EmptyFeedView(
                            title: "Nothing Here Yet",
                            systemImage: "sparkles",
                            description: "Huck's picks for “\(collection.name)” are on the way."
                        )
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let feed = feed ?? StoryFeed.fixed(collection.storyIDs)
            self.feed = feed
            await feed.reload()
        }
    }
}
