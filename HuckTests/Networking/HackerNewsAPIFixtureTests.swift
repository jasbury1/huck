//
//  HackerNewsAPIFixtureTests.swift
//  HuckTests
//

import Foundation
@testable import Huck
import Testing

/// The whole API layer — services, parsing, caches, facade — over the
/// recorded fixtures, so it's exercised against real Algolia, Firebase and
/// Hacker News responses without touching the network.
///
/// The assertions are about shape, not content: the recording is re-made
/// from the live site from time to time, so which stories it holds changes,
/// but what any response must look like doesn't.
@MainActor
struct HackerNewsAPIFixtureTests {
    private let store: FixtureStore
    private let api: HackerNewsAPI

    init() throws {
        store = try #require(FixtureStore.bundled, "Debug builds bundle Huck/Fixtures.bundle")
        api = HackerNewsAPI(transport: FixtureTransport(store: store))
    }

    // MARK: Stories

    @Test(arguments: [FeedKind.topStories, .bestStories, .newStories, .showStories])
    func feedsListTheirStories(kind: FeedKind) async {
        let ids = await api.getStoryIds(kind: kind)
        #expect(ids.count > 50)
        #expect(Set(ids).count == ids.count, "A feed lists each story once")
    }

    @Test func storiesAreMappedToDomainDetails() async throws {
        let ids = await api.getStoryIds(kind: .topStories)
        let story = try #require(await api.getStory(id: ids[0]))
        #expect(!story.title.isEmpty)
        #expect(!story.by.isEmpty)
        #expect(story.timestamp < .now)
        // A link has no body of its own; a text post has no link.
        #expect(story.url == nil || story.text.isEmpty)
    }

    // MARK: Users

    @Test func readsAProfile() async throws {
        let user = try #require(await api.getUser(for: "pg"))
        #expect(user.username == "pg")
        #expect(user.karma > 0)
    }

    @Test func findsAUserTypedWithACapital() async throws {
        // Only "pg" is recorded: the miss on "Pg" retries lowercased.
        let user = try #require(await api.findUser(named: "Pg"))
        #expect(user.username == "pg")
    }

    @Test func pagesThroughAUsersStories() async {
        var seen = Set<Int>()
        for page in 0..<3 {
            let result = await api.getUserStories(username: "pg", page: page)
            #expect(result.ids.count == 20)
            #expect(result.hasMore)
            #expect(seen.isDisjoint(with: result.ids), "Page \(page) repeats an earlier page")
            seen.formUnion(result.ids)
        }
    }

    @Test func readsAUsersComments() async {
        let result = await api.getUserComments(username: "pg", page: 0)
        #expect(result.comments.count == 20)
        #expect(result.hasMore)
        for comment in result.comments {
            #expect(comment.author == "pg")
            #expect(!comment.text.isEmpty)
            #expect(!comment.text.contains("<p>"), "HTML is converted to Markdown")
        }
    }

    @Test func readsAnEmptyFavoritesPageAsEmptyNotFailed() async throws {
        // A news.ycombinator.com page, parsed from its HTML. pg has favorited
        // nothing, and that must come back as an empty last page: `nil` means
        // the page couldn't be read, and a caller treating the two alike
        // would wrongly discard a list it failed to load.
        let page = try #require(await api.getFavoriteStories(username: "pg", page: 0))
        #expect(page.ids.isEmpty)
        #expect(!page.hasMore)
    }

    // MARK: Search

    @Test func searchesStoriesAndComments() async {
        let stories = await api.searchStoryIds(query: "swift", tags: ["story"], numericFilters: [], page: 0)
        #expect(!stories.ids.isEmpty)
        let comments = await api.searchComments(query: "swift", tags: ["comment"], numericFilters: [], page: 0)
        #expect(!comments.comments.isEmpty)
    }

    // MARK: Threads

    /// The threads the recording opened, by story id.
    private var recordedThreadIDs: [Int] {
        store.keys.compactMap { key in
            key.firstMatch(of: /api\/v1\/items\/(\d+)$/).flatMap { Int($0.output.1) }
        }
    }

    @Test func streamsRecordedThreadsInReadingOrder() async throws {
        let threads = recordedThreadIDs
        try #require(!threads.isEmpty, "The recording opens a few threads")
        for id in threads {
            var final: [Huck.Comment] = []
            for await snapshot in api.streamComments(for: id) {
                // Each snapshot only ever adds to the one before.
                #expect(snapshot.count >= final.count)
                #expect(zip(final, snapshot).allSatisfy { $0.id == $1.id })
                final = snapshot
            }
            #expect(!final.isEmpty, "Thread \(id) has comments")
            // Pre-order: a thread starts at the top level, and each comment is
            // at most one level deeper than the one before it.
            #expect(final.first?.nestingLevel == 0)
            for (previous, next) in zip(final, final.dropFirst()) {
                #expect(next.nestingLevel <= previous.nestingLevel + 1)
            }
        }
    }

    // MARK: Writing

    @Test func writesNeedASignedInReader() async {
        // Never sent: there's no credential, and the fixtures refuse writes anyway.
        await #expect(throws: APIError.self) {
            try await api.postComment(parentId: 1, storyId: 1, text: "Hello")
        }
    }
}
