//
//  ListRowFramesTests.swift
//  HuckTests
//

@testable import Huck
import SwiftUI
import Testing

struct ListRowFramesTests {
    private func rows(_ frames: [Int: CGFloat], height: CGFloat = 100) -> ListRowFrames {
        let rowFrames = ListRowFrames(space: .named("test"))
        for (id, minY) in frames {
            rowFrames.update(id, frame: CGRect(x: 0, y: minY, width: 400, height: height))
        }
        return rowFrames
    }

    @Test func findsTheFirstRowStartingBelowAPoint() throws {
        let rowFrames = rows([1: 0, 2: 100, 3: 200, 4: 300])
        let row = try #require(rowFrames.firstRow(startingAtOrBelow: 150))
        #expect(row.id as? Int == 3)
        #expect(row.frame.minY == 200)
    }

    @Test func aRowStartingExactlyAtThePointCounts() {
        let rowFrames = rows([1: 0, 2: 100])
        #expect(rowFrames.firstRow(startingAtOrBelow: 100)?.id as? Int == 2)
    }

    @Test func nothingBelowThePointFindsNothing() {
        #expect(rows([1: 0, 2: 100]).firstRow(startingAtOrBelow: 150) == nil)
    }

    @Test func aRowNoLongerLaidOutIsForgotten() {
        let rowFrames = rows([1: 0, 2: 100, 3: 200])
        rowFrames.update(2, frame: nil)
        #expect(rowFrames.firstRow(startingAtOrBelow: 50)?.id as? Int == 3)
    }

    @Test func aMovedRowIsFoundWhereItNowSits() {
        let rowFrames = rows([1: 0, 2: 100])
        rowFrames.update(1, frame: CGRect(x: 0, y: 500, width: 400, height: 100))
        #expect(rowFrames.firstRow(startingAtOrBelow: 50)?.id as? Int == 2)
        #expect(rowFrames.firstRow(startingAtOrBelow: 150)?.id as? Int == 1)
    }
}
