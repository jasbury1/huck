//
//  UserComment.swift
//  HuckApp
//
//  Created by James Asbury on 8/1/26.
//

import Foundation

/// A comment authored by a user, as shown on their profile.
///
/// This is a domain type produced by `HackerNewsAPI` — it is intentionally
/// decoupled from any single API service's response format.
struct UserComment: Identifiable {
    let id: Int
    let text: String
    let storyTitle: String?
    let storyId: Int?
    let timestamp: Date
}
