//
//  HackerNewsService.swift
//  Huck
//
//  Created by James Asbury on 11/8/26.
//

import SwiftUI

/// Everything the app asks of Hacker News, in domain types only.
///
/// `HackerNewsAPI` is the implementation. Which one the app runs — over the
/// network, or over recorded fixtures for tests and previews — is decided once
/// at launch and handed down through the environment (`\.hackerNews`):
///
/// - Views read it with `@Environment(\.hackerNews)`.
/// - App-wide stores (`UserSession`, `InteractionStore`) are given it when
///   they're created.
/// - Models a view drives (`StoryFeed`, `PaginatedFeed`, `StoryModel`,
///   `CommentFetcher`, `PollModel`) are handed it with each call that needs
///   it, by the view driving them — they're often built in a view's `init`,
///   before the environment is available.
protocol HackerNewsService: Sendable {
    // MARK: Stories

    /// A feed's ranked story ids, from a short-lived cache while fresh.
    func getStoryIds(kind: FeedKind) async -> [Int]
    /// A feed's current ranking, bypassing the cache, for pull-to-refresh.
    func refreshStoryIds(kind: FeedKind) async -> [Int]
    /// The story ids of the GitHub repos Hacker News is talking about.
    func getTrendingRepoStoryIds() async -> [Int]
    /// Warms the main feeds at launch.
    func warmLaunchFeeds() async
    /// A story's details, from the cache when available.
    func getStory(id: Int) async -> StoryDetails?
    /// Warms the story cache ahead of display.
    func prefetchStories(ids: [Int]) async
    /// The titles of the given stories, keyed by id.
    func storyTitles(ids: [Int]) async -> [Int: String]
    /// Warms thumbnails for the given stories ahead of display.
    func prefetchThumbnails(ids: [Int]) async
    /// A linked page's thumbnail, or `nil` if none could be loaded.
    func thumbnail(for pageURL: URL) async -> UIImage?

    // MARK: Comments

    /// Drops the cached thread and story, so the next reads fetch them fresh.
    func invalidateThread(for id: Int) async
    /// Progressively-growing, append-only snapshots of a story's thread.
    func streamComments(for id: Int) -> AsyncStream<[Comment]>
    /// The thread an item belongs to, and the comment within it.
    func threadLocation(ofItem id: Int) async -> ThreadLocation?
    /// The commenters on a story whose accounts Hacker News marks as new.
    func newUsers(inThread id: Int) async -> Set<String>

    // MARK: Search

    func searchStoryIds(
        query: String,
        tags: [String],
        numericFilters: [String],
        page: Int
    ) async -> (ids: [Int], hasMore: Bool)
    func searchComments(
        query: String,
        tags: [String],
        numericFilters: [String],
        page: Int
    ) async -> (comments: [UserComment], hasMore: Bool)

    // MARK: Users

    func getUser(for username: String) async -> User?
    /// Finds a user by name, tolerating the capitalisation someone typed.
    func findUser(named username: String) async -> User?
    func getUserStories(username: String, page: Int) async -> (ids: [Int], hasMore: Bool)
    func getUserComments(username: String, page: Int) async -> (comments: [UserComment], hasMore: Bool)
    /// The signed-in user's upvoted stories; `nil` if the page couldn't be read.
    func getLikedStories(username: String, page: Int) async -> (ids: [Int], hasMore: Bool)?
    /// The signed-in user's upvoted comments; `nil` if the page couldn't be read.
    func getLikedComments(username: String, page: Int) async -> (comments: [UserComment], hasMore: Bool)?
    /// A user's public favorites; `nil` if the page couldn't be read.
    func getFavoriteStories(username: String, page: Int) async -> (ids: [Int], hasMore: Bool)?
    /// The points on one of the signed-in user's own comments.
    func ownCommentScore(id: Int, username: String) async -> Int?

    // MARK: Voting and favorites

    func upvoteStory(id: Int) async throws
    func unvoteStory(id: Int) async throws
    func upvoteComment(id: Int) async throws
    func unvoteComment(id: Int) async throws
    func favoriteStory(id: Int) async throws
    func unfavoriteStory(id: Int) async throws

    // MARK: Polls

    func getPollOptions(ids: [Int]) async -> [PollOption]
    func pollBallot(pollID: Int, optionIDs: [Int]) async -> PollBallot?
    func setPollVote(optionID: Int, voted: Bool, ballot: PollBallot) async throws

    // MARK: Writing

    func postComment(parentId: Int, storyId: Int, text: String) async throws
    func submitStory(title: String, url: String, text: String, username: String) async throws -> SubmissionOutcome
    func deleteComment(id: Int, storyId: Int) async throws
    /// The id Hacker News assigned to a comment the user posted.
    func findPostedCommentId(username: String, parentID: Int) async -> Int?

    // MARK: Authentication

    func login(username: String, password: String) async throws
    func logout(username: String)
}

extension HackerNewsService {
    // The first page, for callers that only ever read one.

    func searchStoryIds(query: String, tags: [String], numericFilters: [String]) async -> (ids: [Int], hasMore: Bool) {
        await searchStoryIds(query: query, tags: tags, numericFilters: numericFilters, page: 0)
    }

    func getUserStories(username: String) async -> (ids: [Int], hasMore: Bool) {
        await getUserStories(username: username, page: 0)
    }

    func getUserComments(username: String) async -> (comments: [UserComment], hasMore: Bool) {
        await getUserComments(username: username, page: 0)
    }
}

extension EnvironmentValues {
    /// The Hacker News the app talks to. Set once at the root from the launch
    /// configuration; the network-backed API otherwise.
    @Entry var hackerNews: any HackerNewsService = HackerNewsAPI.live
}
