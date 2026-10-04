//
//  StoryCellNavigator.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import SwiftUI

enum ItemNavigation: Hashable {
    /// A story's comments. `scrollTo` optionally names a comment to bring into
    /// view once the thread has loaded, for opening one in context from
    /// somewhere else in the app.
    case textStory(id: Int, scrollTo: Int? = nil)
    /// An item known only by its id — a story or a comment, as a link to
    /// Hacker News gives no hint which — opened in its thread once resolved.
    case item(id: Int)
    case userProfile(user: String)
    case favorites(user: String)
    case liked
    case collection(id: UUID)
    case huckCollection(id: String)
}

extension ItemNavigation {
    /// Where a link to Hacker News itself leads within the app, or `nil` for
    /// any other page, which is left to the browser.
    ///
    /// Covers items (`item?id=`) and profiles (`user?id=`). An item link
    /// carrying a comment as its fragment — HN's "context" links — opens onto
    /// that comment rather than the item the page is for.
    init?(hackerNewsURL url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == HackerNewsAPI.baseUri.host(),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value
        else { return nil }

        switch components.path {
        case "/item":
            guard let itemID = Int(id) else { return nil }
            self = .item(id: components.fragment.flatMap(Int.init) ?? itemID)
        case "/user":
            self = .userProfile(user: id)
        default:
            return nil
        }
    }
}

struct StoryDetailsView: View {
    let navigation: ItemNavigation
    @Binding var path: NavigationPath

    init(from navigation: ItemNavigation, path: Binding<NavigationPath>) {
        self.navigation = navigation
        self._path = path
    }

    var body: some View {
        switch navigation {
        case let .textStory(id, scrollTo):
            StoryTextView(storyId: id, path: $path, scrollTo: scrollTo)
        case let .item(id):
            LinkedItemView(itemID: id, path: $path)
        case let .userProfile(user):
            UserView(username: user, path: $path)
        case let .favorites(user):
            FavoritesView(username: user, path: $path)
        case .liked:
            LikedView(path: $path)
        case let .collection(id):
            CollectionView(collectionID: id, path: $path)
        case let .huckCollection(id):
            if let collection = HuckCollections.collection(id: id) {
                HuckCollectionView(collection: collection, path: $path)
            }
        }
    }
}
