//
//  StoryCellNavigator.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import SwiftUI

enum ItemNavigation: Hashable {
    case linkStory(id: Int, url: URL)
    case textStory(id: Int)
    case userProfile(user: String)
}

struct StoryDetailsView: View {
    let navigation: ItemNavigation
    
    init(from navigation: ItemNavigation) {
        self.navigation = navigation
    }
    
    var body: some View {
        switch navigation {
        case let .linkStory(_, url):
            StoryWebView(url: url)
        case let .textStory(id):
            StoryTextView(storyId: id)
        case let .userProfile(user):
            UserView(username: user)
        }
    }
}
