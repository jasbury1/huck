//
//  AsyncSemaphore.swift
//  HuckApp
//
//  Created by James Asbury on 10/3/26.
//

import Foundation

/// A minimal LIFO async semaphore for bounding concurrent work, such as
/// network fetches kicked off by rows as they scroll into view. Callers
/// `wait()` before starting work and `signal()` when done.
///
/// Waiters are resumed most-recent-first. When the user scrolls fast, every
/// passed row queues a fetch; serving newest-first means the rows now on screen
/// (whose requests arrived last) get the network ahead of the stale backlog of
/// rows already scrolled past — and prefetch-ahead work naturally yields to a
/// row scrolling into view. The trade-off is that the oldest waiters can be
/// starved while requests keep arriving, which is acceptable for that use:
/// those are off-screen fetches, and once scrolling stops the backlog drains.
actor AsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        available = value
    }

    func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeLast().resume()
        }
    }
}
