//
//  FixtureTransportTests.swift
//  HuckTests
//

import Foundation
@testable import Huck
import Testing

struct FixtureTransportTests {
    // MARK: Keys

    private func key(_ url: String, method: String = "GET") -> String? {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        return FixtureStore.key(for: request)
    }

    @Test func queryOrderDoesNotMatter() {
        #expect(key("https://hn.algolia.com/api/v1/search?page=0&tags=story")
            == key("https://hn.algolia.com/api/v1/search?tags=story&page=0"))
    }

    @Test func methodMatters() {
        #expect(key("https://news.ycombinator.com/comment", method: "POST")
            != key("https://news.ycombinator.com/comment"))
    }

    @Test func timeBoundsAreWildcarded() {
        // "Stories from the last week" is a different number every time it's asked.
        let lastWeek = key("https://hn.algolia.com/api/v1/search?numericFilters=created_at_i%3E1730000000,points%3E=50")
        let laterWeek = key("https://hn.algolia.com/api/v1/search?numericFilters=created_at_i%3E1731000000,points%3E=50")
        #expect(lastWeek == laterWeek)
        #expect(lastWeek != key("https://hn.algolia.com/api/v1/search?numericFilters=created_at_i%3E1730000000,points%3E=60"))
    }

    // MARK: Replay

    private let store = FixtureStore.bundled

    @Test func debugBuildsBundleALargeRecording() throws {
        let store = try #require(store)
        #expect(store.count > 1000)
    }

    @Test func servesARecordedResponse() async throws {
        let transport = try FixtureTransport(store: #require(store))
        let url = try #require(URL(string: FirebaseAPIService.storyIdsURL(kind: .topStories)))
        let (data, response) = try await transport.data(for: URLRequest(url: url))
        #expect(response.statusCode == 200)
        #expect(try JSONDecoder().decode([Int].self, from: data).count > 100)
    }

    @Test func answersAnUnrecordedRequestWithNotFound() async throws {
        let transport = try FixtureTransport(store: #require(store))
        let url = try #require(URL(string: "https://hacker-news.firebaseio.com/v0/item/1.json?print=nothing-recorded"))
        let (_, response) = try await transport.data(for: URLRequest(url: url))
        #expect(response.statusCode == 404)
    }

    @Test func refusesWritesWithoutSendingThem() async throws {
        let transport = try FixtureTransport(store: #require(store))
        var request = try URLRequest(url: #require(URL(string: "https://news.ycombinator.com/comment")))
        request.httpMethod = "POST"
        let (data, response) = try await transport.data(for: request, kind: .write, endpoint: nil)
        // HN refuses a write by re-rendering its form with a 200, not a 302.
        #expect(response.statusCode == 200)
        #expect(data.isEmpty)
    }
}
