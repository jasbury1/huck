//
//  LikedView.swift
//  HuckApp
//
//  Created by James Asbury on 8/30/26.
//

import SwiftUI

/// The logged-in user's liked (upvoted) stories. HN exposes the `/upvoted` list
/// only to its owner, so — unlike `FavoritesView` — this takes no username and is
/// always the current user's own likes.
struct LikedView: View {
    @Binding var path: NavigationPath

    /// The current user's liked stories, paged in and prefetched by `StoryFeed`.
    @State private var liked: StoryFeed

    init(path: Binding<NavigationPath>) {
        self._path = path
        self._liked = State(initialValue: .liked())
    }

    var body: some View {
        TabableContentView(
            title: "Your likes",
            postsFeed: liked,
            postsEmptyState: EmptyFeedView(
                title: "No Liked Posts",
                systemImage: "arrow.up",
                description: "Stories you like will show up here."
            ),
            commentsEmptyState: EmptyFeedView(
                title: "No Liked Comments",
                systemImage: "bubble.left.and.bubble.right",
                description: "Comments you like will show up here."
            ),
            path: $path
        )
    }
}

#Preview {
    NavigationStack {
        LikedView(path: .constant(NavigationPath()))
    }
    .environment(InteractionStore())
    .environment(RecentlyViewedStore())
}
