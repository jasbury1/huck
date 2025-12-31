//
//  UserTabs.swift
//  HuckApp
//
//  Created by James Asbury on 12/31/25.
//

import SwiftUI

enum UserTab: CaseIterable, Hashable, Equatable {
    case posts
    case comments
    case favorites
    
    var title: LocalizedStringKey {
        return switch self {
        case .posts:
            "Posts"
        case .comments:
            "Comments"
        case .favorites:
            "Favorites"
        }
    }
}
