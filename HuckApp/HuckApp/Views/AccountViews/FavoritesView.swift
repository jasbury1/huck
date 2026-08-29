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

    /// This user's favorited stories, paged in and prefetched by `StoryFeed`.
    @State private var favorites: StoryFeed

    init(username: String, path: Binding<NavigationPath>) {
        self.username = username
        self._path = path
        self._favorites = State(initialValue: .favorites(username: username))
    }

    /// Whether these favorites belong to the logged-in user, which changes the
    /// title from a possessive name to "Your favorites".
    private var isCurrentUser: Bool {
        username == UserSession.shared?.username
    }

    private var title: String {
        isCurrentUser ? "Your favorites" : "\(username)'s favorites"
    }

    var body: some View {
        TabableContentView(title: title, postsFeed: favorites, path: $path)
    }
}

#Preview {
    NavigationStack {
        FavoritesView(username: "zdw", path: .constant(NavigationPath()))
    }
    .environment(InteractionStore())
    .environment(RecentlyViewedStore())
}
