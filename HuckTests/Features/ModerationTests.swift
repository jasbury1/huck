//
//  ModerationTests.swift
//  HuckTests
//

import Foundation
@testable import Huck
import Testing

/// Flagging's scrape of an item page, and blocking's effect on a thread.
@MainActor
struct ModerationTests {
    // MARK: Flag tokens

    /// Answers every request with the same HTML page.
    private struct PageTransport: HTTPTransport {
        let html: String

        func data(for request: URLRequest, kind: RequestKind, endpoint: String?) async throws -> (Data, HTTPURLResponse) {
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(html.utf8), response)
        }
    }

    private func flagAuth(forItem id: Int, onPage html: String) async -> (auth: String, alreadyFlagged: Bool)? {
        await NewsYCService(transport: PageTransport(html: html)).flagAuth(forItem: id)
    }

    @Test func readsAnItemsFlagToken() async throws {
        let html = #"<a href="flag?id=123&amp;auth=abc123&amp;goto=item%3Fid%3D123">flag</a>"#
        let result = try #require(await flagAuth(forItem: 123, onPage: html))
        #expect(result.auth == "abc123")
        #expect(!result.alreadyFlagged)
    }

    @Test func readsThatAnItemIsAlreadyFlagged() async throws {
        let html = #"<a href="flag?id=123&amp;un=t&amp;auth=abc123&amp;goto=item%3Fid%3D123">unflag</a>"#
        let result = try #require(await flagAuth(forItem: 123, onPage: html))
        #expect(result.alreadyFlagged)
    }

    @Test func ignoresAnotherItemsFlagLink() async {
        // Item 1234's link must not be taken for item 123's.
        let html = #"<a href="flag?id=1234&amp;auth=def456&amp;goto=item%3Fid%3D1234">flag</a>"#
        #expect(await flagAuth(forItem: 123, onPage: html) == nil)
    }

    @Test func findsNoTokenWithoutAFlagLink() async {
        // Logged out, or an account without the karma to flag.
        #expect(await flagAuth(forItem: 123, onPage: "<html></html>") == nil)
    }

    // MARK: Blocked authors

    private func thread(_ comments: [(author: String, level: Int)]) -> CommentFetcher {
        let fetcher = CommentFetcher(id: 1)
        fetcher.comments = comments.map { Comment(posted: "text", author: $0.author, nestingLevel: $0.level) }
        return fetcher
    }

    @Test func leavesOutABlockedAuthorAndTheRepliesBeneathThem() {
        let fetcher = thread([
            ("alice", 0),
            ("troll", 1),
            ("bob", 2),
            ("carol", 1),
            ("dave", 0),
        ])
        fetcher.blockedAuthors = ["troll"]
        #expect(fetcher.visibleComments.map(\.author) == ["alice", "carol", "dave"])
    }

    @Test func showsEveryoneWhenNoOneIsBlocked() {
        let fetcher = thread([("alice", 0), ("bob", 1)])
        #expect(fetcher.visibleComments.map(\.author) == ["alice", "bob"])
    }

    @Test func keepsAStoryWhoseAuthorIsntKnownYet() {
        // Its details haven't loaded, so there's no author to judge it by.
        let story = StoryModel(id: 1)
        let context = FeedFilterContext(blockedUsernames: ["troll"])
        #expect(FeedFilter.blockedUsers.includes(story, in: context))
    }

    @Test func blockingAppliesWithoutBeingSwitchedOn() {
        #expect(FeedFilter.alwaysApplied.contains(.blockedUsers))
        #expect(!FeedFilter.toggleable.contains(.blockedUsers))
    }
}
