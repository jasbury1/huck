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

    var title: LocalizedStringKey {
        return switch self {
        case .posts:
            "Posts"
        case .comments:
            "Comments"
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
        }
    }

    /// The pill's fill color when selected, à la the Mail app's category tabs.
    var color: Color {
        return switch self {
        case .posts:
            .orange
        case .comments:
            .blue
        }
    }
}
