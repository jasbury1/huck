//
//  MinHeap.swift
//  HuckApp
//
//  Created by James Asbury on 8/29/26.
//

import Foundation

/// A minimal binary min-heap ordered by a caller-supplied comparator.
///
/// The standard library ships no heap, so this fills the gap for the handful of
/// places that need an efficient priority queue (e.g. the comment-thread fetch
/// frontier in `FirebaseThreadWalker`). Insert and remove-min are O(log n), which a
/// plain sorted array can't match once the collection grows.
///
/// The comparator defines "higher priority": `precedes(a, b) == true` means `a` comes
/// out before `b`. Pass `{ $0 < $1 }` for a classic min-heap over `Comparable` values.
struct MinHeap<Element> {
    private var storage: [Element] = []
    private let precedes: (Element, Element) -> Bool

    init(precedes: @escaping (Element, Element) -> Bool) {
        self.precedes = precedes
    }

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }

    mutating func insert(_ element: Element) {
        storage.append(element)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard precedes(storage[child], storage[parent]) else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func popMin() -> Element? {
        guard let root = storage.first else { return nil }
        let last = storage.removeLast()
        guard !storage.isEmpty else { return root }

        storage[0] = last
        let count = storage.count
        var parent = 0
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var smallest = parent
            if left < count, precedes(storage[left], storage[smallest]) { smallest = left }
            if right < count, precedes(storage[right], storage[smallest]) { smallest = right }
            guard smallest != parent else { break }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
        return root
    }
}
