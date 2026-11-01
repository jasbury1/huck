//
//  TrendingRepos.swift
//  HuckApp
//
//  Created by James Asbury on 11/1/26.
//

import Foundation

/// The ranking behind the "Trending repos" collection: which GitHub
/// repositories Hacker News is talking about right now.
///
/// Pure, so the policy lives in one readable place with no network in it —
/// `TrendingReposCache` gathers the inputs and hands them here.
///
/// Each repo is scored by the story that submitted it: Hacker News-style
/// gravity (points, decaying with age) multiplied up by where the story sits
/// in the Top, Show HN and Best lists. Gravity favors what's rising now; the
/// list bonuses reward stories the front pages are showing at this moment.
nonisolated enum TrendingRepos {
    /// A story whose link might be a repository.
    struct Candidate: Sendable {
        let id: Int
        let url: String
        let points: Int
        let createdAt: Date
    }

    /// How many repos the collection holds.
    static let limit = 30

    /// How far back candidates are drawn from.
    static let window: TimeInterval = 7 * 24 * 60 * 60

    /// The fewest points a story needs to be considered — keeps the one-line
    /// Algolia request to stories with some traction.
    static let minimumPoints = 10

    /// How steeply points decay with age. Gentler than Hacker News's own 1.8,
    /// since the window is a week rather than a day.
    private static let gravity = 1.4

    /// The depth of the Firebase lists, which a rank's weight falls away over.
    private static let listDepth = 500.0

    /// What being on each list is worth at the top of it, scaling down to
    /// nothing at the bottom.
    private static let topBonus = 1.0
    private static let showBonus = 0.6
    private static let bestBonus = 0.4

    /// The story ids of the trending repos, best first. `top`, `show` and
    /// `best` are the ranked id lists of those feeds. A repo submitted more
    /// than once is represented by its highest-scoring submission.
    static func rank(
        _ candidates: [Candidate],
        top: [Int],
        show: [Int],
        best: [Int],
        now: Date = .now,
        limit: Int = TrendingRepos.limit
    ) -> [Int] {
        let topRanks = ranks(of: top)
        let showRanks = ranks(of: show)
        let bestRanks = ranks(of: best)

        var bestByRepo: [String: (id: Int, score: Double)] = [:]
        for candidate in candidates {
            guard let repo = repositoryKey(for: candidate.url) else { continue }
            let bonus = topBonus * weight(of: candidate.id, in: topRanks)
                + showBonus * weight(of: candidate.id, in: showRanks)
                + bestBonus * weight(of: candidate.id, in: bestRanks)
            let ageHours = max(0, now.timeIntervalSince(candidate.createdAt) / 3600)
            let base = Double(max(0, candidate.points - 1)) / pow(ageHours + 2, gravity)
            let score = base * (1 + bonus)

            if let existing = bestByRepo[repo], existing.score >= score { continue }
            bestByRepo[repo] = (candidate.id, score)
        }

        return bestByRepo.values
            .sorted { ($0.score, $0.id) > ($1.score, $1.id) }
            .prefix(limit)
            .map(\.id)
    }

    // MARK: - Lists

    /// Each id's zero-based position in a list.
    private static func ranks(of ids: [Int]) -> [Int: Int] {
        Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
    }

    /// 1 at the head of a list, falling to 0 at its depth; 0 if absent.
    private static func weight(of id: Int, in ranks: [Int: Int]) -> Double {
        guard let rank = ranks[id] else { return 0 }
        return max(0, 1 - Double(rank) / listDepth)
    }

    // MARK: - Repositories

    /// Paths under `github.com/<owner>/<repo>/` that still point at the repo
    /// itself rather than one of its issues, pull requests, and so on.
    private static let repositoryViews: Set<String> = ["tree", "blob", "releases"]

    /// First path components that are GitHub's own pages, not owners.
    private static let reservedOwners: Set<String> = [
        "about", "apps", "collections", "customer-stories", "enterprise", "explore",
        "features", "login", "marketplace", "new", "notifications", "orgs", "pricing",
        "pulls", "issues", "readme", "search", "security", "settings", "site",
        "solutions", "sponsors", "topics", "trending",
    ]

    /// A repository's identity — lowercased `owner/repo` — if the link points
    /// at one, otherwise `nil`. Gists, profiles, GitHub's own pages, and links
    /// into a repo's issues or pull requests don't count.
    static func repositoryKey(for urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host()?.lowercased(),
              host == "github.com" || host == "www.github.com" else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, !reservedOwners.contains(parts[0].lowercased()) else { return nil }
        if parts.count > 2, !repositoryViews.contains(parts[2]) { return nil }

        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard !repo.isEmpty else { return nil }
        return "\(parts[0])/\(repo)".lowercased()
    }
}
