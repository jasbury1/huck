//
//  UserTabs.swift
//  HuckApp
//
//  Created by James Asbury on 12/31/25.
//

import SwiftUI

enum ContentTab: CaseIterable, Hashable, Equatable {
    case posts
    case comments
    case recentlyViewed

    var title: LocalizedStringKey {
        return switch self {
        case .posts:
            "Posts"
        case .comments:
            "Comments"
        case .recentlyViewed:
            "Recently viewed"
        }
    }

    /// The SF Symbol shown in the tab's pill. Always visible; the title only
    /// appears when the pill is selected.
    var systemImage: String {
        return switch self {
        case .posts:
            "newspaper.fill"
        case .comments:
            "bubble.left.and.bubble.right.fill"
        case .recentlyViewed:
            "clock.fill"
        }
    }

    /// The pill's fill color when selected, à la the Mail app's category tabs.
    var color: Color {
        return switch self {
        case .posts:
            .orange
        case .comments:
            .blue
        case .recentlyViewed:
            .purple
        }
    }
}
