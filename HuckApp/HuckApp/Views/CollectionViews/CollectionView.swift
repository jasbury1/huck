//
//  CollectionView.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import SwiftUI

/// Shows the stories in one of the user's collections, in the order they were
/// added. Rows navigate like any story cell; a trailing swipe removes the story
/// from the collection.
struct CollectionView: View {
    let collectionID: StoryCollection.ID
    @Binding var path: NavigationPath

    @Environment(CollectionsStore.self) private var collectionsStore

    /// A one-page feed over the collection's ids, reloaded when its contents
    /// change so newly added (or removed) stories appear. Kept as a single
    /// instance and only ever `reload()`ed — never rebuilt — to preserve its
    /// `StoryModel` cache, the same rule as the recently-viewed feed.
    @State private var feed: StoryFeed?

    private var collection: StoryCollection? {
        collectionsStore.collections.first { $0.id == collectionID }
    }

    var body: some View {
        Group {
            if let feed {
                List {
                    ForEach(feed.stories) { story in
                        StoryCellView(model: story, path: $path)
                            .onAppear {
                                Task { await feed.prefetchAhead(after: story.id) }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    collectionsStore.removeStory(story.id, from: collectionID)
                                    Task { await feed.reload() }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if feed.stories.isEmpty && !feed.hasMore {
                        EmptyFeedView(
                            title: "No Stories",
                            systemImage: "folder",
                            description: "Add stories from a story's “More” menu to see them here."
                        )
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(collection?.name ?? "Collection")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let feed = feed ?? StoryFeed.collection(collectionID, in: collectionsStore)
            self.feed = feed
            await feed.reload()
        }
    }
}
