//
//  MinHeapTests.swift
//  HuckTests
//

@testable import Huck
import Testing

struct MinHeapTests {
    @Test func popsInComparatorOrder() {
        var heap = MinHeap<Int>(precedes: <)
        for value in [5, 3, 8, 1, 9, 2, 7] {
            heap.insert(value)
        }
        var popped: [Int] = []
        while let value = heap.popMin() {
            popped.append(value)
        }
        #expect(popped == [1, 2, 3, 5, 7, 8, 9])
        #expect(heap.isEmpty)
    }

    @Test func honorsACustomComparator() {
        var heap = MinHeap<Int>(precedes: >)
        [2, 9, 4].forEach { heap.insert($0) }
        #expect(heap.count == 3)
        #expect(heap.popMin() == 9)
    }

    @Test func popFromEmptyHeapIsNil() {
        var heap = MinHeap<Int>(precedes: <)
        #expect(heap.popMin() == nil)
    }
}
