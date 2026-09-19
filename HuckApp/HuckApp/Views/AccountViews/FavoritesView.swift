//
//  FavoritesView.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

struct FavoritesView: View {
    let username: String
    @Binding var path: NavigationPath

    @Environment(InteractionStore.self) private var interactionStore
    @Environment(UserSession.self) private var session

    /// This user's favorited stories, paged in and prefetched by `StoryFeed`.
    /// Built on appear rather than in `init` because the feed reconciles through
    /// `InteractionStore`, which is only reachable from the environment once the
    /// view is on screen. Kept as a single instance thereafter.
    @State private var favorites: StoryFeed?

    /// Whether these favorites belong to the logged-in user, which changes the
    /// title from a possessive name to "Your favorites".
    private var isCurrentUser: Bool {
        username == session.username
    }

    private var title: String {
        isCurrentUser ? "Your favorites" : "\(username)'s favorites"
    }

    var body: some View {
        Group {
            if let favorites {
                TabableContentView(
                    title: title,
                    postsFeed: favorites,
                    postsEmptyState: EmptyFeedView(
                        title: "No Favorite Posts",
                        systemImage: "heart",
                        description: "Stories you favorite will show up here."
                    ),
                    commentsEmptyState: EmptyFeedView(
                        title: "No Favorite Comments",
                        systemImage: "bubble.left.and.bubble.right",
                        description: "Comments you favorite will show up here."
                    ),
                    path: $path
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            favorites = favorites ?? .favorites(username: username, in: interactionStore)
        }
    }
}

#Preview {
    let session = UserSession()
    NavigationStack {
        FavoritesView(username: "zdw", path: .constant(NavigationPath()))
    }
    .environment(session)
    .environment(InteractionStore(session: session))
    .environment(RecentlyViewedStore(session: session))
}
