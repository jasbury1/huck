//
//  FavoritesView.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

struct FavoritesView: View {
    let username: String

    /// Whether these favorites belong to the logged-in user, which changes the
    /// title from a possessive name to "Your favorites".
    private var isCurrentUser: Bool {
        username == UserSession.shared?.username
    }

    private var title: String {
        isCurrentUser ? "Your favorites" : "\(username)'s favorites"
    }

    var body: some View {
        TabableContentView(title: title)
    }
}

#Preview {
    NavigationStack {
        FavoritesView(username: "zdw")
    }
}
