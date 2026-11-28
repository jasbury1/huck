//
//  CommentFetcherTests.swift
//  HuckTests
//

@testable import Huck
import Testing

@MainActor
struct CommentFetcherTests {
    @Test func aThreadNotYetLoadedIsntEmpty() {
        // Before the first load, no comments means none yet — not none at all,
        // so the thread shows a spinner rather than "No comments yet."
        let fetcher = CommentFetcher(id: 1)
        #expect(!fetcher.hasLoaded)
        #expect(!fetcher.isEmpty)
    }
}
