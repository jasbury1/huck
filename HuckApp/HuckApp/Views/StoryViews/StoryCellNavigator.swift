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
    case userProfile(user: String)
    case favorites(user: String)
    case liked
    case collection(id: UUID)
    case huckCollection(id: String)
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
