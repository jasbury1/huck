//
//  FirebaseThreadWalker.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import Foundation

/// Loads a story's comment thread from the realtime Firebase API, streaming it in
/// reading order so the top of the page fills first and the on-screen list only ever
/// grows downward — it never reflows content the reader is already looking at.
///
/// Firebase serves one item per request and only reveals a comment's children once
/// that comment has been fetched, so the whole thread can't arrive at once. Two
/// independent policies shape how it streams in:
///
///  - **Fetch order** — a priority frontier keyed by each comment's pre-order *path*
///    (its position in the flattened, depth-first list). Round trips are spent
///    completing the top of the thread first, while spare concurrency warms whatever
///    comes next. See `PreorderPath`.
///  - **Reveal** — only the contiguous, fully-loaded pre-order *prefix* is emitted.
///    Because a prefix can only ever be extended, each snapshot is a strict append to
///    the previous one, which is what keeps the list from jumping. See `settledPrefix`.
///
/// The two are deliberately separate: fetch order is a performance concern (fill the
/// visible region fast), reveal is a correctness concern (never move existing rows).
struct FirebaseThreadWalker {
    /// The story's top-level comment ids, in display order.
    let rootKids: [Int]

    /// Upper bound on concurrent Firebase `item` requests, so a large thread never
    /// fans out into hundreds of simultaneous requests.
    var maxConcurrentFetches = 16

    /// Walks the thread, calling `emit` with each append-only snapshot as it grows, and
    /// returns the final, complete list. `emit` is invoked on the walker's own executor;
    /// callers that touch UI should hop to the main actor.
    @discardableResult
    func walk(emit: ([Comment]) -> Void) async -> [Comment] {
        guard !rootKids.isEmpty else {
            emit([])
            return []
        }

        // Every fetched item, keyed by id — including deleted/dead ones, so the reveal
        // pass can tell "excluded" apart from "not fetched yet".
        var items = [Int: FirebaseCommentData]()
        // Built `Comment`s, reused across snapshots so object identity stays stable and
        // we don't reallocate the whole list on every emission.
        var built = [Int: Comment]()
        // Discovered-but-unfetched comments, ordered by pre-order path.
        var frontier = MinHeap<FrontierNode> { $0.path < $1.path }
        for (index, id) in rootKids.enumerated() {
            frontier.insert(FrontierNode(path: PreorderPath([index]), id: id))
        }

        // Returns the cached `Comment` for an item, building it on first use.
        func comment(for id: Int, data: FirebaseCommentData, level: Int) -> Comment {
            if let existing = built[id] { return existing }
            let comment = Comment(firebase: data, nestingLevel: level)
            built[id] = comment
            return comment
        }

        // The contiguous, fully-loaded pre-order prefix: a depth-first traversal that
        // stops at the first not-yet-fetched node. Deleted/dead comments (and their
        // subtrees) are skipped without ending the prefix — only a genuinely missing
        // item is a "hole". The result is always a prefix of the final list, so it can
        // only grow at its tail.
        func settledPrefix() -> [Comment] {
            var result = [Comment]()
            var hitHole = false
            func visit(_ id: Int, _ level: Int) {
                guard !hitHole else { return }
                guard let data = items[id] else { hitHole = true; return }
                guard data.deleted != true, data.dead != true else { return }
                result.append(comment(for: id, data: data, level: level))
                for kid in data.kids ?? [] {
                    if hitHole { return }
                    visit(kid, level + 1)
                }
            }
            for id in rootKids {
                if hitHole { break }
                visit(id, 0)
            }
            return result
        }

        var revealedCount = 0
        var lastSnapshot = [Comment]()

        await withTaskGroup(of: FetchedNode.self) { group in
            var inFlight = 0

            // Seed the concurrency budget with the highest-priority pending nodes.
            while inFlight < maxConcurrentFetches, let node = frontier.popMin() {
                group.addTask {
                    FetchedNode(path: node.path, id: node.id, data: await FirebaseAPIService.getCommentAsync(id: node.id))
                }
                inFlight += 1
            }

            while let fetched = await group.next() {
                inFlight -= 1

                if let data = fetched.data {
                    items[fetched.id] = data
                    // Enqueue a live comment's children at the next pre-order level.
                    // Deleted/dead comments contribute no visible subtree, matching the
                    // reveal pass, so we don't chase their children.
                    if data.deleted != true, data.dead != true, let kids = data.kids {
                        for (index, kid) in kids.enumerated() {
                            frontier.insert(FrontierNode(path: fetched.path.appending(index), id: kid))
                        }
                    }
                }

                // Emit only when the revealed prefix actually grew, so we never emit a
                // no-op and each emission is a real append.
                let snapshot = settledPrefix()
                if snapshot.count > revealedCount {
                    revealedCount = snapshot.count
                    lastSnapshot = snapshot
                    emit(snapshot)
                }

                // Backfill the freed slot(s) with the next pending nodes.
                while inFlight < maxConcurrentFetches, let node = frontier.popMin() {
                    group.addTask {
                        FetchedNode(path: node.path, id: node.id, data: await FirebaseAPIService.getCommentAsync(id: node.id))
                    }
                    inFlight += 1
                }
            }
        }

        return lastSnapshot
    }
}

// MARK: - Pre-order path

/// A comment's position in the flattened, depth-first thread, expressed as the sequence
/// of sibling indices from the root (e.g. `[0, 3, 1]` = the 1st top-level comment, its
/// 4th reply, that reply's 2nd reply). Comparing paths lexicographically yields exactly
/// pre-order (reading) order, which is what the frontier prioritises by.
private struct PreorderPath: Comparable {
    let indices: [Int]

    init(_ indices: [Int]) {
        self.indices = indices
    }

    func appending(_ index: Int) -> PreorderPath {
        PreorderPath(indices + [index])
    }

    static func < (lhs: PreorderPath, rhs: PreorderPath) -> Bool {
        lhs.indices.lexicographicallyPrecedes(rhs.indices)
    }
}

/// A pending comment in the frontier: its id and where it belongs in reading order.
private struct FrontierNode {
    let path: PreorderPath
    let id: Int
}

/// The result of one Firebase fetch, carrying the path so children can be enqueued at
/// the correct pre-order position.
private struct FetchedNode {
    let path: PreorderPath
    let id: Int
    let data: FirebaseCommentData?
}
