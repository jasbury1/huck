//
//  UserComment.swift
//  HuckApp
//
//  Created by James Asbury on 8/1/26.
//

import Foundation

/// A comment outside its thread — on its author's profile, or in search results.
///
/// This is a domain type produced by `HackerNewsAPI` — it is intentionally
/// decoupled from any single API service's response format.
struct UserComment: Identifiable {
    let id: Int
    /// Who wrote it. Redundant on a profile, where every row is the same person,
    /// but the row is shared with search results where it's the whole point.
    let author: String
    let text: String
    let storyTitle: String?
    let storyId: Int?
    let timestamp: Date
}
