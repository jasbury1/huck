//
//  TrendingReposCache.swift
//  HuckApp
//
//  Created by James Asbury on 11/1/26.
//

import Foundation

/// Caches the "Trending repos" ranking, behind the API facade.
///
/// Building it takes an Algolia search plus three feed lists (the lists come
/// from `StoryListCache`, so they're usually free). The ranking only shifts as
/// stories age and climb, so it's kept for a while rather than rebuilt on
/// every open.
actor TrendingReposCache {
    static let shared = TrendingReposCache()

    private let timeToLive: TimeInterval = 15 * 60

    /// Hits requested from Algolia. A week of GitHub stories with some
    /// traction is a few hundred, so one request covers it.
    private let candidateLimit = 300

    private var ids: [Int] = []
    private var fetchedAt: Date?
    /// The build in progress, so opens during one share its requests.
    private var inFlight: Task<[Int], Never>?

    private init() {}

    /// The trending repos' story ids, from memory when fresh, otherwise built.
    func storyIDs() async -> [Int] {
        if let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < timeToLive {
            return ids
        }
        if let inFlight { return await inFlight.value }

        let limit = candidateLimit
        let task = Task { await Self.build(candidateLimit: limit) }
        inFlight = task
        let built = await task.value
        inFlight = nil
        // An empty result is a failed build; keep what was held rather than
        // caching the failure for the whole time-to-live.
        guard !built.isEmpty else { return ids }
        ids = built
        fetchedAt = .now
        return built
    }

    private static func build(candidateLimit: Int) async -> [Int] {
        let now = Date.now
        async let top = HackerNewsAPI.getStoryIds(kind: .topStories)
        async let show = HackerNewsAPI.getStoryIds(kind: .showStories)
        async let best = HackerNewsAPI.getStoryIds(kind: .bestStories)
        async let hits = AlgoliaAPIService.getRecentLinkStories(
            domain: "github.com",
            since: now.addingTimeInterval(-TrendingRepos.window),
            minPoints: TrendingRepos.minimumPoints,
            hitsPerPage: candidateLimit
        )

        let candidates = await hits.compactMap { hit -> TrendingRepos.Candidate? in
            guard let id = Int(hit.objectID), let url = hit.url else { return nil }
            return TrendingRepos.Candidate(
                id: id,
                url: url,
                points: hit.points ?? 0,
                createdAt: Date(timeIntervalSince1970: TimeInterval(hit.createdAtI))
            )
        }
        return TrendingRepos.rank(candidates, top: await top, show: await show, best: await best, now: now)
    }
}
