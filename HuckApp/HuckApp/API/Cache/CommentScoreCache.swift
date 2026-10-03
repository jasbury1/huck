//
//  CommentScoreCache.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import Foundation

/// Caches the scores of the reader's own comments, behind the API facade.
///
/// Hacker News shows a comment's score only to its author, and only in page
/// markup, so every score is scraped. The cost is kept down by reading them in
/// bulk: the reader's `/threads` page lists their comments newest-first with
/// every score marked, so one request answers for a whole page of comments.
///
/// - Rows ask as they appear. The first ask starts a **walk** of `/threads`,
///   a page at a time, that continues only until the asked-for comment is
///   covered and never past `maxWalkPages`. Every score on every page read is
///   kept, so the rows that ask next are usually answered from memory. Asks
///   that arrive mid-walk wait for it rather than starting their own.
/// - A comment older than the walk reaches falls back to its own `/item`
///   page — one request, coalesced and gated, for the rare old comment.
/// - Everything expires after `timeToLive`, after which the next ask starts a
///   fresh walk from the newest page. Scores are worth showing because they
///   move, and recent comments, which move most, are all on the first page.
actor CommentScoreCache {
    static let shared = CommentScoreCache()

    private let timeToLive: TimeInterval = 2 * 60

    /// How far back a walk goes before older comments are asked for one by
    /// one instead. Deep pages are rarely needed and each costs a request.
    private let maxWalkPages = 3

    private struct Entry {
        let score: Int
        let fetchedAt: Date
    }
    private var scores: [Int: Entry] = [:]

    /// Progress through the reader's `/threads`, newest page first.
    private struct Walk {
        let username: String
        let startedAt = Date.now
        /// The lowest comment id on any page read; every comment newer than it
        /// has been seen.
        var oldestCovered = Int.max
        /// The cursor for the next page, once the first has been read.
        var next: Int?
        var pagesRead = 0
        var isFinished = false
    }
    private var walk: Walk?
    /// The page fetch in progress, which concurrent asks wait on.
    private var pageFetch: Task<Void, Never>?

    /// Single-comment fallbacks in progress, so concurrent asks share one.
    private var itemFetches: [Int: Task<Int?, Never>] = [:]
    /// Bounds concurrent fallbacks. LIFO, so rows on screen go first.
    private let gate = AsyncSemaphore(value: 2)

    private init() {}

    /// The score of one of `username`'s comments, from memory when fresh,
    /// otherwise from `/threads`, otherwise from the comment's own page.
    func score(for id: Int, username: String) async -> Int? {
        if let score = freshScore(for: id) { return score }

        await walkThreads(until: id, username: username)
        if let score = freshScore(for: id) { return score }

        // The walk read past this comment and didn't find a score: it isn't one
        // Hacker News shows (deleted, say), and its own page won't differ.
        if let walk, walk.oldestCovered <= id { return nil }
        return await fetchItemScore(id)
    }

    private func freshScore(for id: Int) -> Int? {
        guard let entry = scores[id],
              Date.now.timeIntervalSince(entry.fetchedAt) < timeToLive else { return nil }
        return entry.score
    }

    // MARK: - Walking /threads

    /// Reads `/threads` pages until one covers `id`, the pages run out, or the
    /// walk reaches its limit. Restarts a walk that's expired or belongs to
    /// another account.
    private func walkThreads(until id: Int, username: String) async {
        while true {
            // Someone else's page is on its way; it may be the one we need.
            if let pageFetch {
                await pageFetch.value
                continue
            }
            if let current = walk,
               current.username != username
                || Date.now.timeIntervalSince(current.startedAt) >= timeToLive {
                walk = nil
            }
            let current = walk ?? Walk(username: username)
            walk = current
            guard current.oldestCovered > id, !current.isFinished else { return }

            // Claimed before suspending, so asks arriving meanwhile wait on it.
            // The task releases the claim itself, before anyone waiting on it
            // wakes: if the claim were released after the await instead, a
            // waiter resuming first would find it still set, re-await the
            // finished task — which returns without yielding — and spin,
            // starving the claimant of the actor it needs to release it.
            let task = Task {
                await self.readNextPage()
                self.pageFetch = nil
            }
            pageFetch = task
            await task.value
        }
    }

    /// Reads the walk's next page and keeps every score on it.
    private func readNextPage() async {
        guard var current = walk else { return }
        let page = await NewsYCService.threadScores(username: current.username, next: current.next)
        guard let page else {
            current.isFinished = true
            walk = current
            return
        }
        for (id, score) in page.scores {
            scores[id] = Entry(score: score, fetchedAt: .now)
        }
        current.pagesRead += 1
        current.oldestCovered = min(current.oldestCovered, page.oldestID ?? .max)
        current.next = page.next
        current.isFinished = page.next == nil
            || page.oldestID == nil
            || current.pagesRead >= maxWalkPages
        walk = current
    }

    // MARK: - Fallback

    /// Reads one comment's score from its own page.
    private func fetchItemScore(_ id: Int) async -> Int? {
        if let existing = itemFetches[id] { return await existing.value }
        let gate = gate
        let task = Task {
            await gate.wait()
            let score = await NewsYCService.commentScore(id: id)
            await gate.signal()
            return score
        }
        itemFetches[id] = task
        let score = await task.value
        itemFetches[id] = nil
        if let score {
            scores[id] = Entry(score: score, fetchedAt: .now)
        }
        return score
    }
}
