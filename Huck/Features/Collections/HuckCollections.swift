//
//  HuckCollections.swift
//  Huck
//
//  Created by James Asbury on 8/29/26.
//

import SwiftUI

/// A collection's icon: either an SF Symbol or a template asset (a monochrome
/// image tinted like an SF Symbol). Lets curated collections carry a brand mark
/// — e.g. the GitHub logo — alongside the usual system symbols.
enum CollectionSymbol: Hashable {
    case system(String)
    case asset(String)

    /// The tintable icon, sized to sit alongside SF Symbols in a `Label`.
    @ViewBuilder
    var image: some View {
        switch self {
        case let .system(name):
            Image(systemName: name)
        case let .asset(name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        }
    }
}

/// A Huck-curated collection: an app-provided, read-only list of stories shown in
/// the home feed's "Huck's Collections" section. Unlike a user's `StoryCollection`
/// these aren't editable or synced; the stories are computed on demand.
struct HuckCollection: Identifiable, Hashable {
    /// Where a collection's stories come from.
    enum Source: Hashable {
        /// GitHub repos Hacker News is talking about — see `TrendingRepos`.
        case trendingRepos
    }

    /// A stable slug, used as the navigation value.
    let id: String
    let name: String
    let symbol: CollectionSymbol
    let source: Source

    /// The collection's story ids, best first.
    func storyIDs(using api: any HackerNewsService) async -> [Int] {
        switch source {
        case .trendingRepos:
            await api.getTrendingRepoStoryIds()
        }
    }
}

/// The curated collections, in display order. A static catalog for now.
enum HuckCollections {
    static let all: [HuckCollection] = [
        HuckCollection(
            id: "trending-repos",
            name: "Trending repos",
            symbol: .asset("GitHubMark"),
            source: .trendingRepos
        ),
    ]

    /// The curated collection for a navigation slug, if any.
    static func collection(id: String) -> HuckCollection? {
        all.first { $0.id == id }
    }
}
