//
//  StoryCellNavigator.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import SwiftUI

enum ItemNavigation: Hashable {
    case textStory(id: Int)
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
        case let .textStory(id):
            StoryTextView(storyId: id, path: $path)
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
