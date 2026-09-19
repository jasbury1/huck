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

    @Environment(InteractionStore.self) private var interactionStore

    /// The current user's liked stories, paged in and prefetched by `StoryFeed`.
    /// Built on appear rather than in `init` because the feed reconciles through
    /// `InteractionStore`, which is only reachable from the environment once the
    /// view is on screen. Kept as a single instance thereafter.
    @State private var liked: StoryFeed?

    var body: some View {
        Group {
            if let liked {
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
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            liked = liked ?? .liked(in: interactionStore)
        }
    }
}

#Preview {
    NavigationStack {
        LikedView(path: .constant(NavigationPath()))
    }
    .environment(InteractionStore())
    .environment(RecentlyViewedStore())
}
