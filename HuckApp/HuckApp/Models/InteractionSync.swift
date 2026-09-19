//
//  InteractionSync.swift
//  HuckApp
//
//  Created by James Asbury on 9/19/26.
//

import Foundation

/// Brings the user's interaction state back in line with the server.
///
/// `InteractionStore` owns what the app believes about upvotes and favorites and
/// keeps that belief correct as the user acts *in the app*. It still drifts:
/// favoriting on the web, on another device, or before this install leaves the
/// local sets behind, so a story shows a grey heart it should not (or keeps a red
/// one after being unfavorited elsewhere). This type closes that gap by re-reading
/// the authoritative `/upvoted` and `/favorites` lists and folding them back in.
///
/// It is deliberately the only thing in the app that fetches those lists purely to
/// reconcile — every other read of them rides a screen the user opened. So its cost
/// is kept small and predictable: at most `maxPages` requests per list, no more
/// often than `minimumInterval`, and never more than one pass at a time.
@MainActor
@Observable
final class InteractionSync {
    /// Whether a pass is currently running, for callers that want to show progress.
    private(set) var isSyncing = false

    private let store: InteractionStore

    /// How much of each list to walk. Two pages is the 60 most recent entries —
    /// where drift realistically is — and bounds a pass at four requests. Anything
    /// older reconciles when the user scrolls Favorites or Likes to the end.
    private let maxPages = 2

    /// The floor between passes. Pull-to-refresh is a cheap gesture to repeat, and
    /// this keeps a flurry of them from becoming a flurry of scrapes.
    private let minimumInterval: Duration = .seconds(60)

    /// When the last pass finished, for `minimumInterval`. A continuous clock so
    /// time spent backgrounded counts toward the interval.
    private var lastSync: ContinuousClock.Instant?

    /// The pass in flight, so concurrent callers share it rather than stacking up.
    private var pass: Task<Void, Never>?

    init(store: InteractionStore) {
        self.store = store
    }

    /// Reconciles upvotes and favorites — unless a pass is already running, in
    /// which case this awaits that one, or one finished within `minimumInterval`,
    /// in which case it does nothing. Cheap to call from any refresh point.
    func refresh() async {
        if let pass {
            await pass.value
            return
        }
        if let lastSync, lastSync.duration(to: .now) < minimumInterval { return }

        let pass = Task { await sync() }
        self.pass = pass
        await pass.value
        self.pass = nil
        lastSync = .now
    }

    /// One reconciliation pass over both lists. No-op when logged out: these lists
    /// are per-user, and `/upvoted` is only visible to its owner.
    private func sync() async {
        guard let username = UserSession.shared?.username else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Read through the store's paged readers rather than the API directly, so
        // each page lands in the same reconciliation the Likes and Favorites
        // screens use — including its guards against removing anything on a
        // partial or failed walk.
        await walk { await self.store.likedStories(page: $0) }
        await walk { await self.store.favoriteStories(username: username, page: $0) }
    }

    /// Reads pages in order until the list ends or `maxPages` is reached. A page
    /// that fails to load reports no further pages, ending the walk — and the
    /// store, which sees the same failure, won't treat it as the end of the list.
    private func walk(_ readPage: (Int) async -> (ids: [Int], hasMore: Bool)) async {
        for page in 0..<maxPages {
            guard await readPage(page).hasMore else { return }
        }
    }
}
